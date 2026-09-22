import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_hop/game/engine.dart';
import 'package:cloud_hop/services/social.dart';
import 'package:cloud_hop/ui/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in [PlayMode.menu, PlayMode.over]) {
    testWidgets('$mode has a central play button and horizontal actions', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = PlayerSettings(await SharedPreferences.getInstance());
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (Platform.isWindows) {
        final font = File(
          '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
        );
        if (font.existsSync()) {
          await (FontLoader('PreviewFont')..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
        }
      }
      final boundary = GlobalKey();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      void noop() {}
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PreviewFont',
            colorScheme: ColorScheme.fromSeed(seedColor: teal),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: HomeOverlay(
                mode: mode,
                settings: settings,
                coins: 420,
                steps: 85,
                earned: 38,
                busy: false,
                searching: false,
                result: 'You win! · Practice bot',
                play: noop,
                home: noop,
                room: noop,
                shop: noop,
                friends: noop,
                reward: noop,
                preferences: noop,
                profile: noop,
                cancelSearch: noop,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byIcon(Icons.play_arrow_rounded)).dx,
        closeTo(195, 1),
      );
      final shop = tester.getCenter(find.byIcon(Icons.shopping_bag_rounded));
      final friends = tester.getCenter(find.byIcon(Icons.people_alt_rounded));
      final reward = tester.getCenter(
        find.byIcon(Icons.ondemand_video_rounded),
      );
      expect(shop.dy, friends.dy);
      expect(friends.dy, reward.dy);
      expect(shop.dx, lessThan(friends.dx));
      expect(friends.dx, lessThan(reward.dx));
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('preview').create();
        await File(
          'preview/${mode.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byIcon(Icons.play_arrow_rounded)).bottom,
        lessThan(tester.getRect(find.byIcon(Icons.shopping_bag_rounded)).top),
      );
    });
  }
}
