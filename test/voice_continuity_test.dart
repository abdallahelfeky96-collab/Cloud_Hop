import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Voice must survive the whole room: results, rematches and backgrounding
/// the app all keep the channel up. Only an explicit room exit, a destroyed
/// room, or process teardown may end it.
///
/// `VoiceService` talks to LiveKit and cannot be driven from a unit test, so
/// this guards the contract at the call-site level in `lib/main.dart`.
void main() {
  late String source;
  setUpAll(() {
    source = File('lib/main.dart').readAsStringSync();
  });

  /// Returns the body of the first member whose declaration contains [needle],
  /// using brace matching so nested blocks are included.
  String bodyOf(String needle) {
    final start = source.indexOf(needle);
    expect(start, greaterThan(-1), reason: 'no member containing $needle');
    final open = source.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final c = source[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return source.substring(open + 1, i);
      }
    }
    throw StateError('unbalanced braces after $needle');
  }

  test('the results screen never drops the room voice', () {
    expect(bodyOf('Future<void> finishRun()'), isNot(contains('voice.leave')));
  });

  test('a rematch never drops the room voice', () {
    expect(
      bodyOf('Future<void> playAgainInRoom()'),
      isNot(contains('voice.leave')),
    );
  });

  test('backgrounding the app never drops the room voice', () {
    final body = bodyOf('void didChangeAppLifecycleState(');
    // Leaving must be reachable only from the detached (process dying) branch.
    final detached = body.indexOf('AppLifecycleState.detached');
    expect(detached, greaterThan(-1), reason: 'detached teardown missing');
    expect(
      body.substring(0, detached),
      isNot(contains('voice.leave')),
      reason: 'pause/hidden must not leave the room voice',
    );
  });

  test('leaving the room and disposing still release the voice', () {
    expect(bodyOf('Future<void> goHome()'), contains('voice.leave'));
    expect(bodyOf('void dispose()'), contains('voice.dispose'));
  });
}
