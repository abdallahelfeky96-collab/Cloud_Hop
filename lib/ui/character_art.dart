import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/character.dart';

/// Character artwork sourced from `assets/ui/characters.png` (selection and
/// UI portraits) and `assets/ui/character_bodies.png` (in-game body sprites).
/// Both sheets hold two full-figure cells: female first, male second.
class CharacterArt {
  /// Sheet of the four selectable characters, used for the mini avatars in
  /// the selection chips, the HUD and the results leaderboard.
  static final Future<ui.Image> image = _load();
  /// In-game body sprite sheet drawn by `GamePainter`.
  static final Future<ui.Image> animatedBody = _loadAsset(
    'assets/ui/character_bodies.png',
  );

  /// Every character the player can pick. Keeping one list means the
  /// selection chips, the HUD and the leaderboard can never drift apart.
  static const List<({String id, String label})> all = Character.all;

  static bool isKnown(String character) => Character.isKnown(character);

  /// Falls back to the default so a bad network value can never blank a
  /// sprite or crash the painter.
  static String normalize(String? character) => Character.normalize(character);

  static Future<ui.Image> _load() => _loadAsset('assets/ui/characters.png');
  static Future<ui.Image> _loadAsset(String asset) async {
    final bytes = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Female cells are wider than male ones, so the sheet is not a clean 50/50
  /// split. These are the measured opaque bounds of the two cells in
  /// `character_bodies.png` (1774x887: female 27-943, male 971-1698); the
  /// boundary is the midpoint of the gap between them.
  static const double _bodySplit = 957 / 1774;

  // Generated bodies have unequal cell margins; avoid clipping the curls.
  static Rect bodyRegion(ui.Image image, String character) {
    final split = image.width * _bodySplit;
    final female = normalize(character).startsWith('female');
    return Rect.fromLTRB(female ? 0 : split, 0, female ? split : image.width.toDouble(), image.height.toDouble());
  }

  /// Cell in `characters.png` (1847x851: female 51-909, male 972-1765).
  static Rect region(ui.Image image, String character) =>
      Rect.fromLTWH(
        normalize(character).startsWith('female') ? 0 : image.width / 2,
        0,
        image.width / 2,
        image.height.toDouble(),
      );

  /// Head-and-shoulders crop used by the mini avatars. Squeezing a whole
  /// body into a small circle loses the face, so take the top of the cell.
  static Rect portraitRegion(ui.Image image, String character) {
    final cell = region(image, character);
    return Rect.fromLTWH(
      cell.left + cell.width * .18,
      cell.top,
      cell.width * .64,
      cell.height * .34,
    );
  }
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
            // Decode is fast but not synchronous: show a neutral placeholder
            // instead of a blank hole so the chip never looks empty.
            : const ColoredBox(color: Color(0x14000000)),
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
    final src = CharacterArt.portraitRegion(image, character);
    // Preserve the crop's aspect ratio inside the square, centred.
    final scale = (size.width / src.width).clamp(
      0.0,
      size.height / src.height,
    );
    final dst = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: src.width * scale,
      height: src.height * scale,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_Portrait old) =>
      old.character != character || old.image != image;
}

/// Mini avatar for character chips, the HUD and the results leaderboard.
/// Uses the same `characters.png` sheet as [CharacterPortrait] but keeps the
/// head crop so it stays readable at chip size.
class CharacterMini extends StatelessWidget {
  final String character;
  final double size;
  final Color? border;
  const CharacterMini({
    super.key,
    required this.character,
    this.size = 28,
    this.border,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$character character',
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<ui.Image>(
        future: CharacterArt.image,
        builder: (context, snapshot) => snapshot.hasData
            ? CustomPaint(painter: _Portrait(snapshot.data!, character))
            : const SizedBox.shrink(),
      ),
    ),
  );
}
