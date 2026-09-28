import 'dart:math' as math;

enum PlayMode { menu, playing, paused, over, spectate }

enum Swipe { left, right, up, upLeft, upRight }

class Progress {
  int coins, best;
  String skin, sky;
  final Set<String> skins, skies;
  final Map<String, int> items;
  Progress({
    this.coins = 150,
    this.best = 0,
    this.skin = 'pip',
    this.sky = 'auto',
    Set<String>? skins,
    Set<String>? skies,
    Map<String, int>? items,
  }) : skins = skins ?? {'pip'},
       skies = skies ?? {'auto'},
       items = items ?? {'rocket': 1, 'life': 1, 'spring': 1, 'rock': 0};
  Map<String, dynamic> toJson() => {
    'coins': coins,
    'best': best,
    'skin': skin,
    'sky': sky,
    'skins': skins.toList(),
    'skies': skies.toList(),
    'items': Map<String, int>.from(items),
  };
  factory Progress.fromJson(Map<String, dynamic> m) {
    int count(dynamic n) => n is num ? n.toInt().clamp(0, 10000000) : 0;
    final skins = {
      'pip',
      ...((m['skins'] as List?) ?? []).whereType<String>().where(
        (s) => ['mint', 'berry', 'cosmo'].contains(s),
      ),
    };
    final skies = {
      'auto',
      ...((m['skies'] as List?) ?? []).whereType<String>().where(
        (s) => ['sunset', 'aurora', 'candy'].contains(s),
      ),
    };
    final bag = Map<String, dynamic>.from(m['items'] as Map? ?? {});
    return Progress(
      coins: count(m['coins']),
      best: count(m['best']),
      skin: skins.contains(m['skin']) ? m['skin'] as String : 'pip',
      sky: skies.contains(m['sky']) ? m['sky'] as String : 'auto',
      skins: skins,
      skies: skies,
      items: {
        for (final id in ['rocket', 'life', 'spring', 'rock'])
          id: count(bag[id]),
      },
    );
  }
}

class Product {
  final String id, name, category, description;
  final int price;
  const Product(
    this.id,
    this.name,
    this.category,
    this.price,
    this.description,
  );
}

const products = [
  Product('rocket', 'Rocket', 'items', 500, 'Fly upward for 1.6 seconds.'),
  Product(
    'life',
    'Extra life',
    'items',
    1000,
    'Classic: one rescue per life. Use your full bag in one run.',
  ),
  Product(
    'spring',
    'Trampoline',
    'items',
    100,
    'Spring line three steps ahead.',
  ),
  Product(
    'rock',
    'Rocks',
    'items',
    500,
    'One spectator rock shower (5-10 boulders). Stock up before the round.',
  ),
  Product('pip', 'Original Pip', 'skins', 0, 'The original explorer.'),
  Product('mint', 'Froggy Pip', 'skins', 100, 'A bright green frog hat.'),
  Product('cosmo', 'Cosmo Pip', 'skins', 140, 'A little space explorer.'),
  Product('berry', 'Berry Pip', 'skins', 120, 'Pink with a golden bow.'),
  Product('auto', 'Level skies', 'skies', 0, 'A new style every 50 steps.'),
  Product('sunset', 'Peach sunset', 'skies', 100, 'Warm evening colors.'),
  Product(
    'aurora',
    'Dream aurora',
    'skies',
    150,
    'Soft ribbons of northern light.',
  ),
  Product('candy', 'Candy sky', 'skies', 100, 'Clouds in pink and lavender.'),
];
bool purchase(Progress p, Product item) {
  final owned = item.category == 'skins'
      ? p.skins
      : item.category == 'skies'
      ? p.skies
      : null;
  if (owned == null || !owned.contains(item.id)) {
    if (p.coins < item.price) return false;
    p.coins -= item.price;
    if (owned != null) {
      owned.add(item.id);
    } else {
      p.items[item.id] = (p.items[item.id] ?? 0) + 1;
    }
  }
  if (item.category == 'skins') p.skin = item.id;
  if (item.category == 'skies') p.sky = item.id;
  return true;
}

class Ledge {
  final int id;
  double x, y, w;
  bool spring = false, claimed = false;
  String? gift;
  final double giftRoll;
  Ledge(this.id, this.x, this.y, this.w, {this.gift, this.giftRoll = 0});
}

class Runner {
  double x = 210,
      y = 623,
      vx = 0,
      vy = 0,
      run = 0,
      flight = 0,
      rocket = 0,
      power = 0,
      animationPhase = 0,
      gazeX = 0,
      gazeY = 0;
  int ledge = 0, launch = 0, face = 1, flipTurns = 1;
  bool fallSoundPlayed = false;
  bool grounded = true, airborne = false, flip = false, wall = false;
  double stun = 0;
  int edgeHits = 0;
}

/// A boulder thrown by a spectator. Simulated locally from its spawn state;
/// every client runs the same integration, so throws stay in sync over the
/// network without per-frame writes.
class RockThrow {
  final String id, owner;
  double x, y, vx, vy, age;
  double scale = 1;
  RockThrow(
    this.id,
    this.owner,
    this.x,
    this.y,
    this.vx,
    this.vy, [
    this.age = 0,
  ]);
}

class GameEngine {
  static const gravity = 2200.0, maxRun = 300.0, width = 420.0;
  static const rockGravity = 0.0, rockTtl = 8.0, rockHitRadius = 27.0;
  final List<RockThrow> rocks = [];
  final Set<String> rockHits = {};
  final Map<String, int> seenShowers = {};
  double movementDistance = 0;
  final Progress progress;
  final void Function()? onChanged, onEnd;
  final void Function(String)? onSound;
  GameEngine(this.progress, {this.onChanged, this.onEnd, this.onSound}) {
    reset();
  }
  PlayMode mode = PlayMode.menu;
  Runner player = Runner();
  List<Ledge> ledges = [];
  double camera = 0,
      viewHeight = 740,
      time = 0,
      attractTime = 0,
      rockTimer = 5,
      moveTime = 0,
      jumpBuffer = 0,
      comboTime = 0,
      messageTime = 0;
  int highest = 0, points = 0, runCoins = 0, chain = 0, direction = 0, seed = 1;
  bool lifeUsed = false, adRevived = false;
  bool allowRewardAds = true;
  bool competitive = false, awaitingFinish = false;
  int roundLives = 2; // Two rescues plus the starting attempt.
  int get availableLives =>
      competitive ? roundLives : (progress.items['life'] ?? 0);
  String character = 'male';
  String message = '';
  Ledge? adGift;
  int get level => highest ~/ 50 + 1;
  double get beltSpeed => 90 * (1 + .1 * (level - 1));
  void say(String text) {
    message = text;
    messageTime = 1.7;
  }

  void reset({int? courseSeed}) {
    seed = courseSeed ?? math.Random().nextInt(0x7fffffff);
    player = Runner();
    camera = 0;
    time = 0;
    attractTime = 0;
    rockTimer = 5;
    highest = 0;
    points = 0;
    runCoins = 0;
    chain = 0;
    moveTime = 0;
    jumpBuffer = 0;
    direction = 0;
    comboTime = 0;
    lifeUsed = false;
    roundLives = 2;
    awaitingFinish = false;
    rocks.clear();
    rockHits.clear();
    seenShowers.clear();
    movementDistance = 0;
    adRevived = false;
    adGift = null;
    message = '';
    ledges = [Ledge(0, 45, 640, 330)];
    generate();
  }

  void start({int? courseSeed}) {
    reset(courseSeed: courseSeed);
    mode = PlayMode.playing;
    onSound?.call('start');
  }

  /// Menu attract mode: slowly scrolls up through the course and bobs the
  /// climber so the home screen shows live gameplay behind the overlay.
  /// [start] always calls [reset], so demo state never leaks into a run.
  void attract(double dt) {
    if (mode != PlayMode.menu) return;
    attractTime += dt;
    time += dt;
    messageTime = math.max(0, messageTime - dt);
    camera -= 45 * dt;
    generate();
    ledges.removeWhere((q) => q.y > camera + viewHeight + 50);
    player.x = 210 + math.sin(attractTime * .6) * 90;
    player.y = camera + viewHeight * .62 + math.sin(attractTime * 2.2) * 14;
    player.vx = 0;
    player.vy = 0;
    player.grounded = true;
    player.airborne = false;
    player.face = math.cos(attractTime * .6) >= 0 ? 1 : -1;
  }

  /// Puts the local player into spectator mode after elimination. The round
  /// keeps running; the camera follows [tickSpectate]'s leader instead.
  void enterSpectate() {
    stopInput();
    mode = PlayMode.spectate;
    onChanged?.call();
  }

  /// Spectator frame: ease the camera toward the leader and simulate rocks.
  void tickSpectate(double dt, double leaderY) {
    if (mode != PlayMode.spectate) return;
    time += dt;
    messageTime = math.max(0, messageTime - dt);
    camera += ((leaderY - 300) - camera) * math.min(1, dt * 2.5);
    generate();
    ledges.removeWhere((q) => q.y > camera + viewHeight + 50);
    stepRocks(dt);
  }

  /// Adds a rock unless already known. Remote rocks arrive with an estimated
  /// age so late joiners see them mid-flight instead of restarting them.
  void spawnRock({
    required String id,
    required String owner,
    required double x,
    required double y,
    required double vx,
    required double vy,
    double age = 0,
  }) {
    if (id.isEmpty || rocks.any((r) => r.id == id)) return;
    rocks.add(RockThrow(id, owner, x, y, vx, vy, age));
  }

  /// Merges network throws (each map carries id/by/x0/y0/vx/vy/t0).
  /// Own throws are simulated locally from the tap, so [selfId]'s rocks are
  /// skipped here to avoid double simulation under a different id.
  void syncRocks(List<Map<String, dynamic>> remote, int nowMs, String selfId) {
    seenShowers.removeWhere((_, at) => nowMs - at > 60000);
    for (final m in remote) {
      final id = m['id']?.toString() ?? '';
      final t0 = (m['t0'] as num?)?.toInt() ?? 0;
      final age = (nowMs - t0) / 1000;
      if (id.isEmpty || seenShowers.containsKey(id) || age < 0 || age > rockTtl)
        continue;
      seenShowers[id] = t0;
      final random = math.Random((m['seed'] as num?)?.toInt() ?? 1);
      final count = ((m['count'] as num?)?.toInt() ?? 8).clamp(8, 15);
      final fromLeft = ((m['vx'] as num?) ?? 1) > 0;
      for (var i = 0; i < count; i++) {
        final speed = 330 + random.nextDouble() * 160;
        final vx = (fromLeft ? 1 : -1) * speed * .42;
        final vy = speed;
        final delay = i * .12;
        final flight = math.max(0.0, age - delay);
        final x =
            (fromLeft ? 5.0 : 415.0) +
            (fromLeft ? 1 : -1) * random.nextDouble() * 120;
        final y =
            ((m['y0'] as num?)?.toDouble() ?? camera - 40) -
            random.nextDouble() * 45;
        final rock = RockThrow(
          '$id:$i',
          (m['by'] ?? '').toString(),
          x + vx * flight,
          y + vy * flight,
          vx,
          vy,
          age - delay,
        )..scale = .3 + random.nextDouble() * 2.2;
        rocks.add(rock);
      }
    }
  }

  void stepRocks(double dt) {
    for (final r in rocks) {
      r.age += dt;
      if (r.age < 0) continue;
      r.vy += rockGravity * dt;
      r.x += r.vx * dt;
      r.y += r.vy * dt;
    }
    rocks.removeWhere(
      (r) =>
          r.age > rockTtl ||
          r.y > camera + viewHeight ||
          (r.vx > 0 && r.x > width) ||
          (r.vx < 0 && r.x < 0),
    );
    rockHits.removeWhere((id) => !rocks.any((r) => r.id == id));
  }

  /// Hit test against the local live player. Each rock hits once.
  /// Impact depends on state at contact:
  /// - Rocket flight absorbs the hit: the booster is stripped, nothing else.
  /// - Grounded, first hit: shoved to the nearest step edge (brief stun).
  /// - Grounded, second hit while still grounded: knocked off the step.
  /// - Airborne: knocked straight down immediately.
  bool checkRockHits(String selfId) {
    if (mode != PlayMode.playing) return false;
    final p = player;
    var hit = false;
    for (final r in rocks) {
      if (r.age < 0 || r.owner == selfId || rockHits.contains(r.id)) continue;
      final dx = r.x - p.x, dy = r.y - p.y;
      if (dx * dx + dy * dy >= math.pow(17 + 10 * r.scale, 2)) continue;
      rockHits.add(r.id);
      hit = true;
      if (p.rocket > 0) {
        p.rocket = 0;
        say('ROCKET LOST!');
        continue;
      }
      if (p.grounded) {
        _hitGrounded(p, r);
      } else {
        p.airborne = true;
        p.flip = false;
        p.vy = math.max(p.vy, 240);
        say('KNOCKED DOWN!');
      }
    }
    return hit;
  }

  void _hitGrounded(Runner p, RockThrow r) {
    Ledge? footing;
    for (final q in ledges) {
      if (q.id == p.ledge) {
        footing = q;
        break;
      }
    }
    if (footing == null || p.edgeHits > 0) {
      // Second hit while still grounded (or unknown footing): off the step.
      p.edgeHits = 0;
      p.grounded = false;
      p.airborne = true;
      p.flight = 0;
      p.flip = false;
      p.vy = 140;
      p.vx = (p.x >= r.x ? 1.0 : -1.0) * 140;
      say('KNOCKED OFF!');
      return;
    }
    // First hit: shoved to the nearest step edge.
    final l = footing;
    final edgeX = p.x < l.x + l.w / 2 ? l.x + 12 : l.x + l.w - 12;
    p.x = edgeX.clamp(l.x + 4, l.x + l.w - 4);
    p.vx = 0;
    p.stun = .9;
    direction = 0;
    moveTime = 0;
    jumpBuffer = 0;
    p.edgeHits = 1;
    say('HIT!');
  }

  void earn(int n) {
    if (n <= 0) return;
    progress.coins += n;
    runCoins += n;
    onChanged?.call();
  }

  Ledge makeLedge(Ledge previous, int id) {
    final rng = math.Random((seed ^ (id * 2654435761)) & 0x7fffffff);
    final lv = id ~/ 50 + 1,
        wide = .8 * math.pow(.72, lv - 1),
        small = .05 + .75 * (1 - math.pow(.76, lv - 1));
    final pick = rng.nextDouble(),
        shrink = 1 - .28 * (1 - math.exp(-(lv - 1) / 6));
    final low = pick < wide
            ? 250.0
            : pick < 1 - small
            ? 150.0
            : 85.0,
        span = pick < wide
            ? 60.0
            : pick < 1 - small
            ? 55.0
            : 30.0;
    final w = (low + rng.nextDouble() * span) * shrink;
    final x =
        (previous.x + previous.w / 2 - w / 2 + rng.nextDouble() * 224 - 112)
            .clamp(18.0, width - w - 18);
    final y = previous.y - 82 - rng.nextDouble() * 16;
    final gift = rng.nextDouble() < .12
        ? (rng.nextDouble() < .35 ? 'ad' : 'free')
        : null;
    return Ledge(
      id,
      x,
      y,
      w,
      gift: gift == 'ad' && !allowRewardAds ? null : gift,
      giftRoll: rng.nextDouble(),
    );
  }

  void generate() {
    while (ledges.last.y > camera - 480) {
      ledges.add(makeLedge(ledges.last, ledges.last.id + 1));
    }
  }

  void swipe(Swipe s) {
    if (mode != PlayMode.playing) return;
    final dx = s == Swipe.left || s == Swipe.upLeft
        ? -1
        : s == Swipe.right || s == Swipe.upRight
        ? 1
        : 0;
    direction = dx;
    moveTime = dx == 0 ? 0 : .55;
    if (s != Swipe.left && s != Swipe.right) {
      jumpBuffer = .16;
      if (player.grounded && player.rocket == 0) jump();
    }
  }

  /// Joystick hold: refresh the jump buffer every frame so the climber
  /// hops again on every landing, and steer while [dir] is non-zero.
  /// Releasing the touch should call [stopInput].
  void holdJump(int dir) {
    if (mode != PlayMode.playing) return;
    jumpBuffer = .16;
    if (dir != 0) {
      direction = dir;
      moveTime = .55;
    }
  }

  void stopInput() {
    direction = 0;
    moveTime = 0;
    jumpBuffer = 0;
    player.vx = 0;
  }

  void jump({bool spring = false}) {
    final p = player;
    p.power = math.min(
      (p.vx.abs() / maxRun).clamp(0.0, 1.0),
      (p.run / 95).clamp(0.0, 1.0),
    );
    p.vy = -math.sqrt(
      2 * gravity * (spring ? 460 : 110 + 195 * p.power * p.power),
    );
    p.grounded = false;
    p.airborne = true;
    p.launch = p.ledge;
    p.flight = 0;
    p.flip = p.power > .72;
    p.flipTurns = p.power > .90 ? 3 : 1;
    p.fallSoundPlayed = false;
    if (mode == PlayMode.playing) {
      onSound?.call(
        spring
            ? 'spring'
            : p.flip
            ? (p.flipTurns == 3 ? 'triple_flip' : 'flip')
            : 'jump',
      );
    }
    p.wall = false;
    jumpBuffer = 0;
    if (spring) {
      say('TRAMPOLINE!');
    } else if (p.flip)
      say('SUPER JUMP!');
  }

  bool use(String id) {
    if (mode != PlayMode.playing || (progress.items[id] ?? 0) <= 0) {
      return false;
    }
    if (id == 'rocket') {
      if (player.rocket > 0) return false;
      player.rocket = 1.6;
      player.grounded = false;
      player.airborne = true;
      player.flip = false;
      player.launch = player.ledge;
      player.vy = -520;
      onSound?.call('rocket');
      say('ROCKET FLIGHT!');
    } else if (id == 'spring') {
      generate();
      final target = (player.grounded ? player.ledge : highest) + 3,
          choices = ledges.where((q) => q.id == target);
      if (choices.isEmpty || choices.first.spring) return false;
      choices.first.spring = true;
      onSound?.call('spring_set');
      say('SPRING ON STEP $target');
    } else {
      return false;
    }
    progress.items[id] = progress.items[id]! - 1;
    onChanged?.call();
    return true;
  }

  void grantGift(Ledge q) {
    if (q.claimed) return;
    q.claimed = true;
    final roll = q.giftRoll;
    if (roll < .25) {
      progress.items['rocket'] = progress.items['rocket']! + 1;
      say('GIFT: ROCKET');
    } else if (roll < .4) {
      progress.items['life'] = progress.items['life']! + 1;
      say('GIFT: EXTRA LIFE');
    } else if (roll < .65) {
      progress.items['spring'] = progress.items['spring']! + 1;
      say('GIFT: TRAMPOLINE');
    } else {
      earn(25);
      say('GIFT: +25 COINS');
    }
    onChanged?.call();
  }

  void land(Ledge q) {
    final p = player, hadFlight = p.airborne;
    p.y = q.y - 17;
    p.vy = 0;
    p.grounded = true;
    p.fallSoundPlayed = false;
    p.ledge = q.id;
    p.edgeHits = 0;
    if (q.gift != null && !q.claimed) {
      if (q.gift == 'ad') {
        adGift = q;
        say('AD GIFT AVAILABLE');
      } else {
        grantGift(q);
      }
    }
    if (!hadFlight) return;
    if (mode == PlayMode.playing) onSound?.call('land');
    p.airborne = false;
    if (p.flip && p.flight >= .52) {
      earn(10);
      say('FLIP +10 COINS');
    }
    p.run = direction != 0 && p.vx.sign == direction
        ? 95 * (p.vx.abs() / maxRun).clamp(0.0, 1.0)
        : 0;
    if (q.id > highest) {
      final old = highest, skip = q.id - p.launch;
      earn(q.id ~/ 10 - old ~/ 10);
      final stunt = skip >= 3 || p.wall;
      chain = stunt ? (comboTime > 0 ? chain + 1 : 1) : 0;
      comboTime = stunt ? 3.2 : 0;
      points +=
          (q.id - old) * 10 +
          (skip >= 3
                  ? 90
                  : skip == 2
                  ? 30
                  : 0) *
              math.max(1, math.min(chain, 8));
      highest = q.id;
      if (highest ~/ 50 != old ~/ 50) say('LEVEL $level');
    }
    if (q.spring) {
      q.spring = false;
      jump(spring: true);
    }
  }

  bool rescue() {
    if (availableLives <= 0) return false;
    lifeUsed = true;
    if (competitive) {
      roundLives--;
    } else {
      progress.items['life'] = progress.items['life']! - 1;
    }
    final choices = ledges
        .where(
          (q) => q.id <= highest && q.y - camera > 280 && q.y - camera < 520,
        )
        .toList();
    Ledge q;
    if (choices.isNotEmpty) {
      q = choices.first;
    } else {
      q = Ledge(highest, 80, camera + 420, 260);
      ledges.add(q);
      ledges.sort((a, b) => b.y.compareTo(a.y));
    }
    player = Runner()
      ..x = q.x + q.w / 2
      ..y = q.y - 17
      ..ledge = q.id
      ..launch = q.id;
    stopInput();
    onChanged?.call();
    say('EXTRA LIFE!');
    return true;
  }

  /// One-time revive earned by watching a rewarded ad. Repositions the
  /// climber like [rescue] but costs no item; keeps score, coins and camera.
  bool revive() {
    if (adRevived || mode != PlayMode.over) return false;
    adRevived = true;
    lifeUsed = true;
    final choices = ledges
        .where(
          (q) => q.id <= highest && q.y - camera > 280 && q.y - camera < 520,
        )
        .toList();
    Ledge q;
    if (choices.isNotEmpty) {
      q = choices.first;
    } else {
      q = Ledge(highest, 80, camera + 420, 260);
      ledges.add(q);
      ledges.sort((a, b) => b.y.compareTo(a.y));
    }
    player = Runner()
      ..x = q.x + q.w / 2
      ..y = q.y - 17
      ..ledge = q.id
      ..launch = q.id;
    stopInput();
    mode = PlayMode.playing;
    onChanged?.call();
    say('REVIVED! KEEP CLIMBING');
    return true;
  }

  void end({bool allowRescue = true}) {
    if (mode == PlayMode.over) return;
    if (allowRescue && rescue()) return;
    progress.best = math.max(progress.best, highest);
    mode = PlayMode.over;
    stopInput();
    onChanged?.call();
    onEnd?.call();
  }

  void tick(double dt) {
    if (mode != PlayMode.playing || awaitingFinish) return;
    final p = player, oldY = p.y, wasGround = p.grounded;
    time += dt;
    messageTime = math.max(0, messageTime - dt);
    comboTime = math.max(0, comboTime - dt);
    moveTime = math.max(0, moveTime - dt);
    if (moveTime == 0) direction = 0;
    if (p.stun > 0) {
      p.stun = math.max(0, p.stun - dt);
      direction = 0;
      moveTime = 0;
      jumpBuffer = 0;
    }
    // Exponential steering is stable across frame rates, including reversals.
    final target = direction * maxRun;
    p.vx += (target - p.vx) * (1 - math.exp(-(direction == 0 ? 22 : 12) * dt));
    if (direction == 0 && p.vx.abs() < 1) p.vx = 0;
    if (direction != 0) p.face = direction;
    if (p.grounded) {
      p.run = direction != 0
          ? p.run + p.vx.abs() * dt
          : p.run * math.exp(-9 * dt);
    }
    if (jumpBuffer > 0 && p.grounded && p.rocket == 0) jump();
    jumpBuffer = math.max(0, jumpBuffer - dt);
    // Visual state is independent of jump charge and never affects physics.
    p.animationPhase += dt * (p.grounded ? p.vx.abs() * .075 : 9);
    final lookX = (p.vx / maxRun).clamp(-1.0, 1.0);
    final lookY = p.grounded ? 0.0 : (p.vy / 500).clamp(-1.0, 1.0);
    final gazeBlend = 1 - math.exp(-12 * dt);
    p.gazeX += (lookX - p.gazeX) * gazeBlend;
    p.gazeY += (lookY - p.gazeY) * gazeBlend;
    movementDistance += p.vx.abs() * dt;
    p.x += p.vx * dt;
    if (p.rocket > 0) {
      p.y -= 520 * dt;
      p.rocket = math.max(0, p.rocket - dt);
      p.vy = p.rocket > 0 ? -520 : -100;
    } else {
      p.y += p.vy * dt + .5 * gravity * dt * dt;
      p.vy += gravity * dt;
    }
    if (p.x < 26 || p.x > 394) {
      if (p.airborne && p.vx.abs() > 190 && !p.wall) {
        p.wall = true;
        say('WALL REBOUND!');
      }
      p.x = p.x.clamp(26.0, 394.0);
      p.vx *= -.82;
    }
    p.grounded = false;
    if (p.vy >= 0) {
      for (final q in ledges.reversed) {
        if (oldY + 17 <= q.y + 1 &&
            p.y + 17 >= q.y &&
            p.x + 12 > q.x &&
            p.x - 12 < q.x + q.w) {
          land(q);
          break;
        }
      }
    }
    if (wasGround && !p.grounded && !p.airborne) {
      p.airborne = true;
      p.launch = p.ledge;
      p.flight = 0;
      p.flip = false;
    }
    if (p.airborne) p.flight += dt;
    if (p.y - camera < 300) camera = p.y - 300;
    if (highest >= 1) camera -= beltSpeed * dt;
    generate();
    stepRocks(dt);
    ledges.removeWhere((q) => q.y > camera + viewHeight + 50);
    if (p.airborne &&
        p.vy > 0 &&
        p.rocket == 0 &&
        p.y - camera > viewHeight - 150 &&
        !p.fallSoundPlayed) {
      p.fallSoundPlayed = true;
      onSound?.call('fall');
    }
    if (p.y - 17 > camera + viewHeight) {
      end();
    }
  }
}
