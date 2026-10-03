import 'dart:math';

// `Transaction` below always means the Realtime Database one used by
// `runTransaction`; Firestore's identically named class is not used here.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/character.dart';
import '../game/challenge.dart';
import '../config.dart';
import 'firebase_errors.dart';
import 'progress_store.dart';

/// Retains actionable diagnostics without displaying a raw stack in gameplay.
class OnlineServiceFailure implements Exception {
  final String action, code, detail;
  OnlineServiceFailure(this.action, this.code, this.detail);
  String get message {
    if (code == 'not-found') return 'Online service is not configured yet.';
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return 'Online access was denied. Check sign-in and app verification.';
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return 'Online service is unreachable. Please retry.';
    }
    return 'Online service could not complete this request.';
  }

  @override
  String toString() =>
      '$action Â· $code Â· ${AppConfig.effectiveProject}/${AppConfig.functionsRegion}: $detail';
}

/// User-facing text for online failures. Never leaks raw `action Â· code Â·
/// project/region` diagnostics into toasts or inline errors; those stay in
/// debug logs and the copyable connection-details field.
String friendlyOnlineError(Object e) {
  if (e is OnlineServiceFailure) return e.message;
  final text = e.toString().replaceFirst('StateError: ', '');
  if (text.contains('firebase_functions/not-found') ||
      text.contains('not-found')) {
    return 'Online service is not configured yet.';
  }
  return text.length > 140 ? '${text.substring(0, 140)}â€¦' : text;
}

enum ControlMode { swipe, joystick }

class PlayerSettings {
  String name, country, city, language;
  bool sound;
  String character;
  int raceTarget;
  GameChoice choice;
  ControlMode control;
  final SharedPreferences prefs;
  PlayerSettings(this.prefs)
    : name = prefs.getString('name') ?? 'Pip',
      country = prefs.getString('country') ?? 'Egypt',
      city = prefs.getString('city') ?? 'Cairo',
      sound = prefs.getBool('sound') ?? true,
      language = prefs.getString('language') == 'ar' ? 'ar' : 'en',
      character =
          [
            'male',
            'female',
            'male_round',
            'female_round',
          ].contains(prefs.getString('character'))
          ? prefs.getString('character')!
          : 'male',
      raceTarget =
          ((prefs.getInt('raceTarget') ?? 100) ~/ 100).clamp(1, 10).toInt() *
          100,
      choice = GameChoice.values[(prefs.getInt('choice') ?? 0).clamp(0, 2)],
      control = ControlMode.values[(prefs.getInt('control') ?? 0).clamp(0, 1)];
  Future<void> save() async {
    await prefs.setString('name', name);
    await prefs.setString('country', country);
    await prefs.setString('city', city);
    await prefs.setBool('sound', sound);
    await prefs.setString('language', language);
    await prefs.setString('character', character);
    await prefs.setInt('raceTarget', raceTarget);
    await prefs.setInt('choice', choice.index);
    await prefs.setInt('control', control.index);
  }
}

/// A resolved matchmaking pairing, including the room id that the atomic
/// queue transaction minted and committed to both players' records.
class MatchPair {
  /// The opponent's uid.
  final String id;

  /// The opponent's display name.
  final String name;

  /// The opponent's picked character.
  final String character;

  /// The single room both players are committed to.
  final String roomId;

  const MatchPair({
    required this.id,
    required this.name,
    required this.character,
    required this.roomId,
  });
}

/// 100% client-side social backend over Realtime Database (+ Firestore
/// display names). No Cloud Functions are used anywhere.
class SocialService {
  final ProgressStore store;
  SocialService(this.store);

  static const _timeout = Duration(seconds: 8);

  /// Global matchmaking window: a queue node stays claimable for this long,
  /// and it is also the search deadline before a practice bot takes over.
  /// Kept in one place so the queue, the claim and the bot fallback agree.
  /// The product requirement is a strict 10-15s search, so this is the
  /// midpoint and is guarded by a test.
  static const matchWindowMs = 12000;

  DatabaseReference get _db => FirebaseDatabase.instance.ref();

  String _uid() {
    final id = store.uidOrNull;
    if (id == null || !store.cloud) throw StateError(store.status);
    return id;
  }

  Never _fail(Object e, String action) => throw OnlineServiceFailure(
    action,
    e is FirebaseException ? e.code : 'unavailable',
    firebaseProblem(e, service: 'Realtime Database $action'),
  );

  static String pairId(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';

  Future<String?> fetchDisplayName(String other) async {
    _uid();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(other)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      if (!doc.exists) return null;
      final name = (doc.data()!['name'] ?? '').toString().trim();
      return name.isEmpty ? null : name;
    } catch (e) {
      _fail(e, 'friends');
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriends() async {
    final uid = _uid();
    try {
      final snap = await _db.child('userFriends/$uid').get().timeout(_timeout);
      final map = snap.value as Map? ?? {};
      return map.entries
          .where((e) => e.value is Map)
          .map(
            (e) => {
              'id': e.key.toString(),
              ...Map<String, dynamic>.from(e.value as Map),
            },
          )
          .toList();
    } catch (e) {
      _fail(e, 'friends');
    }
  }

  Future<List<Map<String, dynamic>>> fetchInvites() async {
    final uid = _uid();
    try {
      final snap = await _db.child('invites/$uid').get().timeout(_timeout);
      final map = snap.value as Map? ?? {};
      final now = DateTime.now().millisecondsSinceEpoch;
      return map.entries
          .where((e) => e.value is Map)
          .map(
            (e) => {
              ...Map<String, dynamic>.from(e.value as Map),
              'from': e.key.toString(),
            },
          )
          .where((m) => ((m['expiresAt'] as num?) ?? 0).toInt() > now)
          .toList();
    } catch (e) {
      _fail(e, 'invitations');
    }
  }

  /// Adds by player ID; adopts into friendship when they already requested.
  /// Returns 'sent' or 'accepted'.
  Future<String> addFriend(String other) async {
    final uid = _uid();
    final clean = other.trim();
    if (clean.isEmpty || clean == uid || !RegExp(r'^[\w-]+$').hasMatch(clean)) {
      throw StateError('Enter another player ID.');
    }
    final name = await fetchDisplayName(clean);
    if (name == null) throw StateError('Player ID not found.');
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final pair = pairId(uid, clean);
      final existing = await _db
          .child('friendships/$pair')
          .get()
          .timeout(_timeout);
      if (existing.exists) {
        final data = Map<String, dynamic>.from(existing.value as Map);
        if (data['status'] == 'accepted') throw StateError('Already friends.');
        if (data['from'] == uid) throw StateError('Request already sent.');
        await acceptFriend(clean);
        return 'accepted';
      }
      await _db
          .child('friendships/$pair')
          .set({
            'a': uid.compareTo(clean) <= 0 ? uid : clean,
            'b': uid.compareTo(clean) <= 0 ? clean : uid,
            'from': uid,
            'status': 'pending',
            'updatedAt': now,
          })
          .timeout(_timeout);
      await _db
          .child('userFriends/$uid/$clean')
          .set({
            'name': name,
            'status': 'pending',
            'incoming': false,
            'from': uid,
            'updatedAt': now,
          })
          .timeout(_timeout);
      // Recipient mirror drives their overlay + push: they see it incoming.
      final myName = await fetchDisplayName(uid) ?? 'Player';
      await _db
          .child('userFriends/$clean/$uid')
          .set({
            'name': myName,
            'status': 'pending',
            'incoming': true,
            'from': uid,
            'updatedAt': now,
          })
          .timeout(_timeout);
      // NOTE: background delivery is handled by the self-hosted relay
      // (tools/fcm-relay-v1.js), which watches this same mirror node.
      // No push call happens here: FCM sends need server credentials that
      // must never ship inside the app.
      return 'sent';
    } on StateError {
      rethrow;
    } catch (e) {
      _fail(e, 'friends');
    }
  }

  Future<void> acceptFriend(String other) async {
    final uid = _uid();
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final pair = pairId(uid, other);
      final snap = await _db.child('friendships/$pair').get().timeout(_timeout);
      if (!snap.exists)
        throw StateError('This request is no longer available.');
      final data = Map<String, dynamic>.from(snap.value as Map);
      if (data['status'] == 'accepted') {
        // Already accepted: just refresh mirrors below.
      } else if (data['from'] == other && data['status'] == 'pending') {
        await _db
            .child('friendships/$pair')
            .update({'status': 'accepted', 'updatedAt': now})
            .timeout(_timeout);
      } else {
        throw StateError('This request is no longer available.');
      }
      final otherName = await fetchDisplayName(other) ?? 'Player';
      final myName = await fetchDisplayName(uid) ?? 'Player';
      await _db
          .child('userFriends/$uid/$other')
          .set({
            'name': otherName,
            'status': 'accepted',
            'incoming': false,
            'from': data['from'],
            'updatedAt': now,
          })
          .timeout(_timeout);
      await _db
          .child('userFriends/$other/$uid')
          .set({
            'name': myName,
            'status': 'accepted',
            'incoming': false,
            'from': data['from'],
            'updatedAt': now,
          })
          .timeout(_timeout);
    } on StateError {
      rethrow;
    } catch (e) {
      _fail(e, 'friends');
    }
  }

  Future<void> removeFriend(String other) async {
    final uid = _uid();
    try {
      await _db
          .child('friendships/${pairId(uid, other)}')
          .remove()
          .timeout(_timeout);
      await _db.child('userFriends/$uid/$other').remove().timeout(_timeout);
      await _db.child('userFriends/$other/$uid').remove().timeout(_timeout);
    } catch (e) {
      _fail(e, 'friends');
    }
  }

  Future<void> sendInvite(String other, String code) async {
    final uid = _uid();
    final cleanCode = code.trim();
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleanCode)) {
      throw StateError('Invalid invitation.');
    }
    try {
      final pair = await _db
          .child('friendships/${pairId(uid, other)}')
          .get()
          .timeout(_timeout);
      if (!pair.exists ||
          (Map<String, dynamic>.from(pair.value as Map)['status'] !=
              'accepted')) {
        throw StateError('Add this friend first.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final myName = await fetchDisplayName(uid) ?? 'Player';
      await _db
          .child('invites/$other/$uid')
          .set({
            'from': uid,
            'name': myName,
            'code': cleanCode,
            'expiresAt': now + 300000,
          })
          .timeout(_timeout);
      // Background delivery is handled by the self-hosted relay watching
      // this same invites node (tools/fcm-relay-v1.js).
    } on StateError {
      rethrow;
    } catch (e) {
      _fail(e, 'invitations');
    }
  }

  Future<void> dismissInvite(String from) async {
    final uid = _uid();
    try {
      await _db.child('invites/$uid/$from').remove().timeout(_timeout);
    } catch (e) {
      _fail(e, 'invitations');
    }
  }

  // ---- Global matchmaking queue (RTDB transactions, no Cloud Functions) ----
  //
  // Everything lives under ONE node, `matchmaking_queue`, so a single RTDB
  // transaction can rewrite the whole thing atomically:
  //
  //   matchmaking_queue/waiting/{uid}  -> a player currently searching
  //   matchmaking_queue/paired/{uid}   -> a player's resolved pairing
  //
  // [matchTryPair] runs `runTransaction` on that root and, inside the
  // transaction, picks an opponent, mints the shared room id, erases BOTH
  // waiting entries and writes BOTH paired records. Because it is a single
  // transaction, RTDB serialises it against every other claim:
  //
  //   * A cannot pair with B while C pairs with B. The second transaction
  //     re-reads the tree, finds B already gone from `waiting`, and retries.
  //   * A cannot be paired by C while A is pairing B. A is already removed
  //     from `waiting`, so C can never see it.
  //   * `roomId` is minted inside the transaction and written to both records
  //     in the same commit, so a player is never "matched but homeless" and
  //     can never be assigned a second room.
  //
  // The transaction body is pure and synchronous (map copies plus one random
  // draw), so it stays far below the 50ms budget even on a large queue, and
  // it never performs I/O inside the handler.
  //
  // `onDisconnect().remove()` on the waiting node clears entries the moment a
  // client dies, so a dead player never stalls the queue.

  /// Joins the global queue. [requestId] tags this search attempt.
  Future<void> matchPublish({
    required String requestId,
    required String mode,
    required String target,
    required String name,
    String character = 'male',
    int targetSteps = 100,
  }) async {
    final uid = _uid();
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      // If the app is killed or the network drops, remove the entry right
      // away instead of leaving a ghost player to be matched into a room that
      // can never start.
      await _db
          .child('matchmaking_queue/waiting/$uid')
          .onDisconnect()
          .remove();
      await _db
          .child('matchmaking_queue/waiting/$uid')
          .set({
            'requestId': requestId,
            'name': name.trim().isEmpty ? 'Pip' : name.trim(),
            'mode': mode == 'arcade' ? 'arcade' : 'race',
            'target': targetSteps,
            'character': Character.normalize(character),
            'createdAt': now,
            'deadline': now + matchWindowMs,
            'status': 'waiting',
          })
          .timeout(_timeout);
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  Map<String, dynamic>? _asNode(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  bool _compatible(Map<String, dynamic> mine, Map<String, dynamic> other) {
    if (other['status'] != 'waiting') return false;
    if (other['mode'] != mine['mode']) return false;
    if (mine['mode'] != 'arcade' &&
        (other['target'] as num?)?.toInt() !=
            (mine['target'] as num?)?.toInt()) {
      return false;
    }
    return true;
  }

  /// Diagnostics from the latest queue scan: live opponents seen vs
  /// mode/target-compatible ones. Lets the UI report WHY no match happened
  /// (signed out vs empty queue vs wrong mode) instead of failing silently.
  int lastQueueTotal = 0, lastQueueCompatible = 0;

  /// Atomically claims one live, compatible opponent, or returns null when
  /// nobody is available. The commit is the single source of truth: it erases
  /// both queue entries and writes both pairing records with the same
  /// `roomId`.
  Future<MatchPair?> matchTryPair({
    required String mode,
    required int target,
    required String name,
    required String character,
  }) async {
    final uid = _uid();
    final now = DateTime.now().millisecondsSinceEpoch;
    final mine = <String, dynamic>{
      'mode': mode == 'arcade' ? 'arcade' : 'race',
      'target': target,
      'character': Character.normalize(character),
      'name': name,
    };
    MatchPair? paired;
    try {
      await _db.child('matchmaking_queue').runTransaction((current) {
        paired = null;
        final tree = _asNode(current) ?? const <String, dynamic>{};
        final waiting = _asNode(tree['waiting']) ?? const <String, dynamic>{};
        final pairedNodes =
            _asNode(tree['paired']) ?? const <String, dynamic>{};

        // We must be queued ourselves and must not already hold a live room.
        final myEntry = _asNode(waiting[uid]);
        final myPair = _asNode(pairedNodes[uid]);
        if (myEntry == null) return Transaction.abort();
        if (myPair != null && myPair['status'] == 'ready') {
          return Transaction.abort();
        }

        // Diagnostics and candidate selection from the same snapshot.
        var total = 0, compatible = 0;
        final candidates = <String>[];
        for (final entry in waiting.entries) {
          final id = entry.key.toString();
          if (id == uid) continue;
          final other = _asNode(entry.value);
          if (other == null) continue;
          if (((other['deadline'] as num?) ?? 0).toInt() <= now) continue;
          total++;
          if (!_compatible(mine, other)) continue;
          compatible++;
          candidates.add(id);
        }
        lastQueueTotal = total;
        lastQueueCompatible = compatible;
        if (candidates.isEmpty) return Transaction.abort();
        // Smallest id first keeps every client converging on the same order.
        candidates.sort();
        final peerId = candidates.first;
        final peer = _asNode(waiting[peerId]);
        if (peer == null) return Transaction.abort();
        final peerName = (peer['name'] ?? 'Player').toString();
        final peerCharacter = Character.normalize(peer['character']?.toString());

        // One room id, minted here, committed to both records below.
        final roomId = Random()
            .nextInt(0xffffff)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();

        final nextWaiting = Map<String, dynamic>.from(waiting)
          ..remove(uid)
          ..remove(peerId);
        final nextPaired = Map<String, dynamic>.from(pairedNodes)
          ..[uid] = {
            'peer': peerId,
            'peerName': peerName,
            'peerCharacter': peerCharacter,
            'status': 'pending',
            'roomId': roomId,
            'at': ServerValue.timestamp,
          }
          ..[peerId] = {
            'peer': uid,
            'peerName': name.trim().isEmpty ? 'Pip' : name.trim(),
            'peerCharacter': Character.normalize(character),
            'status': 'pending',
            'roomId': roomId,
            'at': ServerValue.timestamp,
          };
        paired = MatchPair(
          id: peerId,
          name: peerName,
          character: peerCharacter,
          roomId: roomId,
        );
        return Transaction.success(<String, dynamic>{
          'waiting': nextWaiting,
          'paired': nextPaired,
        });
      }).timeout(_timeout);
    } catch (e) {
      _fail(e, 'matchmaking');
    }
    return paired;
  }

  /// Flips both pairing records to `ready` once the room node exists. The
  /// `roomId` was already committed by [matchTryPair], so this only opens the
  /// gate the joiner waits on. Guarded by a transaction, so the two sides can
  /// never disagree about the room.
  Future<void> matchAnnounceRoom({
    required String peerId,
    required String roomId,
  }) async {
    final uid = _uid();
    try {
      await _db.child('matchmaking_queue/paired').runTransaction(
        (current) {
          final paired = _asNode(current);
          if (paired == null) return Transaction.abort();
          final mine = _asNode(paired[uid]);
          final theirs = _asNode(paired[peerId]);
          if (mine == null || theirs == null) return Transaction.abort();
          // Only this exact pairing may be stamped, and only once.
          if (mine['peer'] != peerId || theirs['peer'] != uid) {
            return Transaction.abort();
          }
          if (mine['roomId'] != roomId || theirs['roomId'] != roomId) {
            return Transaction.abort();
          }
          if (mine['status'] == 'ready') return Transaction.abort();
          return Transaction.success(Map<String, dynamic>.from(paired)
            ..[uid] = {...mine, 'status': 'ready'}
            ..[peerId] = {...theirs, 'status': 'ready'});
        },
      ).timeout(_timeout);
      // Background delivery is handled by the self-hosted relay watching
      // ready pairings (tools/fcm-relay-v1.js).
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  /// My current pairing record, or `{status: waiting}` when not paired.
  Future<Map<String, dynamic>> matchPairing() async {
    final uid = _uid();
    try {
      final snap = await _db
          .child('matchmaking_queue/paired/$uid')
          .get()
          .timeout(_timeout);
      return _asNode(snap.value) ?? const {'status': 'waiting'};
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  /// Clears this pairing when the room could not be created, so the other
  /// player is released instead of waiting out the whole search window.
  Future<void> matchCancelPair({required String peerId}) async {
    final uid = _uid();
    try {
      await _db.child('matchmaking_queue/paired').runTransaction(
        (current) {
          final paired = _asNode(current);
          if (paired == null) return Transaction.abort();
          final mine = _asNode(paired[uid]);
          final theirs = _asNode(paired[peerId]);
          if (mine == null || theirs == null) return Transaction.abort();
          // Release both ends of the same pairing, and only that pairing.
          if (mine['peer'] != peerId || theirs['peer'] != uid) {
            return Transaction.abort();
          }
          return Transaction.success(Map<String, dynamic>.from(paired)
            ..[uid] = {...mine, 'status': 'cancelled', 'roomId': ''}
            ..[peerId] = {...theirs, 'status': 'cancelled', 'roomId': ''});
        },
      ).timeout(_timeout);
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  /// Leaves the queue and drops any pending pairing.
  Future<void> matchCancel() async {
    final uid = _uid();
    try {
      await _db
          .child('matchmaking_queue/waiting/$uid')
          .onDisconnect()
          .cancel();
      await _db.update({
        'matchmaking_queue/waiting/$uid': null,
        'matchmaking_queue/paired/$uid': null,
      }).timeout(_timeout);
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  /// Profile sync bypasses Cloud Functions entirely: the signed-in user's
  /// document in `users/{uid}` is written directly. Requires the `users`
  /// match in firebase/firestore.rules to be published. Never throws the
  /// functions `not-found` path.
  Future<void> register(PlayerSettings settings) async {
    final uid = store.uidOrNull;
    if (uid == null) throw StateError('Sign in first.');
    await settings.prefs.setBool('profileSyncPending', true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'name': settings.name,
            'country': settings.country,
            'city': settings.city,
            'character': settings.character,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      await settings.prefs.setBool('profileSyncPending', false);
    } on FirebaseException catch (e) {
      throw OnlineServiceFailure(
        'profile',
        e.code,
        firebaseProblem(e, service: 'Firestore users'),
      );
    } catch (e) {
      throw StateError(friendlyOnlineError(e));
    }
  }

  /// Reads the signed-in user's profile document, if any.
  Future<Map<String, dynamic>?> fetchOwnProfile() async {
    final uid = store.uidOrNull;
    if (uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;
      return Map<String, dynamic>.from(doc.data()!);
    } catch (e) {
      throw OnlineServiceFailure(
        'profile',
        e is FirebaseException ? e.code : 'unavailable',
        firebaseProblem(e, service: 'Firestore users'),
      );
    }
  }
}
