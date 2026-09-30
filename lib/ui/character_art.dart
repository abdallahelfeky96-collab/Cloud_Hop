import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uses the supplied artwork unchanged. Two source regions, female then male.
class CharacterArt {
  static final Future<ui.Image> image = _load();
  static final Future<ui.Image> animatedBody = _loadAsset(
    'assets/ui/character_bodies.png',
  );
  static Future<ui.Image> _load() => _loadAsset('assets/ui/characters.png');
  static Future<ui.Image> _loadAsset(String asset) async {
    final bytes = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  // Generated bodies have unequal cell margins; avoid clipping the curls.
  static Rect bodyRegion(ui.Image image, String character) => Rect.fromLTRB(
    character.startsWith('female') ? 0 : image.width * (950 / 1774),
    0,
    character.startsWith('female')
        ? image.width * (950 / 1774)
        : image.width.toDouble(),
    image.height.toDouble(),
  );

  static Rect region(ui.Image image, String character) => Rect.fromLTWH(
    character.startsWith('female') ? 0 : image.width / 2,
    0,
    image.width / 2,
    image.height.toDouble(),
  );
}

class CharacterPortrait extends StatelessWidget {
  final String character;
  final double size;
  const CharacterPortrait({super.key, required this.character, this.size = 70});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$character character',
    child: SizedBox.square(
      dimension: size,
      child: FutureBuilder<ui.Image>(
        future: CharacterArt.image,
        builder: (context, snapshot) => snapshot.hasData
            ? ClipOval(
                child: CustomPaint(
                  painter: _Portrait(snapshot.data!, character),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );
}

class _Portrait extends CustomPainter {
  final ui.Image image;
  final String character;
  _Portrait(this.image, this.character);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      CharacterArt.region(image, character),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_Portrait old) =>
      old.character != character || old.image != image;
}
