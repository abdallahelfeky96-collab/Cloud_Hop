import 'dart:math' as math;

import 'engine.dart';

enum GameChoice { classic, personalBest, quick }

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

/// A visible practice opponent, never presented as a real person.
class PracticeRival {
  final String name;
  final int bestTarget;
  double elapsed = 0, step = 0, x = 210, y = 623;
  PracticeRival(String country, String city, {this.bestTarget = 0, int seed = 1})
    : name = bestTarget > 0
          ? 'Your best'
          : '${(regions[country]?[city] ?? ['Pip'])[math.Random(seed).nextInt((regions[country]?[city] ?? ['Pip']).length)]} · BOT';

  void tick(double dt, GameEngine game) {
    elapsed += dt;
    // Early leads alternate; later the training rival eases off for a comeback.
    final pace = bestTarget > 0 ? bestTarget / 120 : .7;
    final desired = bestTarget > 0
        ? math.min(bestTarget.toDouble(), elapsed * pace)
        : math.max(
            0.0,
            game.highest + (elapsed < 75 ? 2 * math.sin(elapsed / 5) + 1 : -2),
          );
    step += (desired - step).clamp(-dt * 2, dt * 2);
    final near = game.ledges.where((q) => q.id >= step.floor()).toList();
    if (near.isNotEmpty) {
      final q = near.first;
      x += (q.x + q.w / 2 - x) * math.min(1, dt * 5);
      y +=
          (q.y - 17 - 55 * math.sin(elapsed * 4).abs() - y) *
          math.min(1, dt * 8);
    } else {
      y = 623 - step * 90;
    }
  }

  Map<String, dynamic> get peer => {
    'id': 'practice',
    'name': name,
    'x': x,
    'y': y,
    'step': step.floor(),
    'skin': 'berry',
    'status': 'live',
  };
}
