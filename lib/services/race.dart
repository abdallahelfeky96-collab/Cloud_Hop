import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

import 'progress_store.dart';
import '../game/engine.dart';

class RaceService extends ChangeNotifier {
  final ProgressStore store;
  RaceService(this.store);
  String? code;
  Map<String, dynamic> room = {};
  StreamSubscription<DatabaseEvent>? _subscription, _clock;
  int clockOffset = 0;
  String? error;
  bool sending = false;
  bool get active => code != null;
  String get uid => store.uid;
  int get serverNow => DateTime.now().millisecondsSinceEpoch + clockOffset;
  int get startAt => (room['startAt'] as num?)?.toInt() ?? 0;
  bool get started => startAt > 0 && serverNow >= startAt + 3000;
  int get remaining =>
      ((startAt + 123000 - serverNow) / 1000).ceil().clamp(0, 120);
  int get seed => (room['seed'] as num?)?.toInt() ?? 1;
  List<Map<String, dynamic>> get peers {
    final raw = room['players'] as Map? ?? {};
    final list = raw.entries
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

  bool get finished =>
      started &&
      (remaining == 0 ||
          peers.isNotEmpty && peers.every((p) => p['status'] == 'out'));
  DatabaseReference get ref => FirebaseDatabase.instance.ref('rooms/$code');
  Future<void> enter({required String name, String? joinCode}) async {
    if (!store.cloud) {
      throw StateError('Set up Firebase to enable online races.');
    }
    await leave();
    error = null;
    final clean = name.trim().isEmpty
        ? 'Pip'
        : name.trim().substring(0, min(16, name.trim().length));
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
            'seed': Random().nextInt(0x7fffffff),
            'createdAt': ServerValue.timestamp,
            'players': {
              uid: {
                'name': clean,
                'x': 210,
                'y': 623,
                'step': 0,
                'skin': 'pip',
                'status': 'ready',
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
          'status': 'ready',
          'updatedAt': ServerValue.timestamp,
        });
      } catch (_) {
        code = null;
        rethrow;
      }
    }
    await watchRoom();
  }

  Future<void> attachMatch(String roomCode) async {
    await leave();
    code = roomCode;
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
    await ref.child('players/$uid').onDisconnect().update({'status': 'out'});
    _clock = FirebaseDatabase.instance
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((event) {
          clockOffset = (event.snapshot.value as num?)?.toInt() ?? 0;
        });
    _subscription = ref.onValue.listen(
      (event) {
        if (!event.snapshot.exists) {
          error = 'The host closed this room.';
          room = {};
          notifyListeners();
          return;
        }
        room = Map<String, dynamic>.from(event.snapshot.value as Map);
        notifyListeners();
      },
      onError: (Object e) {
        error = 'Race connection interrupted.';
        notifyListeners();
      },
    );
  }

  Future<void> start() async {
    if (room['host'] != uid) throw StateError('Only the host can start.');
    if (peers.length < 2) throw StateError('Invite another player first.');
    await ref.child('startAt').set(ServerValue.timestamp);
  }

  Future<void> send(GameEngine game) async {
    if (!active || sending) return;
    sending = true;
    try {
      await ref.child('players/$uid').update({
        'x': game.player.x,
        'y': game.player.y,
        'step': game.highest,
        'skin': game.progress.skin,
        'status': game.mode == PlayMode.over ? 'out' : 'live',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {
      error = 'Race connection interrupted.';
    } finally {
      sending = false;
    }
  }

  Future<void> leave() async {
    final old = code, host = room['host'];
    code = null;
    room = {};
    await _subscription?.cancel();
    await _clock?.cancel();
    _subscription = null;
    _clock = null;
    if (old != null && store.cloud) {
      final previous = FirebaseDatabase.instance.ref('rooms/$old');
      try {
        await previous.child('players/$uid').onDisconnect().cancel();
        if (host == uid) {
          await previous.remove();
        } else {
          await previous.child('players/$uid').remove();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    unawaited(leave());
    super.dispose();
  }
}
