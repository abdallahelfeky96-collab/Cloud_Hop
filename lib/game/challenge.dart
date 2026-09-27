import 'dart:math' as math;

import 'engine.dart';

enum GameChoice { classic, arcade, race }

const regions = <String, Map<String, List<String>>>{
  'Egypt': {
    'Cairo': ['Omar', 'Mariam', 'Youssef'],
    'Alexandria': ['Nour', 'Salma', 'Karim'],
  },
  'Saudi Arabia': {
    'Riyadh': ['Fahad', 'Sara', 'Abdullah'],
    'Jeddah': ['Lina', 'Khalid', 'Reem'],
  },
  'UAE': {
    'Dubai': ['Mansour', 'Alya', 'Saeed'],
    'Abu Dhabi': ['Hamad', 'Noora', 'Hessa'],
  },
  'United Kingdom': {
    'London': ['Oliver', 'Amelia', 'Noah'],
    'Manchester': ['Jack', 'Isla', 'Leo'],
  },
  'United States': {
    'New York': ['Alex', 'Maya', 'Sam'],
    'Los Angeles': ['Jordan', 'Avery', 'Riley'],
  },
};

/// A practice opponent driven by the same gravity, collision and life rules.
/// It plans reachable platforms; it is not tied to the human's score.
class PracticeRival {
  final String name;
  final GameEngine simulation;
  double elapsed = 0, groundedTime = 0;
  Ledge? target;
  bool wasGrounded = true;
  PracticeRival(String country, String city, {int seed = 1})
    : name =
          (regions[country]?[city] ?? ['Pip'])[math.Random(seed)
              .nextInt((regions[country]?[city] ?? ['Pip']).length)],
      simulation = GameEngine(Progress()) {
    simulation.competitive = true;
    simulation.allowRewardAds = false;
    simulation.character = seed.isEven ? 'female' : 'male';
    simulation.start(courseSeed: seed);
  }
  double get step => simulation.highest.toDouble();
  bool get out => simulation.mode == PlayMode.over;
  void tick(double dt, GameEngine human) {
    elapsed += dt;
    if (out) return;
    simulation.viewHeight = human.viewHeight;
    final p = simulation.player;
    if (p.grounded) {
      if (!wasGrounded) {
        groundedTime = 0;
        target = null;
      }
      groundedTime += dt;
      final next = simulation.ledges.where((q) => q.id > p.ledge).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (next.isNotEmpty) {
        final aim = next.first.x + next.first.w / 2;
        final current = simulation.ledges.where((q) => q.id == p.ledge);
        final platform = current.isEmpty ? null : current.first;
        var dir = aim >= p.x ? 1 : -1;
        // Use space on a wide ledge to build momentum, then take off before its edge.
        if (platform != null && platform.w > 210 && groundedTime < .18) {
          dir = p.x < platform.x + platform.w / 2 ? 1 : -1;
        }
        simulation.direction = dir;
        simulation.moveTime = .2;
        final edge = platform == null
            ? 0.0
            : (dir > 0 ? platform.x + platform.w - p.x : p.x - platform.x);
        if (groundedTime > .34 ||
            edge < 28 ||
            (p.run > 80 && p.vx.abs() > 235)) {
          simulation.jump();
          target = null;
        }
      }
    } else {
      groundedTime = 0;
      if (target == null) {
        final apex =
            p.y - (p.vy < 0 ? p.vy * p.vy / (2 * GameEngine.gravity) : 0);
        final reachable = simulation.ledges.where((q) {
          final rise = q.y - 17 - p.y;
          final disc = p.vy * p.vy + 2 * GameEngine.gravity * rise;
          if (disc <= 0 || q.y < apex + 19 || q.id <= p.launch) return false;
          final flight = (-p.vy + math.sqrt(disc)) / GameEngine.gravity;
          final nearest = p.x.clamp(q.x + 18, q.x + q.w - 18);
          return (nearest - p.x).abs() < math.max(0, flight - .10) * 245;
        }).toList()..sort((a, b) => b.id.compareTo(a.id));
        if (reachable.isNotEmpty) target = reachable.first;
      }
      final q = target;
      if (q != null) {
        final aim = q.x + q.w / 2;
        final error = aim - p.x - p.vx * .055;
        simulation.direction = error.abs() < 7 ? 0 : error.sign.toInt();
        simulation.moveTime = .2;
      }
    }
    wasGrounded = p.grounded;
    simulation.tick(dt);
  }

  Map<String, dynamic> get peer => {
    'id': 'practice',
    'face': simulation.player.face,
    'animationPhase': simulation.player.animationPhase,
    'movement': simulation.player.airborne
        ? .65
        : (simulation.player.vx.abs() / 160).clamp(0.0, 1.0),
    'gazeX': simulation.player.gazeX,
    'gazeY': simulation.player.gazeY,
    'airborne': simulation.player.airborne,
    'rocket': simulation.player.rocket > 0,
    'spin': simulation.player.flip && simulation.player.airborne
        ? math.min(simulation.player.flight / .52, 1) *
              math.pi *
              2 *
              simulation.player.flipTurns *
              simulation.player.face
        : 0.0,
    'name': name,
    'x': simulation.player.x,
    'y': simulation.player.y,
    'step': simulation.highest,
    'skin': 'pip',
    'character': simulation.character,
    'status': out ? 'out' : 'live',
  };
}
