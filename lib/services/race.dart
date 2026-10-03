import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

import 'progress_store.dart';
import 'firebase_errors.dart';
import '../game/character.dart';
import '../game/engine.dart';
import '../game/match_result.dart';

class RaceService extends ChangeNotifier {
  final ProgressStore store;
  RaceService(this.store);
  String? code;
  Map<String, dynamic> room = {};
  StreamSubscription<DatabaseEvent>? _subscription, _clock;
  int clockOffset = 0;
  String? error;
  bool sending = false;
  bool finishSent = false;
  bool get active => code != null;
  String? get uidOrNull => store.uidOrNull;
  String get uid => store.uid;
  int get serverNow => DateTime.now().millisecondsSinceEpoch + clockOffset;
  int get startAt => (room['startAt'] as num?)?.toInt() ?? 0;
  int get effectiveSeed =>
      ((room['rematch'] as Map?)?['seed'] as num?)?.toInt() ?? seed;
  int get effectiveStartAt =>
      ((room['rematch'] as Map?)?['startAt'] as num?)?.toInt() ?? startAt;
  int get rematchRound =>
      ((room['rematch'] as Map?)?['round'] as num?)?.toInt() ?? 0;
  int get rematchVotes => (room['rematchVotes'] as Map?)?.length ?? 0;
  /// True once *this* player asked the host for a same-room rematch. Read
  /// from the room so the tick on the avatar survives navigation away from
  /// the result screen and clears only when the host starts the round.
  bool get myRematchRequested =>
      active && (room['rematchVotes'] as Map?)?[uid] == true;
  bool get started =>
      effectiveStartAt > 0 && serverNow >= effectiveStartAt + 3000;
  List<Map<String, dynamic>> get livePeers =>
      peers.where((p) => p['status'] == 'live').toList();
  List<Map<String, dynamic>> get throwEvents {
    final raw = room['throws'] as Map? ?? {};
    return raw.entries
        .where((e) => e.value is Map)
        .map(
          (e) => {
            ...Map<String, dynamic>.from(e.value as Map),
            'id': e.key.toString(),
          },
        )
        .where((e) => matchInt(e['round']) == rematchRound)
        .toList();
  }

  bool get arcade => room['mode'] == 'arcade';
  int get target => (room['target'] as num?)?.toInt() ?? 100;
  /// True as soon as ANY player has reached the finish line. Race mode stops
  /// the whole round here, so nobody can keep jumping past the first finisher.
  bool get anyAtTarget {
    if (arcade || !active) return false;
    return peers.any((p) => matchInt(p['step']) >= target);
  }
  String get winner => (room['result'] as Map?)?['winner'] as String? ?? '';
  String get winnerName =>
      peers
          .where((p) => p['id'] == winner)
          .map((p) => p['name'].toString())
          .firstOrNull ??
      'Player';
  int get seed => (room['seed'] as num?)?.toInt() ?? 1;
  List<Map<String, dynamic>> get peers {
    final raw = room['players'] as Map? ?? {};
    final list = raw.entries
        .where((e) => e.value is Map)
        .map(
          (e) => {
            ...Map<String, dynamic>.from(e.value as Map),
            'id': e.key.toString(),
          },
        )
        .toList();
    list.sort(
      (a, b) => ((b['step'] as num?) ?? 0).compareTo((a['step'] as num?) ?? 0),
    );
    return list;
  }

  bool get finished => room['result'] != null;
  DatabaseReference get ref => FirebaseDatabase.instance.ref('rooms/$code');
  Future<void> enter({
    required String name,
    String? joinCode,
    String mode = 'race',
    int target = 100,
    String character = 'male',
  }) async {
    if (!store.cloud) {
      throw StateError('Set up Firebase to enable online races.');
    }
    final uid = uidOrNull;
    if (uid == null) throw StateError('Sign in first.');
    await leave();
    error = null;
    final clean = name.trim().isEmpty
        ? 'Pip'
        : name.trim().substring(0, min(16, name.trim().length));
    try {
      if (joinCode == null) {
        bool created = false;
        for (var attempt = 0; attempt < 5 && !created; attempt++) {
          code = Random.secure()
              .nextInt(0xffffff)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase();
          final result = await ref.runTransaction((current) {
            if (current != null) return Transaction.abort();
            return Transaction.success({
              'host': uid,
              'mode': mode == 'arcade' ? 'arcade' : 'race',
              'target': (target ~/ 100).clamp(1, 10) * 100,
              'seed': Random().nextInt(0x7fffffff),
              'createdAt': ServerValue.timestamp,
              'players': {
                uid: {
                  'name': clean,
                  'x': 210,
                  'y': 623,
                  'step': 0,
                  'skin': 'pip',
                  'character': character,
                  'lives': 2,
                  'status': 'ready',
                  'round': 0,
                  'updatedAt': ServerValue.timestamp,
                },
              },
            });
          });
          created = result.committed;
        }
        if (!created) {
          code = null;
          throw StateError('Could not create a room. Try again.');
        }
      } else {
        final candidate = joinCode.trim().toUpperCase();
        if (!RegExp(r'^[A-F0-9]{6}$').hasMatch(candidate)) {
          throw StateError('Enter the six-character room code.');
        }
        code = candidate;
        try {
          final snapshot = await ref.get();
          if (!snapshot.exists) throw StateError('Room not found.');
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          if (data['startAt'] != null) {
            throw StateError('This race has already started.');
          }
          if ((data['players'] as Map).length >= 6) {
            throw StateError('Room is full.');
          }
          await ref.child('players/$uid').set({
            'name': clean,
            'x': 210,
            'y': 623,
            'step': 0,
            'skin': 'pip',
            'character': character,
            'lives': 2,
            'status': 'ready',
            'updatedAt': ServerValue.timestamp,
          });
        } catch (_) {
          code = null;
          rethrow;
        }
      }
      await watchRoom();
    } catch (e) {
      await leave();
      error = firebaseProblem(e, service: 'Realtime Database rooms');
      throw StateError(error!);
    }
  }

  /// Creates a matchmade room with all participants present (client-side
  /// matchmaking). The room auto-starts when the host taps Start.
  ///
  /// [reservedCode] is the room id the atomic matchmaking transaction already
  /// committed to both players' pairing records. Supplying it means the room
  /// id a player was promised is exactly the room they land in; when it is
  /// null a fresh code is reserved here instead.
  Future<String> createMatchRoom({
    required Map<String, String> participants,
    required String mode,
    required int target,
    /// Character per participant uid, so every racer is drawn as themselves.
    required Map<String, String> characters,
    String skin = 'pip',
    String character = 'male',
    String? reservedCode,
  }) async {
    final uid = uidOrNull;
    if (uid == null || !store.cloud) throw StateError('Sign in first.');
    if (!participants.containsKey(uid) || participants.length < 2) {
      throw StateError('Need another player first.');
    }
    await leave();
    error = null;
    try {
      String? code;
      // A code reserved by matchmaking is claimed with the same
      // first-writer-wins transaction, so a stale room cannot be hijacked.
      final seeds = reservedCode == null
          ? List.generate(
              5,
              (_) => Random.secure()
                  .nextInt(0xffffff)
                  .toRadixString(16)
                  .padLeft(6, '0')
                  .toUpperCase(),
            )
          : [reservedCode];
      for (var attempt = 0; attempt < seeds.length && code == null; attempt++) {
        final candidate = seeds[attempt];
        final result = await FirebaseDatabase.instance
            .ref('rooms/$candidate')
            .runTransaction((current) {
              if (current != null) return Transaction.abort();
              return Transaction.success({
                'host': uid,
                'mode': mode == 'arcade' ? 'arcade' : 'race',
                'target': (target ~/ 100).clamp(1, 10) * 100,
                'seed': Random().nextInt(0x7fffffff),
                'createdAt': ServerValue.timestamp,
                'players': {
                  for (final entry in participants.entries)
                    entry.key: {
                      'name': entry.value,
                      'x': 210,
                      'y': 623,
                      'step': 0,
                      'skin': entry.key == uid ? skin : 'pip',
                      // Each racer keeps their own pick. Previously every
                      // matchmade opponent was flattened to 'male', which is
                      // why only one character showed up in a real match.
                      'character': entry.key == uid
                          ? Character.normalize(character)
                          : Character.normalize(characters[entry.key]),
                      'lives': 2,
                      'status': 'ready',
                      'updatedAt': ServerValue.timestamp,
                    },
                },
              });
            });
        if (result.committed) code = candidate;
      }
      if (code == null) throw StateError('Could not create a room. Try again.');
      this.code = code;
      await watchRoom();
      return code;
    } catch (e) {
      await leave();
      error = firebaseProblem(e, service: 'Realtime Database rooms');
      throw StateError(error!);
    }
  }

  /// First-writer-wins round settlement, run by every client. Replaces the
  /// server `settleRound` trigger: whoever writes first decides, the rest
  /// abort silently on the existing result.
  Future<void> settleResult() async {
    if (!active) return;
    try {
      final snapshot = await ref.get();
      if (snapshot.value is! Map) return;
      final fresh = Map<String, dynamic>.from(snapshot.value as Map);
      final round = matchInt((fresh['rematch'] as Map?)?['round']);
      final start = matchInt(
        (fresh['rematch'] as Map?)?['startAt'] ?? fresh['startAt'],
      );
      if (serverNow < start + 3000 || start == 0) return;
      final raw = fresh['players'] as Map? ?? {};
      final players = raw.entries
          .where((e) => e.value is Map)
          .map(
            (e) => {
              ...Map<String, dynamic>.from(e.value as Map),
              'id': e.key.toString(),
            },
          )
          .toList();
      if (players.any((p) => matchInt(p['round']) != round)) return;
      // A zero/missing target would make every racer look like a finisher
      // (step >= 0), so fall back to the same default the UI uses.
      final rawTarget = matchInt(fresh['target']);
      final decision = evaluateMatch(
        players,
        target: rawTarget > 0 ? rawTarget : 100,
        arcade: fresh['mode'] == 'arcade',
      );
      if (decision == null || round != rematchRound || !active) return;
      await ref.child('result').runTransaction((current) {
        if (current != null) return Transaction.abort();
        return Transaction.success({
          'winner': decision.winner,
          'reason': decision.reason,
          'round': round,
          'settledAt': ServerValue.timestamp,
        });
      });
    } catch (e) {
      debugPrint('Settle round: $e');
    }
  }

  Future<void> attachMatch(String roomCode) async {
    if (code == roomCode && _subscription != null) return;
    final uid = uidOrNull;
    if (uid == null) throw StateError('Sign in first.');
    await leave();
    code = roomCode;
    error = null;
    try {
      final data = await ref.get();
      room = Map<String, dynamic>.from(data.value as Map);
      if (!(room['players'] as Map).containsKey(uid)) {
        throw StateError('Not a match participant.');
      }
      await watchRoom();
    } catch (_) {
      code = null;
      room = {};
      rethrow;
    }
  }

  Future<void> watchRoom() async {
    final uid = uidOrNull;
    if (uid == null) throw StateError('Sign in first.');
    final snapshot = await ref.get();
    if (snapshot.value is! Map) throw StateError('Room no longer exists.');
    room = Map<String, dynamic>.from(snapshot.value as Map);
    error = null;
    await _subscription?.cancel();
    await _clock?.cancel();
    finishSent = false;
    await ref.child('players/$uid').onDisconnect().update({
      'status': 'out',
      'updatedAt': ServerValue.timestamp,
    });
    _clock = FirebaseDatabase.instance
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((event) {
          clockOffset = (event.snapshot.value as num?)?.toInt() ?? 0;
        });
    final watchingCode = code;
    _subscription = ref.onValue.listen(
      (event) {
        if (code != watchingCode) return;
        if (!event.snapshot.exists) {
          error = 'The host closed this room.';
          room = {};
          notifyListeners();
          return;
        }
        room = Map<String, dynamic>.from(event.snapshot.value as Map);
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        error = firebaseProblem(e, service: 'Realtime Database rooms');
        notifyListeners();
      },
    );
  }

  Future<void> start() async {
    if (room['host'] != uidOrNull) throw StateError('Only the host can start.');
    if (peers.length < 2) throw StateError('Invite another player first.');
    await ref
        .child('startAt')
        .runTransaction(
          (value) => value == null
              ? Transaction.success(ServerValue.timestamp)
              : Transaction.abort(),
        );
  }

  Future<void> send(GameEngine game) async {
    final uid = uidOrNull;
    if (!active || sending || uid == null) return;
    sending = true;
    try {
      await ref.child('players/$uid').update({
        'round': rematchRound,
        'score': game.points,
        'movement': game.movementDistance.round(),
        'x': game.player.x,
        'y': game.player.y,
        'step': game.highest,
        'skin': game.progress.skin,
        'character': game.character,
        'lives': game.roundLives,
        'status': !arcade && game.highest >= target
            ? 'finished'
            : game.mode == PlayMode.spectate
            ? 'spectator'
            : game.mode == PlayMode.over
            ? 'out'
            : 'live',
        if (!arcade && game.highest >= target && !finishSent)
          'finishedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });
      if (!arcade && game.highest >= target) finishSent = true;
      error = null;
    } catch (e) {
      error = firebaseProblem(e, service: 'Realtime Database rooms');
    } finally {
      sending = false;
    }
  }

  final Map<String, int> _myThrows = {};

  /// Publishes a spectator rock throw. Returns the throw id, or null when
  /// offline. The thrower prunes its own stale throws via [pruneRocks].
  Future<String?> sendRock({
    required double x0,
    required double y0,
    required double vx,
    required double vy,
    required int t0,
  }) async {
    final uid = uidOrNull;
    if (!active ||
        uid == null ||
        finished ||
        !peers.any((p) => p['id'] == uid && p['status'] == 'spectator'))
      return null;
    try {
      final node = ref.child('throws').push();
      await node.set({
        'by': uid,
        'round': rematchRound,
        'count': 8 + Random().nextInt(8),
        'seed': Random().nextInt(0x7fffffff),
        'x0': x0,
        'y0': y0,
        'vx': vx,
        'vy': vy,
        't0': t0,
      });
      if (node.key != null) _myThrows[node.key!] = t0;
      error = null;
      return node.key;
    } catch (e) {
      error = firebaseProblem(e, service: 'Realtime Database throws');
      return null;
    }
  }

  /// Deletes own throws older than ~9s so the room log stays small.
  Future<void> pruneRocks(int nowMs) async {
    if (!active) return;
    final stale = _myThrows.entries
        .where((e) => nowMs - e.value > 9000)
        .map((e) => e.key)
        .toList();
    for (final key in stale) {
      _myThrows.remove(key);
      try {
        await ref.child('throws/$key').remove();
      } catch (_) {}
    }
  }

  /// Non-host spectators vote for a same-room rematch.
  Future<void> requestRematch() async {
    final uid = uidOrNull;
    if (!active || uid == null) throw StateError('Sign in first.');
    try {
      await ref.child('rematchVotes/$uid').set(true);
    } catch (e) {
      throw StateError(firebaseProblem(e, service: 'Realtime Database rooms'));
    }
  }

  /// Host starts a fresh round in the same room: new seed + start time,
  /// previous result and votes cleared in one atomic update.
  Future<void> startRematch() async {
    if (!active || room['host'] != uidOrNull) {
      throw StateError('Only the host can restart.');
    }
    try {
      await ref.update({
        'rematch': {
          'round': rematchRound + 1,
          'seed': Random().nextInt(0x7fffffff),
          'startAt': ServerValue.timestamp,
        },
        'result': null,
        'rematchVotes': null,
        'throws': null,
      });
      _myThrows.clear();
    } catch (e) {
      throw StateError(firebaseProblem(e, service: 'Realtime Database rooms'));
    }
  }

  /// Publishes a single status (used to mark ready on rematch apply).
  Future<void> publishStatus(String status) async {
    final uid = uidOrNull;
    if (!active || uid == null) return;
    try {
      await ref.child('players/$uid').update({
        'round': rematchRound,
        'step': 0,
        'score': 0,
        'movement': 0,
        'lives': 2,
        'finishedAt': null,
        'status': status,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      error = firebaseProblem(e, service: 'Realtime Database rooms');
    }
  }

  Future<void> leave() async {
    final old = code, host = room['host'];
    final wasStarted = effectiveStartAt > 0;
    final uid = uidOrNull;
    code = null;
    room = {};
    error = null;
    await _subscription?.cancel();
    await _clock?.cancel();
    _subscription = null;
    _clock = null;
    if (old != null && store.cloud && uid != null) {
      final previous = FirebaseDatabase.instance.ref('rooms/$old');
      try {
        await previous.child('players/$uid').onDisconnect().cancel();
        if (host == uid && !wasStarted) {
          await previous.remove();
        } else {
          if (wasStarted) {
            await previous.child('players/$uid').update({
              'status': 'out',
              'updatedAt': ServerValue.timestamp,
            });
          } else {
            await previous.child('players/$uid').remove();
          }
        }
      } catch (e) {
        debugPrint('Race leave cleanup: $e');
      }
    }
  }

  @override
  void dispose() {
    unawaited(leave());
    super.dispose();
  }
}
