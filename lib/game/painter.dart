import 'dart:ui' as ui;

import '../ui/cartoon_controls.dart';
import '../ui/character_art.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine.dart';

const skyThemes = [
  [Color(0xffb8dfe3), Color(0xffe1eedc), Color(0xfff1e7bb)],
  [Color(0xffd3c7ed), Color(0xfff4dcdf), Color(0xffffe8cb)],
  [Color(0xff94cae6), Color(0xffd1ecf2), Color(0xffe6f7f5)],
  [Color(0xffe9b0b2), Color(0xfff7ceaa), Color(0xffffecc2)],
  [Color(0xffa3a5d6), Color(0xffc7c4e7), Color(0xffe5d5ed)],
];
Color skinColor(String skin) => switch (skin) {
  'mint' => const Color(0xff78bd94),
  'cosmo' => const Color(0xffada2e5),
  'berry' => const Color(0xffe690ad),
  _ => const Color(0xfff1a657),
};

class GamePainter extends CustomPainter {
  final GameEngine game;
  final List<Map<String, dynamic>> peers;
  final bool reducedMotion;
  final ui.Image? controls, characters;
  GamePainter(
    this.game, {
    this.peers = const [],
    this.reducedMotion = false,
    this.controls,
    this.characters,
  });
  void pill(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    Color color, [
    double radius = 8,
  ]) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(radius),
      ),
      Paint()..color = color,
    );
  }

  void oval(Canvas c, double x, double y, double rx, double ry, Color color) {
    c.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
      Paint()..color = color,
    );
  }

  void text(
    Canvas c,
    String value,
    double x,
    double y, {
    double size = 10,
    Color color = const Color(0xff395e4b),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);
    tp.paint(c, Offset(x - tp.width / 2, y));
  }

  void backpackRocket(Canvas c, int face) {
    c.save();
    c.translate(face >= 0 ? -27 : 27, -20);
    final outline = Paint()
      ..color = const Color(0xff493329)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final flame = reducedMotion ? 15.0 : 15 + math.sin(game.time * 34) * 3;
    oval(c, 0, 32, 6, flame, const Color(0xffffa332));
    oval(c, 0, 29, 3, flame * .65, const Color(0xffffef99));
    final fins = Path()
      ..moveTo(-7, 8)
      ..lineTo(-14, 24)
      ..lineTo(-5, 21)
      ..lineTo(5, 21)
      ..lineTo(14, 24)
      ..lineTo(7, 8)
      ..close();
    c.drawPath(fins, Paint()..color = const Color(0xffe96556));
    c.drawPath(fins, outline);
    final shell = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, -22, 16, 45),
      const Radius.circular(8),
    );
    c.drawRRect(shell, Paint()..color = const Color(0xfffff0ce));
    c.drawRRect(shell, outline);
    final nose = Path()
      ..moveTo(-8, -20)
      ..quadraticBezierTo(-6, -30, 0, -35)
      ..quadraticBezierTo(6, -30, 8, -20)
      ..close();
    c.drawPath(nose, Paint()..color = const Color(0xffe96556));
    c.drawPath(nose, outline);
    oval(c, 0, -9, 5, 6, const Color(0xff487278));
    oval(c, 0, -10, 3.3, 4, const Color(0xff94e4e5));
    pill(c, -8, 17, 16, 4, const Color(0xff65888a), 2);
    c.restore();
  }

  void avatar(
    Canvas c,
    double x,
    double y,
    String skin, {
    String character = 'male',
    double spin = 0,
    bool rocket = false,
    int face = 1,
    double stride = 0,
    bool lookUp = false,
    double gazeX = 0,
    double gazeY = 0,
    double movement = 0,
    bool airborne = false,
  }) {
    c.save();
    c.translate(x, y);
    c.rotate(spin);
    // Keep the face stable when steering; gaze follows motion without flipping the hair.
    if (rocket) backpackRocket(c, face);
    if (characters != null) {
      // Only the background has alpha. The artwork uses ordinary opaque compositing.
      final swing = reducedMotion ? 0.0 : math.sin(stride) * movement;
      final lift = airborne ? -2.0 : 0.0;
      void limb(Offset root, Offset joint, Offset end, double width) {
        final path = Path()
          ..moveTo(root.dx, root.dy)
          ..quadraticBezierTo(joint.dx, joint.dy, end.dx, end.dy);
        c.drawPath(
          path,
          Paint()
            ..color = const Color(0xff502708)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width + 3,
        );
        c.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(root, end, [
              const Color(0xffffdf70),
              const Color(0xfff2a62e),
            ])
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width,
        );
        oval(
          c,
          end.dx - 1,
          end.dy - 1,
          width * .22,
          width * .15,
          const Color(0xffffedaa),
        );
      }

      final female = character.startsWith('female');
      final rounded = character.endsWith('_round');
      final shoe = female ? const Color(0xffed84ae) : const Color(0xfffffff4);
      limb(
        const Offset(-7, 6),
        Offset(-8, 11 + lift),
        Offset(-9 - swing * 2.5, 14 + lift),
        5,
      );
      limb(
        const Offset(7, 6),
        Offset(8, 11 + lift),
        Offset(9 + swing * 2.5, 14 + lift),
        5,
      );
      for (final side in [-1.0, 1.0]) {
        final footX = side * (9 + swing * 2.5);
        oval(c, footX, 15 + lift, 6, 3.2, const Color(0xff513524));
        oval(c, footX, 14.6 + lift, 5.1, 2.5, shoe);
        pill(c, footX - 4, 15.8 + lift, 8, 1.1, Colors.white, 1);
      }
      limb(
        const Offset(-12, -12),
        Offset(-16, -7 + swing * 2),
        Offset(-18, -2 + swing * 3),
        5,
      );
      limb(
        const Offset(12, -12),
        Offset(16, -7 - swing * 2),
        Offset(18, -2 - swing * 3),
        5,
      );
      // Soft rounded palms keep the supplied characters readable at game scale.
      for (final side in [-1.0, 1.0]) {
        final handX = side * 18;
        final handY = -2 + (side < 0 ? swing : -swing) * 3;
        final handSize = rounded ? 5.0 : 3.8;
        oval(c, handX, handY, handSize, handSize, const Color(0xff502708));
        oval(
          c,
          handX,
          handY - .4,
          handSize * .77,
          handSize * .77,
          const Color(0xffffc451),
        );
      }
      final clothes = Path()
        ..moveTo(-10, -17)
        ..lineTo(10, -17)
        ..lineTo(female ? 16 : 12, female ? 9 : 3)
        ..lineTo(female ? -16 : -12, female ? 9 : 3)
        ..close();
      if (female) {
        c.drawPath(clothes, Paint()..color = const Color(0xffffa5c5));
        c.drawPath(
          clothes,
          Paint()
            ..color = const Color(0xff664536)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      if (female) {
        pill(c, -10, -3, 20, 2, const Color(0xffed75a3), 1);
        for (final x in [-8.0, 0.0, 8.0])
          c.drawLine(
            Offset(x * .7, 0),
            Offset(x, 7),
            Paint()
              ..color = const Color(0xfff18fb2)
              ..strokeWidth = .8,
          );
      } else {
        // Short sleeves connect directly into the fitted shirt.
        for (final side in [-1.0, 1.0]) {
          final sleeve = Path()
            ..moveTo(side * 9, -16)
            ..quadraticBezierTo(side * 14, -15, side * 16, -10);
          c.drawPath(
            sleeve,
            Paint()
              ..color = const Color(0xff664536)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 8,
          );
          c.drawPath(
            sleeve,
            Paint()
              ..color = const Color(0xfffffff7)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 5,
          );
        }
        // Fitted shirt tailored like the female dress cut: outlined torso
        // with side seams, then a denim waistband and shorts. No chain.
        final shirt = Path()
          ..moveTo(-10, -17)
          ..lineTo(10, -17)
          ..lineTo(14, 7)
          ..lineTo(-14, 7)
          ..close();
        c.drawPath(shirt, Paint()..color = const Color(0xfffffff7));
        c.drawPath(
          shirt,
          Paint()
            ..color = const Color(0xff664536)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        for (final x in [-8.0, 0.0, 8.0])
          c.drawLine(
            Offset(x * .7, -2),
            Offset(x, 5),
            Paint()
              ..color = const Color(0xffa9c6d8)
              ..strokeWidth = .8,
          );
        pill(c, -13, 5, 26, 2.6, const Color(0xff5089af), 1);
        pill(c, -12, 7, 24, 5, const Color(0xff86bfdf), 2);
        c.drawLine(
          const Offset(0, 8),
          const Offset(0, 12),
          Paint()
            ..color = const Color(0xff5089af)
            ..strokeWidth = 1,
        );
      }
      c.drawImageRect(
        characters!,
        CharacterArt.bodyRegion(characters!, character),
        const Rect.fromLTWH(-27, -59, 54, 49),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = const ColorFilter.matrix([
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1.02,
            0,
          ]),
      );
      // Small coordinated glances preserve the original friendly expression.
      // The broader male face carries the eyes slightly wider and lower,
      // matching their relative placement on the female artwork.
      final lookX = gazeX.clamp(-1.0, 1.0) * .65;
      final lookY = gazeY.clamp(-1.0, 1.0) * .55;
      final blink = !reducedMotion && game.time % 4.6 > 4.45;
      final eyeSpread = female ? 9.0 : 10.0;
      final eyeBaseY = female ? -32.0 : -31.0;
      for (final eyeX in [-eyeSpread, eyeSpread]) {
        oval(
          c,
          eyeX + lookX,
          eyeBaseY + lookY,
          3.1,
          blink ? .65 : 4.2,
          const Color(0xff291701),
        );
        if (!blink)
          oval(
            c,
            eyeX + lookX + .8,
            eyeBaseY - 1.7 + lookY,
            .9,
            1.1,
            const Color(0xfffffff3),
          );
      }
      c.restore();
      return;
    }
    final color = skinColor(skin),
        hat = skin == 'berry'
            ? const Color(0xffa65782)
            : skin == 'cosmo'
            ? const Color(0xff8b81c7)
            : const Color(0xff4f7f64);
    // Run cycle: legs alternate, arms swing opposite. Stride 0 = idle pose.
    final left = math.sin(stride) * 5, right = math.sin(stride + math.pi) * 5;
    oval(
      c,
      -10 + left,
      18 - (left > 0 ? left * .8 : 0),
      8,
      5,
      const Color(0xff805c41),
    );
    oval(
      c,
      10 + right,
      18 - (right > 0 ? right * .8 : 0),
      8,
      5,
      const Color(0xff805c41),
    );
    pill(c, -21, -17, 42, 36, color, 15);
    oval(c, -22, 5 + right, 6, 8, color);
    oval(c, 22, 5 + left, 6, 8, color);
    pill(c, -19, -24, 38, 12, hat, 6);
    pill(c, -23, -15, 46, 5, hat, 2);
    pill(c, -13, -3, 26, 17, const Color(0xffffdda3));
    // Eyes and smile ride up while ascending.
    final eyeY = lookUp ? -5.0 : -2.0;
    oval(c, -7, eyeY, 2.2, 3.1, const Color(0xff394840));
    oval(c, 7, eyeY, 2.2, 3.1, const Color(0xff394840));
    c.drawArc(
      Rect.fromCircle(center: Offset(0, lookUp ? 1 : 4), radius: 3),
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xff825334)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (skin == 'mint') {
      for (final x in [-11.0, 11.0]) {
        oval(c, x, -25, 7, 7, color);
        oval(c, x, -26, 3, 3, Colors.white);
        oval(c, x, -26, 1.5, 2, const Color(0xff395647));
      }
    }
    if (skin == 'cosmo') {
      text(c, '★', 0, -25, size: 12, color: const Color(0xffffe69b));
    }
    if (skin == 'berry') {
      oval(c, 10, -25, 6, 4, const Color(0xffffdeae));
      oval(c, 20, -25, 6, 4, const Color(0xffffdeae));
    }
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / GameEngine.width;
    canvas.save();
    canvas.scale(scale);
    final h = size.height / scale;
    final index = switch (game.progress.sky) {
          'candy' => 1,
          'sunset' => 3,
          'aurora' => 4,
          _ => (game.level - 1) % 5,
        },
        colors = skyThemes[index];
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 420, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Rect.fromLTWH(0, 0, 420, h)),
    );
    oval(canvas, 330, 160, 44, 44, const Color(0xfffff5c3));
    for (var i = 0; i < 9; i++) {
      final y = ((i * 137 - game.camera * .23) % (h + 160)) - 60,
          x = (i * 113 + 35) % 420.0;
      oval(canvas, x, y, 42, 14, Colors.white.withValues(alpha: .38));
      oval(canvas, x - 15, y - 10, 20, 17, Colors.white.withValues(alpha: .38));
      oval(canvas, x + 10, y - 17, 24, 22, Colors.white.withValues(alpha: .38));
    }
    if (game.progress.sky == 'aurora') {
      final path = Path()
        ..moveTo(0, 90)
        ..cubicTo(130, 0, 240, 260, 420, 90)
        ..lineTo(420, 150)
        ..cubicTo(240, 340, 130, 80, 0, 170)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: .22),
      );
    }
    for (final q in game.ledges) {
      final y = q.y - game.camera;
      if (y < -60 || y > h + 30) continue;
      final theme = (q.id ~/ 50) % 5,
          top = [
            0xff7cab70,
            0xffe396b4,
            0xff77c9de,
            0xffe9ad53,
            0xff9b8dda,
          ][theme];
      if (q.spring) {
        final path = Path()
          ..moveTo(q.x, y)
          ..quadraticBezierTo(q.x + q.w / 2, y + 6, q.x + q.w, y);
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff8260ad)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke,
        );
        canvas.drawLine(
          Offset(q.x, y - 7),
          Offset(q.x, y + 14),
          Paint()
            ..color = const Color(0xff8260ad)
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(q.x + q.w, y - 7),
          Offset(q.x + q.w, y + 14),
          Paint()
            ..color = const Color(0xff8260ad)
            ..strokeWidth = 2,
        );
      } else {
        pill(canvas, q.x + 2, y + 4, q.w, 18, const Color(0x15456754));
        pill(
          canvas,
          q.x,
          y,
          q.w,
          18,
          Color(theme == 0 ? 0xffb78e64 : top).withValues(alpha: .9),
        );
        pill(canvas, q.x, y, q.w, 8, Color(top));
        for (double x = q.x + 16; x < q.x + q.w - 8; x += 26) {
          oval(canvas, x, y + 12, 2, 1.5, Colors.white.withValues(alpha: .4));
        }
      }
      text(canvas, q.id.toString(), q.x + q.w / 2, y - 15, size: 9);
      if (q.gift != null && !q.claimed) {
        if (controls != null) {
          canvas.save();
          final bob = reducedMotion
              ? 0.0
              : math.sin(game.time * 2.5 + q.id) * 2;
          canvas.translate(q.x + q.w / 2 - 21, y - 54 + bob);
          CartoonSpritePainter(
            controls!,
            q.gift == 'ad' ? CartoonArt.ad : CartoonArt.gift,
          ).paint(canvas, const Size(42, 42));
          canvas.restore();
        } else {
          text(
            canvas,
            q.gift == 'ad' ? '▷' : '🎁',
            q.x + q.w / 2,
            y - 43,
            size: 23,
          );
        }
      }
    }
    int above = 0, below = 0;
    for (final peer in peers) {
      if (peer['status'] == 'out' || peer['status'] == 'spectator') continue;
      final x = (peer['x'] as num?)?.toDouble() ?? 210.0,
          y = ((peer['y'] as num?)?.toDouble() ?? 623.0) - game.camera,
          name = peer['name'] as String? ?? 'Pip';
      if (y < 100 || y > h - 90) {
        final top = y < 100, row = top ? above++ : below++;
        text(
          canvas,
          '${top ? '↑ ' : '↓ '}$name · ${peer['step']}',
          210,
          top ? 90 + row * 14.0 : h - 80 - row * 14,
        );
      } else {
        avatar(
          canvas,
          x,
          y,
          peer['skin'] as String? ?? 'pip',
          character: peer['character'] as String? ?? 'male',
          face: (peer['face'] as num?)?.toInt() ?? 1,
          stride: (peer['animationPhase'] as num?)?.toDouble() ?? 0,
          movement: (peer['movement'] as num?)?.toDouble() ?? 0,
          gazeX: (peer['gazeX'] as num?)?.toDouble() ?? 0,
          gazeY: (peer['gazeY'] as num?)?.toDouble() ?? 0,
          airborne: peer['airborne'] == true,
          rocket: peer['rocket'] == true,
          spin: reducedMotion ? 0 : (peer['spin'] as num?)?.toDouble() ?? 0,
        );
        // Keep the name clear of the taller hair and nearby step numbers.
        pill(canvas, x - 48, y - 66, 96, 16, const Color(0xfffff8e8));
        text(canvas, name, x, y - 65, size: 9);
      }
    }
    for (final r in game.rocks) {
      final y = r.y - game.camera;
      if (y < -30 || y > h + 30) continue;
      if (r.age < 0) continue;
      oval(canvas, r.x, y, 10 * r.scale, 10 * r.scale, const Color(0xff6b5a4e));
      oval(
        canvas,
        r.x - 3 * r.scale,
        y - 3 * r.scale,
        4 * r.scale,
        4 * r.scale,
        const Color(0xff9a8878),
      );
    }
    final p = game.player,
        spin = p.flip && p.airborne && !reducedMotion
            ? math.min(p.flight / .52, 1) * math.pi * 2 * p.flipTurns * p.face
            : 0.0;
    // Limb cycle follows distance run on the ground, airtime in the air.
    double stride = 0;
    if (!reducedMotion && (p.vx.abs() > 1 || p.airborne)) {
      stride = p.animationPhase;
    }
    if (game.mode != PlayMode.spectate)
      avatar(
        canvas,
        p.x,
        p.y - game.camera,
        game.progress.skin,
        character: game.character,
        spin: spin,
        rocket: p.rocket > 0,
        face: p.face,
        stride: stride,
        lookUp: p.airborne && p.vy < -50,
        gazeX: p.gazeX,
        gazeY: p.gazeY,
        movement: p.airborne ? .65 : (p.vx.abs() / 160).clamp(0.0, 1.0),
        airborne: p.airborne,
      );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
