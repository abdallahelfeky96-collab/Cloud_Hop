import 'dart:io';

import 'package:cloud_hop/services/social.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collapses runs of whitespace so structural assertions do not depend on the
/// exact indentation of the rules file.
String _flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

/// The queue must find real players anywhere, so it is a single global
/// Realtime Database node with no local network filtering. Pairing happens in
/// one RTDB transaction, and the search window is a strict 10-15 seconds
/// before a practice bot takes over.
void main() {
  test('the matchmaking window is a strict 10-15 second search', () {
    expect(SocialService.matchWindowMs, greaterThanOrEqualTo(10000));
    expect(SocialService.matchWindowMs, lessThanOrEqualTo(15000));
  });

  group('global queue rules', () {
    late String queue;
    late String waiting;
    late String paired;
    setUpAll(() {
      final rules = _flat(File('firebase/database.rules.json').readAsStringSync());
      final start = rules.indexOf('"matchmaking_queue"');
      expect(start, greaterThan(-1), reason: 'matchmaking_queue rules missing');
      final end = rules.indexOf('"matchQueue"', start);
      queue = rules.substring(start, end > start ? end : rules.length);

      final wStart = queue.indexOf('"waiting"');
      expect(wStart, greaterThan(-1), reason: 'waiting rules missing');
      final wEnd = queue.indexOf('"paired"', wStart);
      waiting = queue.substring(wStart, wEnd);
      paired = queue.substring(wEnd);
    });

    test('anyone signed in can read the whole queue', () {
      expect(queue, contains('".read": "auth != null"'));
    });

    test('no IP address or subnet filter is used', () {
      for (final banned in ['ip', 'ipAddress', 'subnet', 'localOnly', 'lan']) {
        expect(
          RegExp('"$banned"', caseSensitive: false).hasMatch(queue),
          isFalse,
          reason: 'queue must stay global, found $banned',
        );
      }
    });

    test('the queue deadline is validated and the character stays optional', () {
      expect(waiting, contains('"deadline"'));
      expect(
        waiting,
        contains(
          'newData.hasChildren([\'requestId\',\'name\',\'mode\',\'target\','
          '\'createdAt\',\'deadline\',\'status\'])',
        ),
        reason: 'a published entry must carry an expiry deadline',
      );
      // `character` is validated when present but not required, so an older
      // installed client can still publish a search during the rollout.
      expect(
        waiting,
        contains(
          '"character": { ".validate": "newData.isString() && '
          'newData.val().length > 0 && newData.val().length <= 32"',
        ),
        reason: 'character must stay optional but validated',
      );
    });

    test('a pairing cannot pair a player with itself', () {
      expect(
        paired,
        contains(r'newData.val() !== $uid'),
        reason: 'self-pairing must be rejected by the rules',
      );
    });

    test('a pairing carries exactly one room id and a known status', () {
      expect(paired, contains('"roomId"'));
      expect(
        paired,
        contains('"roomId": { ".validate": "newData.isString()'),
        reason: 'roomId must be validated, not free-form',
      );
      expect(
        paired,
        contains(
          '"status": { ".validate": "newData.val() === \'pending\' || '
          'newData.val() === \'ready\' || newData.val() === \'cancelled\'"',
        ),
      );
    });
  });

  group('atomic pairing in the client', () {
    late String client;
    late String tryPair;
    late String announceRoom;
    late String cancelPair;
    setUpAll(() {
      client = File('lib/services/social.dart').readAsStringSync();
      final t = client.indexOf('Future<MatchPair?> matchTryPair');
      final a = client.indexOf('Future<void> matchAnnounceRoom');
      final c = client.indexOf('Future<void> matchCancelPair');
      expect(t, greaterThan(-1));
      expect(a, greaterThan(t));
      expect(c, greaterThan(a));
      tryPair = client.substring(t, a);
      announceRoom = client.substring(a, c);
      cancelPair = client.substring(c, client.indexOf('Future<void> register', c));
    });

    test('pairing is a transaction on the queue root', () {
      expect(
        tryPair,
        contains("_db.child('matchmaking_queue').runTransaction"),
        reason:
            'the claim must be one transaction covering the whole queue, '
            'otherwise two players can be claimed twice',
      );
    });

    test('the transaction erases both queue entries and writes both records', () {
      // Both removals and both records are produced inside the handler, so a
      // single commit does all of it.
      expect(tryPair, contains('..remove(uid)'));
      expect(tryPair, contains('..remove(peerId)'));
      expect(tryPair, contains('..[uid] = {'));
      expect(tryPair, contains('..[peerId] = {'));
    });

    test('the room id is minted inside the transaction and shared', () {
      expect(tryPair, contains('final roomId = Random()'));
      final uses = "'roomId': roomId".allMatches(tryPair).length;
      expect(uses, 2, reason: 'both pairing records share one room id');
    });

    test('a dead client is removed from the queue immediately', () {
      final flat = _flat(client);
      expect(
        flat,
        contains(
          "child('matchmaking_queue/waiting/\$uid') .onDisconnect() .remove()",
        ),
        reason: 'a disconnected player must not stay in the queue',
      );
    });

    test('a live pairing is never re-stamped with a different room', () {
      expect(announceRoom, contains('runTransaction'));
      expect(announceRoom, contains("mine['roomId'] != roomId"));
      expect(announceRoom, contains("mine['status'] == 'ready'"));
    });

    test('a failed room only releases its own pairing', () {
      expect(cancelPair, contains('runTransaction'));
      expect(cancelPair, contains("mine['peer'] != peerId"));
      expect(cancelPair, contains("theirs['peer'] != uid"));
    });

    test('the old two-step pairing path is gone', () {
      expect(
        client.contains('matchAnnouncePair'),
        isFalse,
        reason: 'a separate announce step would break atomicity',
      );
      expect(client.contains('matchmaking_pairings'), isFalse);
    });
  });
}
