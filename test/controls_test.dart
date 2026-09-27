import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_hop/game/engine.dart';
import 'package:cloud_hop/game/swipe_input.dart';
import 'package:cloud_hop/game/challenge.dart';

void main() {
  test('swipe ignores jitter and emits only one jump per finger', () {
    final input = SwipeInput()..begin(100, 100);
    expect(input.update(102, 98), isNull);
    expect(input.update(100, 80), Swipe.up);
    expect(input.update(100, 40), isNull);
    input.end();
    expect(input.update(150, 20), isNull);
    input.begin(100, 100);
    expect(input.update(125, 75), Swipe.upRight);
  });
  test('direction reverses during the same swipe', () {
    final input = SwipeInput()..begin(100, 100);
    expect(input.update(140, 100), Swipe.right);
    expect(input.update(120, 100), Swipe.left);
  });
  test('steering brakes smoothly and then stops', () {
    final g = GameEngine(Progress())..start(courseSeed: 1);
    g.swipe(Swipe.right);
    for (var i = 0; i < 30; i++) {
      g.tick(1 / 120);
    }
    final previous = g.player.vx;
    g.swipe(Swipe.left);
    g.tick(1 / 120);
    expect(g.player.vx, greaterThan(0));
    expect(g.player.vx, lessThan(previous));
    for (var i = 0; i < 120; i++) {
      g.tick(1 / 120);
    }
    expect(g.player.vx, 0);
  });
  test('practice rival plans independently of the human score', () {
    final first = GameEngine(Progress())..start(courseSeed: 7);
    final second = GameEngine(Progress())..start(courseSeed: 7);
    final a = PracticeRival('Egypt', 'Cairo', seed: 7);
    final b = PracticeRival('Egypt', 'Cairo', seed: 7);
    for (var i = 0; i < 120 * 20; i++) {
      first.highest = 900;
      second.highest = 0;
      a.tick(1 / 120, first);
      b.tick(1 / 120, second);
    }
    expect(a.name, isNot(contains('BOT')));
    expect(a.step, b.step);
    expect(a.simulation.player.x, b.simulation.player.x);
  });
}
