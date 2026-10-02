import 'package:cloud_hop/game/character.dart';
import 'package:cloud_hop/game/match_result.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> p(
  String id,
  int step,
  String status, {
  int finish = 0,
  int movement = 0,
  String character = 'male',
}) => {
  'id': id,
  'step': step,
  'status': status,
  'finishedAt': finish,
  'movement': movement,
  'character': character,
};

void main() {
  group('race ends the moment anyone reaches the target', () {
    test('a live opponent at the target wins immediately', () {
      final decision = evaluateMatch([
        p('self', 40, 'live'),
        p('rival', 100, 'live'),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'rival');
      expect(decision?.reason, 'finish');
    });

    test('overshooting the target still finishes', () {
      final decision = evaluateMatch([
        p('self', 10, 'live'),
        p('rival', 137, 'live'),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'rival');
    });

    test('a ready lobby with one player past target is not blocked by the barrier', () {
      final decision = evaluateMatch([
        p('other', 0, 'ready'),
        p('rival', 100, 'live'),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'rival');
    });

    test('earliest server finish stamp wins when two cross together', () {
      final decision = evaluateMatch([
        p('aaa', 100, 'live', finish: 500),
        p('bbb', 120, 'live', finish: 400),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'bbb');
    });

    test('an unstamped node never beats a stamped finisher', () {
      final decision = evaluateMatch([
        p('aaa', 140, 'live'),
        p('bbb', 100, 'live', finish: 900),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'bbb');
    });

    test('ties without timestamps resolve identically on every client', () {
      final forwards = evaluateMatch([
        p('aaa', 100, 'live'),
        p('bbb', 100, 'live'),
      ], target: 100, arcade: false);
      final reversed = evaluateMatch([
        p('bbb', 100, 'live'),
        p('aaa', 100, 'live'),
      ], target: 100, arcade: false);
      expect(forwards?.winner, 'aaa');
      expect(reversed?.winner, forwards?.winner);
    });

    test('nobody at the target keeps the round alive', () {
      expect(
        evaluateMatch([
          p('a', 99, 'live'),
          p('b', 98, 'live'),
        ], target: 100, arcade: false),
        isNull,
      );
    });

    test('three racers: the finisher wins even with racers still climbing', () {
      final decision = evaluateMatch([
        p('a', 30, 'live'),
        p('b', 100, 'live'),
        p('c', 70, 'live'),
      ], target: 100, arcade: false);
      expect(decision?.winner, 'b');
      expect(decision?.reason, 'finish');
    });

    test('arcade still settles on progress, not the target', () {
      final decision = evaluateMatch([
        p('a', 100, 'out'),
        p('b', 90, 'spectator'),
      ], target: 100, arcade: true);
      expect(decision?.winner, 'a');
      expect(decision?.reason, 'progress');
    });
  });

  group('character identity', () {
    test('every selectable id is preserved', () {
      for (final entry in Character.all) {
        expect(Character.normalize(entry.id), entry.id);
        expect(Character.isKnown(entry.id), isTrue);
      }
    });

    test('unknown or missing values fall back to the default', () {
      expect(Character.normalize(null), Character.fallback);
      expect(Character.normalize(''), Character.fallback);
      expect(Character.normalize('ninja'), Character.fallback);
    });

    test('gender and palm variant are derived from the id', () {
      expect(Character.isFemale('female'), isTrue);
      expect(Character.isFemale('female_round'), isTrue);
      expect(Character.isFemale('male'), isFalse);
      expect(Character.isRound('male_round'), isTrue);
      expect(Character.isRound('female_round'), isTrue);
      expect(Character.isRound('male'), isFalse);
    });

    test('a hostile network value cannot invent a new character', () {
      expect(Character.normalize('female"; drop'), Character.fallback);
    });
  });
}
