import 'ui_sounds.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Row-major atlas order, matching the approved Cloud Hop artwork.
enum CartoonArt {
  play,
  back,
  home,
  pause,
  settings,
  profile,
  shop,
  friends,
  room,
  invite,
  rocket,
  trampoline,
  life,
  gift,
  coins,
  ad,
  revive,
  mic,
  micOff,
  close,
  sound,
  soundOff,
  classic,
  challenge,
  joystick,
  rock,
}

CartoonArt? artForIcon(IconData icon) {
  if ([
    Icons.play_arrow,
    Icons.play_arrow_rounded,
    Icons.login_rounded,
  ].contains(icon))
    return CartoonArt.play;
  if ([
    Icons.arrow_back,
    Icons.arrow_back_rounded,
    Icons.logout_rounded,
  ].contains(icon))
    return CartoonArt.back;
  if ([Icons.home, Icons.home_rounded].contains(icon)) return CartoonArt.home;
  if ([Icons.pause, Icons.pause_rounded].contains(icon))
    return CartoonArt.pause;
  if ([Icons.settings, Icons.settings_rounded].contains(icon))
    return CartoonArt.settings;
  if ([
    Icons.person,
    Icons.person_rounded,
    Icons.account_circle_rounded,
    Icons.verified_user_rounded,
    Icons.face,
  ].contains(icon))
    return CartoonArt.profile;
  if ([Icons.shopping_bag, Icons.shopping_bag_rounded].contains(icon))
    return CartoonArt.shop;
  if ([Icons.people, Icons.people_alt_rounded].contains(icon))
    return CartoonArt.friends;
  if ([Icons.group_add, Icons.group_add_rounded].contains(icon))
    return CartoonArt.room;
  if ([Icons.person_add, Icons.copy].contains(icon)) return CartoonArt.invite;
  if ([Icons.rocket_launch, Icons.rocket_launch_rounded].contains(icon))
    return CartoonArt.rocket;
  if ([Icons.horizontal_rule, Icons.horizontal_rule_rounded].contains(icon))
    return CartoonArt.trampoline;
  if ([Icons.favorite, Icons.favorite_rounded].contains(icon))
    return CartoonArt.life;
  if (icon == Icons.circle) return CartoonArt.rock;
  if ([Icons.card_giftcard, Icons.card_giftcard_rounded].contains(icon))
    return CartoonArt.gift;
  if ([Icons.monetization_on, Icons.toll].contains(icon))
    return CartoonArt.coins;
  if ([Icons.ondemand_video, Icons.ondemand_video_rounded].contains(icon))
    return CartoonArt.ad;
  if (icon == Icons.refresh) return CartoonArt.revive;
  if (icon == Icons.mic) return CartoonArt.mic;
  if (icon == Icons.mic_off) return CartoonArt.micOff;
  if ([Icons.close, Icons.close_rounded].contains(icon))
    return CartoonArt.close;
  if (icon == Icons.volume_up) return CartoonArt.sound;
  if (icon == Icons.volume_off) return CartoonArt.soundOff;
  if (icon == Icons.sports_esports) return CartoonArt.joystick;
  if ([
    Icons.flag,
    Icons.emoji_events_rounded,
    Icons.handshake_rounded,
  ].contains(icon))
    return CartoonArt.challenge;
  if (icon == Icons.smart_toy_rounded) return CartoonArt.classic;
  return null;
}

class CartoonAtlas {
  static Future<ui.Image>? _image;
  static Future<ui.Image> get image => _image ??= _load();
  static Future<ui.Image> _load() async {
    final bytes = await rootBundle.load('assets/ui/cartoon_controls.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}

class CartoonSprite extends StatelessWidget {
  final CartoonArt art;
  final double size;
  const CartoonSprite(this.art, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: FutureBuilder<ui.Image>(
      future: CartoonAtlas.image,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x55fff4d8),
              shape: BoxShape.circle,
            ),
          );
        }
        return RepaintBoundary(
          child: CustomPaint(
            painter: CartoonSpritePainter(snapshot.data!, art),
          ),
        );
      },
    ),
  );
}

class CartoonSpritePainter extends CustomPainter {
  final ui.Image image;
  final CartoonArt art;
  CartoonSpritePainter(this.image, this.art);
  @override
  void paint(Canvas canvas, Size size) {
    if (art == CartoonArt.rock) {
      final bounds = Offset.zero & size;
      final outline = Paint()
        ..color = const Color(0xff493c35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .055
        ..strokeJoin = StrokeJoin.round;
      final stone = Path()
        ..moveTo(size.width * .18, size.height * .72)
        ..lineTo(size.width * .12, size.height * .48)
        ..lineTo(size.width * .34, size.height * .17)
        ..lineTo(size.width * .62, size.height * .13)
        ..lineTo(size.width * .87, size.height * .41)
        ..lineTo(size.width * .82, size.height * .69)
        ..lineTo(size.width * .62, size.height * .84)
        ..lineTo(size.width * .35, size.height * .83)
        ..close();
      canvas.drawShadow(stone, const Color(0x55392e28), 3, true);
      canvas.drawPath(
        stone,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffaa9a88), Color(0xff78695f), Color(0xff554a43)],
          ).createShader(bounds),
      );
      canvas.drawPath(stone, outline);
      canvas.drawOval(
        Rect.fromLTWH(
          size.width * .30,
          size.height * .29,
          size.width * .18,
          size.height * .10,
        ),
        Paint()..color = const Color(0xffc8b8a3).withValues(alpha: .8),
      );
      canvas.drawOval(
        Rect.fromLTWH(
          size.width * .58,
          size.height * .53,
          size.width * .12,
          size.height * .08,
        ),
        Paint()..color = const Color(0xffc8b8a3).withValues(alpha: .55),
      );
      return;
    }
    // Atlas-specific transparent gutters. Do not assume equally spaced rows:
    // the approved generated sprites have slightly different silhouettes.
    const columns = [0.0, 253.0, 503.0, 745.0, 988.0, 1254.0];
    const rows = [0.0, 282.0, 507.0, 741.0, 982.0, 1254.0];
    final col = art.index % 5, row = art.index ~/ 5;
    final source = Rect.fromLTRB(
      columns[col],
      rows[row],
      columns[col + 1],
      rows[row + 1],
    );
    final scale = math.min(
      size.width / source.width,
      size.height / source.height,
    );
    final target = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: source.width * scale,
      height: source.height * scale,
    );
    canvas.drawImageRect(
      image,
      source,
      target,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(CartoonSpritePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.art != art;
}

/// Drop-in artwork for existing icon slots; preserves utility glyphs without
/// an approved sprite (such as radio selections).
class CartoonIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  const CartoonIcon(this.icon, {super.key, this.size, this.color});
  @override
  Widget build(BuildContext context) {
    final art = artForIcon(icon);
    return art == null
        ? Icon(icon, size: size, color: color)
        : CartoonSprite(art, size: size ?? 36);
  }
}

class CartoonButton extends StatefulWidget {
  final CartoonArt art;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool idle;
  const CartoonButton({
    super.key,
    required this.art,
    required this.label,
    required this.onTap,
    this.size = 64,
    this.idle = false,
  });
  @override
  State<CartoonButton> createState() => _CartoonButtonState();
}

class _CartoonButtonState extends State<CartoonButton>
    with TickerProviderStateMixin {
  late final AnimationController idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 360),
  );
  bool reduced = false;
  void syncMotion() {
    if (widget.idle &&
        widget.onTap != null &&
        !reduced &&
        TickerMode.of(context)) {
      if (!idle.isAnimating) idle.repeat(reverse: true);
    } else {
      idle.stop();
      idle.value = 0;
    }
    if (reduced) {
      press.stop();
      press.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    syncMotion();
  }

  @override
  void didUpdateWidget(CartoonButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncMotion();
  }

  @override
  void dispose() {
    idle.dispose();
    press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.label,
    child: Tooltip(
      message: widget.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([idle, press]),
          builder: (context, child) {
            final wave = reduced ? 0.0 : math.sin(idle.value * math.pi);
            final compression = reduced
                ? 0.0
                : Curves.easeOutBack.transform(press.value);
            return Transform.translate(
              offset: Offset(0, -2 * wave + 3 * compression),
              child: Transform.scale(
                scaleX: 1 + .025 * wave + .05 * compression,
                scaleY: 1 + .025 * wave - .11 * compression,
                child: Opacity(
                  opacity: widget.onTap == null ? .42 : 1,
                  child: child,
                ),
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              excludeFromSemantics: true,
              onTap: UiSounds.wrap(widget.onTap),
              onHighlightChanged: (down) {
                if (!reduced && widget.onTap != null) {
                  down ? press.forward() : press.reverse();
                }
              },
              child: ExcludeSemantics(
                child: CartoonSprite(widget.art, size: widget.size),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
