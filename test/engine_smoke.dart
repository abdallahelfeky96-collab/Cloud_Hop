// ignore_for_file: avoid_print
import 'package:cloud_hop/game/engine.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  int passed = 0;
  void test(String label, void Function() body) {
    body();
    passed++;
    print('PASS $label');
  }

  GameEngine fresh() =>
      GameEngine(Progress(items: {'rocket': 2, 'life': 0, 'spring': 2}))
        ..start(courseSeed: 123);
  test('prices, purchasing and duplicate cosmetic equip', () {
    final p = Progress(coins: 2000);
    check(purchase(p, products.first), 'rocket bought');
    check(p.coins == 1500, '500 price');
    final mint = products.firstWhere((p) => p.id == 'mint');
    purchase(p, mint);
    final coins = p.coins;
    purchase(p, mint);
    check(p.coins == coins, 'no double charge');
    check(
      products.firstWhere((p) => p.id == 'life').price == 1000,
      'life price',
    );
    check(
      products.firstWhere((p) => p.id == 'spring').price == 100,
      'spring price',
    );
  });
  test('up swipe jumps vertically without buttons', () {
    final g = fresh();
    g.swipe(Swipe.up);
    check(g.player.vy < 0 && !g.player.grounded, 'takeoff');
    final x = g.player.x;
    for (int i = 0; i < 20; i++) {
      g.tick(1 / 120);
    }
    check(g.player.x == x, 'vertical arc');
  });
  test('all horizontal and diagonal swipe directions', () {
    for (final s in [Swipe.left, Swipe.right, Swipe.upLeft, Swipe.upRight]) {
      final g = fresh();
      g.swipe(s);
      g.tick(1 / 120);
      final left = s == Swipe.left || s == Swipe.upLeft;
      check(left ? g.player.x < 210 : g.player.x > 210, 'direction $s');
      if (s == Swipe.upLeft || s == Swipe.upRight) {
        check(g.player.vy < 0, 'diagonal jumps');
      } else {
        check(g.player.grounded, 'horizontal swipe runs');
      }
    }
  });
  test('constant gravity, one-step standing jump, three-step running jump', () {
    for (final charge in [0.0, 1.0]) {
      final g = fresh();
      g.player.vx = 300 * charge;
      g.player.run = 95 * charge;
      g.swipe(Swipe.up);
      final initial = g.player.vy, expected = 110 + 195 * charge * charge;
      check(
        (initial * initial / (2 * GameEngine.gravity) - expected).abs() <
            .000001,
        'height',
      );
      for (int i = 0; i < 30; i++) {
        g.tick(1 / 120);
        final energy =
            g.player.vy * g.player.vy -
            2 * GameEngine.gravity * (g.player.y - 623);
        check((energy - initial * initial).abs() < .001, 'symmetric physics');
      }
    }
  });
  test('swipe movement expires with no held direction', () {
    final g = fresh();
    g.swipe(Swipe.right);
    for (int i = 0; i < 110; i++) {
      g.tick(1 / 120);
    }
    check(g.direction == 0 && g.player.vx == 0, 'no drift');
  });
  test('course seed produces identical race platforms', () {
    final a = fresh(), b = fresh();
    for (int i = 0; i < a.ledges.length; i++) {
      check(
        a.ledges[i].x == b.ledges[i].x && a.ledges[i].y == b.ledges[i].y,
        'shared course',
      );
    }
  });
  test('belt speed grows by 10 percent of initial speed every 50 steps', () {
    final g = fresh();
    for (int n = 0; n < 10; n++) {
      g.highest = n * 50;
      check((g.beltSpeed - (90 + n * 9)).abs() < .00001, 'speed level $n');
    }
  });
  test('ten-step coin boundaries and completed flip rewards', () {
    final g = fresh();
    g.progress.coins = 0;
    g.player.airborne = true;
    g.land(Ledge(9, 0, 400, 420));
    check(g.progress.coins == 0, '9 steps');
    g.player.airborne = true;
    g.land(Ledge(10, 0, 300, 420));
    check(g.progress.coins == 1, '10 steps');
    g.player.airborne = true;
    g.player.flip = true;
    g.player.flight = .6;
    g.land(Ledge(11, 0, 200, 420));
    check(g.progress.coins == 11, 'flip ten');
    g.land(Ledge(11, 0, 200, 420));
    check(g.progress.coins == 11, 'landing once');
  });
  test('rocket consumes once and lasts 1.6 seconds', () {
    final g = fresh();
    check(g.use('rocket'), 'activate');
    check(!g.use('rocket'), 'no double');
    check(g.progress.items['rocket'] == 1, 'one consumed');
    for (int i = 0; i < 120; i++) {
      g.tick(1 / 120);
    }
    check(g.player.y < 110, 'fly');
    for (int i = 0; i < 80; i++) {
      g.tick(1 / 120);
    }
    check(g.player.rocket == 0, 'expires');
  });
  test('trampoline is three steps ahead and bounces on landing', () {
    final g = fresh();
    check(g.use('spring'), 'spring');
    final q = g.ledges.firstWhere((q) => q.id == 3);
    check(q.spring, 'correct step');
    g.player.airborne = true;
    g.land(q);
    check(!q.spring && !g.player.grounded, 'consumed and bouncing');
    check(
      (g.player.vy * g.player.vy / (2 * GameEngine.gravity) - 460).abs() < .001,
      'spring power',
    );
  });
  test('Classic consumes every owned life before ending', () {
    final g = fresh();
    g.progress.items['life'] = 5;
    for (var remaining = 4; remaining >= 0; remaining--) {
      g.end();
      check(
        g.mode == PlayMode.playing && g.progress.items['life'] == remaining,
        'one rescue per owned life',
      );
    }
    g.end();
    check(g.mode == PlayMode.over, 'ends when lives are exhausted');
  });
  test('Competitive attempts do not spend owned lives', () {
    final g = fresh()..competitive = true;
    g.progress.items['life'] = 10;
    g.end();
    g.end();
    check(g.mode == PlayMode.playing && g.roundLives == 0, 'two equal rescues');
    g.end();
    check(
      g.mode == PlayMode.over && g.progress.items['life'] == 10,
      'third fall ends without spending inventory',
    );
  });
  test('ad revive resumes the run exactly once', () {
    final g = fresh();
    g.progress.items['life'] = 0;
    g.highest = 12;
    g.end(allowRescue: false);
    check(g.mode == PlayMode.over, 'game over');
    check(g.revive(), 'revived');
    check(g.mode == PlayMode.playing && g.player.grounded, 'run continues');
    check(g.highest == 12, 'score kept');
    g.end(allowRescue: false);
    check(g.mode == PlayMode.over && !g.revive(), 'one revive only');
  });
  test('joystick hold auto-jumps and steers until released', () {
    final g = fresh();
    g.holdJump(1);
    check(g.jumpBuffer > 0 && g.direction == 1, 'hold steers');
    g.tick(1 / 120);
    check(!g.player.grounded, 'continuous jump');
    g.stopInput();
    check(g.direction == 0 && g.jumpBuffer == 0, 'release stops');
  });
  test('spectator rocks simulate, dedupe and expire', () {
    final g = fresh();
    g.enterSpectate();
    check(g.mode == PlayMode.spectate, 'spectating');
    g.spawnRock(id: 'r1', owner: 'mallory', x: 210, y: 100, vx: 0, vy: 500);
    g.spawnRock(id: 'r1', owner: 'mallory', x: 0, y: 0, vx: 0, vy: 0);
    check(g.rocks.length == 1, 'dedupe by id');
    final y = g.rocks.first.y;
    g.stepRocks(1 / 120);
    check(g.rocks.first.y > y, 'gravity falls');
    check(g.rocks.first.vy > 500, 'accelerates');
    for (int i = 0; i < 400; i++) g.stepRocks(1 / 120);
    check(g.rocks.isEmpty, 'expired by ttl');
  });
  test('rock hits stumble the victim exactly once', () {
    final g = fresh();
    g.spawnRock(
      id: 'r1',
      owner: 'mallory',
      x: g.player.x,
      y: g.player.y,
      vx: 0,
      vy: 0,
    );
    check(g.checkRockHits('me'), 'hit registers');
    check(g.player.stun > 0 && g.player.vx != 0, 'stumble impulse');
    check(!g.checkRockHits('me'), 'each rock hits once');
    g.spawnRock(
      id: 'r2',
      owner: 'me',
      x: g.player.x,
      y: g.player.y,
      vx: 0,
      vy: 0,
    );
    check(!g.checkRockHits('me'), 'own rocks harmless');
  });
  test('spectator camera follows the leader', () {
    final g = fresh();
    g.enterSpectate();
    final cam = g.camera;
    g.tickSpectate(1, cam - 500);
    check(g.camera < cam, 'camera climbs to leader');
    g.tickSpectate(30, cam - 500);
    check((g.camera - (cam - 800)).abs() < 1, 'camera settles');
  });
  test('network rocks merge without duplicates', () {
    final g = fresh();
    final remote = [
      {
        'id': 'a',
        'by': 'x',
        'x0': 1,
        'y0': 2,
        'vx': 0,
        'vy': 0,
        't0': 1000,
      },
    ];
    g.syncRocks(remote, 1000, 'me');
    g.syncRocks(remote, 1100, 'me');
    check(g.rocks.length == 1, 'merged once');
    g.syncRocks([
      {'id': 'b', 'by': 'me', 'x0': 0, 'y0': 0, 'vx': 0, 'vy': 0, 't0': 1100},
    ], 1100, 'me');
    check(g.rocks.length == 1, 'own throws skipped');
  });
  test('rematch reset clears rocks for a fresh round', () {
    final g = fresh();
    g.spawnRock(id: 'r1', owner: 'x', x: 0, y: 0, vx: 0, vy: 0);
    g.start(courseSeed: 7);
    check(g.rocks.isEmpty && g.rockHits.isEmpty, 'clean round');
  });
  test('gift claim is idempotent and progress round trips', () {
    final g = fresh();
    final q = Ledge(1, 0, 0, 100, gift: 'free', giftRoll: .9);
    final before = g.progress.coins;
    g.grantGift(q);
    g.grantGift(q);
    check(g.progress.coins == before + 25, 'once');
    final copy = Progress.fromJson(g.progress.toJson());
    check(copy.coins == g.progress.coins, 'saved coins');
  });
  print('$passed native game checks passed.');
}
