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
  GamePainter(this.game, {this.peers = const [], this.reducedMotion = false});
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

  void avatar(
    Canvas c,
    double x,
    double y,
    String skin, {
    double spin = 0,
    bool rocket = false,
    int face = 1,
    double stride = 0,
    bool lookUp = false,
  }) {
    c.save();
    c.translate(x, y);
    c.rotate(spin);
    // Mirror the whole body when heading left.
    c.scale(face >= 0 ? 1.0 : -1.0, 1.0);
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
    if (rocket) {
      pill(c, x - 13, y + 17, 26, 20, const Color(0xff71869c));
      oval(c, x, y + 45, 9, 16, const Color(0xfff5a74a));
      oval(c, x, y + 41, 5, 11, const Color(0xfffff1a8));
    }
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
        text(
          canvas,
          q.gift == 'ad' ? '▷' : '🎁',
          q.x + q.w / 2,
          y - 43,
          size: 23,
        );
      }
    }
    int above = 0, below = 0;
    for (final peer in peers) {
      if (peer['status'] == 'out') continue;
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
        avatar(canvas, x, y, peer['skin'] as String? ?? 'pip');
        text(canvas, name, x, y - 40);
      }
    }
    final p = game.player,
        spin = p.flip && p.airborne && !reducedMotion
            ? math.min(p.flight / .52, 1) * math.pi * 2 * p.face
            : 0.0;
    // Limb cycle follows distance run on the ground, airtime in the air.
    double stride = 0;
    if (!reducedMotion && (p.vx.abs() > 30 || (p.airborne && p.flip))) {
      stride = p.grounded ? p.run * .12 : p.flight * 10;
    }
    avatar(
      canvas,
      p.x,
      p.y - game.camera,
      game.progress.skin,
      spin: spin,
      rocket: p.rocket > 0,
      face: p.face,
      stride: stride,
      lookUp: p.airborne && p.vy < -50,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
