import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      '$action · $code · ${AppConfig.effectiveProject}/${AppConfig.functionsRegion}: $detail';
}

/// User-facing text for online failures. Never leaks raw `action · code ·
/// project/region` diagnostics into toasts or inline errors; those stay in
/// debug logs and the copyable connection-details field.
String friendlyOnlineError(Object e) {
  if (e is OnlineServiceFailure) return e.message;
  final text = e.toString().replaceFirst('StateError: ', '');
  if (text.contains('firebase_functions/not-found') ||
      text.contains('not-found')) {
    return 'Online service is not configured yet.';
  }
  return text.length > 140 ? '${text.substring(0, 140)}…' : text;
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

/// 100% client-side social backend over Realtime Database (+ Firestore
/// display names). No Cloud Functions are used anywhere.
class SocialService {
  final ProgressStore store;
  SocialService(this.store);

  static const _timeout = Duration(seconds: 8);

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

  // ---- Direct matchmaking queue (replaces the matchmaking function) ----
  // The lexicographically smaller uid creates the room; the larger only
  // polls. This makes double-room creation impossible without transactions.

  Future<void> matchPublish({
    required String requestId,
    required String mode,
    required int target,
    required String name,
  }) async {
    final uid = _uid();
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _db
          .child('matchQueue/$uid')
          .set({
            'requestId': requestId,
            'name': name.trim().isEmpty ? 'Pip' : name.trim(),
            'mode': mode == 'arcade' ? 'arcade' : 'race',
            'target': target,
            'createdAt': now,
            'deadline': now + 12000,
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

  /// Finds a live, compatible waiting opponent in the queue, if any.
  /// Deterministic smallest id first so both sides agree silently.
  Future<Map<String, String>?> matchScan() async {
    final uid = _uid();
    try {
      final snap = await _db.child('matchQueue').get().timeout(_timeout);
      final all = snap.value as Map? ?? {};
      final mine = _asNode(all[uid]);
      if (mine == null) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      var total = 0, compatible = 0;
      for (final entry in all.entries) {
        if (entry.key.toString() == uid) continue;
        final other = _asNode(entry.value);
        if (other == null) continue;
        if (((other['deadline'] as num?) ?? 0).toInt() <= now) continue;
        total++;
        if (_compatible(mine, other)) compatible++;
      }
      lastQueueTotal = total;
      lastQueueCompatible = compatible;
      return _scanBest(all, uid, mine, now);
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  Map<String, String>? _scanBest(
    Map all,
    String uid,
    Map<String, dynamic> mine,
    int now,
  ) {
    Map<String, String>? best;
    for (final entry in all.entries) {
      final id = entry.key.toString();
      if (id == uid) continue;
      final other = _asNode(entry.value);
      if (other == null) continue;
      if (((other['deadline'] as num?) ?? 0).toInt() <= now) continue;
      if (!_compatible(mine, other)) continue;
      final name = (other['name'] ?? 'Player').toString();
      if (best == null || id.compareTo(best['id']!) < 0)
        best = {'id': id, 'name': name};
    }
    return best;
  }

  /// Marks my queue node matched (called by the room creator).
  Future<void> matchClaimMine({
    required String code,
    required String peerId,
    required String peerName,
    required String myName,
  }) async {
    final uid = _uid();
    try {
      await _db
          .child('matchQueue/$uid')
          .update({
            'status': 'matched',
            'match': {
              'code': code,
              'participants': {uid: myName, peerId: peerName},
            },
          })
          .timeout(_timeout);
      // Background delivery is handled by the self-hosted relay watching
      // matched queue nodes (tools/fcm-relay-v1.js).
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  /// Returns `{status, code?}`: own node first, then anyone matched with me.
  Future<Map<String, dynamic>> matchPoll() async {
    final uid = _uid();
    try {
      final snap = await _db.child('matchQueue').get().timeout(_timeout);
      final all = snap.value as Map? ?? {};
      final mine = _asNode(all[uid]);
      if (mine != null && mine['status'] == 'matched') {
        final match = _asNode(mine['match']);
        if (match != null && (match['code'] ?? '').toString().isNotEmpty) {
          return {'status': 'matched', 'code': match['code'].toString()};
        }
      }
      for (final entry in all.entries) {
        final node = _asNode(entry.value);
        if (node == null ||
            node['status'] != 'matched' ||
            mine == null ||
            ((node['createdAt'] as num?) ?? 0) <
                ((mine['createdAt'] as num?) ?? 0) - 12000)
          continue;
        final match = _asNode(node['match']);
        final participants = _asNode(match?['participants']);
        if (match != null &&
            participants != null &&
            participants.containsKey(uid)) {
          return {'status': 'matched', 'code': match['code'].toString()};
        }
      }
      return {'status': mine?['status']?.toString() ?? 'waiting'};
    } catch (e) {
      _fail(e, 'matchmaking');
    }
  }

  Future<void> matchCancel() async {
    final uid = _uid();
    try {
      await _db.child('matchQueue/$uid').remove().timeout(_timeout);
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
