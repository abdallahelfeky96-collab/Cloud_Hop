import 'dart:io';

import 'package:cloud_hop/services/social.dart';
import 'package:flutter_test/flutter_test.dart';

/// The queue must find real players anywhere, so it is a single global
/// Realtime Database node with no local network filtering, and the search
/// window has to stay inside the requested 5-10 seconds.
void main() {
  test('the matchmaking window is between five and ten seconds', () {
    expect(SocialService.matchWindowMs, greaterThanOrEqualTo(5000));
    expect(SocialService.matchWindowMs, lessThanOrEqualTo(10000));
  });

  group('global queue rules', () {
    late String rules;
    late String queue;
    setUpAll(() {
      rules = File('firebase/database.rules.json').readAsStringSync();
      final start = rules.indexOf('"matchQueue"');
      expect(start, greaterThan(-1), reason: 'matchQueue rules missing');
      final end = rules.indexOf('"rooms"', start);
      queue = rules.substring(start, end > start ? end : rules.length);
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
      expect(queue, contains('"deadline"'));
      expect(
        queue,
        contains('newData.hasChildren([\'requestId\',\'name\',\'mode\',\'target\',\'createdAt\',\'deadline\',\'status\'])'),
      );
      // `character` is validated when present but not required, so an older
      // installed client can still publish a search during the rollout.
      expect(
        queue,
        contains(
          '"character": {\n          ".validate": "newData.isString() && newData.val().length > 0 && newData.val().length <= 32"',
        ),
      );
    });
  });
}
