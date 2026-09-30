import 'package:cloud_hop/ui/cartoon_controls.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_hop/game/engine.dart';
import 'package:cloud_hop/game/challenge.dart';
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
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
                modes: noop,
                cancelSearch: noop,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getCenter(
              find.byWidgetPredicate(
                (w) =>
                    w is CartoonButton &&
                    w.art == artForIcon(Icons.play_arrow_rounded),
              ),
            )
            .dx,
        closeTo(195, 1),
      );
      final shop = tester.getCenter(
        find.byWidgetPredicate(
          (w) =>
              w is CartoonButton &&
              w.art == artForIcon(Icons.shopping_bag_rounded),
        ),
      );
      final friends = tester.getCenter(
        find.byWidgetPredicate(
          (w) =>
              w is CartoonButton &&
              w.art == artForIcon(Icons.people_alt_rounded),
        ),
      );
      final reward = tester.getCenter(
        find.byWidgetPredicate(
          (w) =>
              w is CartoonButton &&
              w.art == artForIcon(Icons.ondemand_video_rounded),
        ),
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
        await File('preview/${mode.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(
              find.byWidgetPredicate(
                (w) =>
                    w is CartoonButton &&
                    w.art == artForIcon(Icons.play_arrow_rounded),
              ),
            )
            .bottom,
        lessThan(
          tester
              .getRect(
                find.byWidgetPredicate(
                  (w) =>
                      w is CartoonButton &&
                      w.art == artForIcon(Icons.shopping_bag_rounded),
                ),
              )
              .top,
        ),
      );
    });
  }

  testWidgets('result screen offers rematch to the host and a guest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = PlayerSettings(await SharedPreferences.getInstance());
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    void noop() {}

    Widget overlay({
      required bool inRace,
      required bool host,
      bool waiting = false,
    }) =>
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: teal),
          ),
          home: Scaffold(
            body: HomeOverlay(
              mode: PlayMode.over,
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
              modes: noop,
              cancelSearch: noop,
              inRace: inRace,
              spectateHost: host,
              rematchWaiting: waiting,
            ),
          ),
        );

    // Host in a room restarts the same room.
    await tester.pumpWidget(overlay(inRace: true, host: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Play again'), findsOneWidget);

    // A guest asks the host instead.
    await tester.pumpWidget(overlay(inRace: true, host: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Request rematch'), findsOneWidget);

    // After requesting, the guest waits.
    await tester.pumpWidget(overlay(inRace: true, host: false, waiting: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Request rematch'), findsNothing);
    expect(find.text('Waiting for host…'), findsOneWidget);

    // Solo practice keeps the plain Play again button.
    await tester.pumpWidget(overlay(inRace: false, host: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Request rematch'), findsNothing);
  });

  testWidgets('avatar ticks once the player has requested a rematch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = PlayerSettings(await SharedPreferences.getInstance());
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    void noop() {}

    Widget avatar({required bool requested}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal),
      ),
      home: Scaffold(
        body: Center(
          child: ProfileAvatar(
            photoUrl: null,
            accountName: 'Player',
            busy: false,
            rematchRequested: requested,
          ),
        ),
      ),
    );

    final tick = find.byIcon(Icons.check_rounded);
    await tester.pumpWidget(avatar(requested: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tick, findsNothing);

    await tester.pumpWidget(avatar(requested: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tick, findsOneWidget);
  });

  testWidgets('home Modes button lists every mode and applies the choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = PlayerSettings(prefs);
    expect(settings.choice, GameChoice.classic);
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    void noop() {}
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: teal),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setHost) => HomeOverlay(
              mode: PlayMode.menu,
              settings: settings,
              coins: 420,
              steps: 85,
              earned: 38,
              busy: false,
              searching: false,
              result: '',
              play: noop,
              home: noop,
              room: noop,
              shop: noop,
              friends: noop,
              reward: noop,
              preferences: noop,
              profile: noop,
              modes: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => ModePickerSheet(
                    settings: settings,
                    onChanged: () {
                      changed++;
                      setHost(() {});
                    },
                  ),
                );
              },
              cancelSearch: noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Modes'), findsOneWidget);
    // The current mode stays visible on the home screen.
    expect(find.text('Classic'), findsOneWidget);

    await tester.tap(find.text('Modes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Every mode is listed inside the popup.
    final sheet = find.byType(ModePickerSheet);
    for (final name in modeNames) {
      expect(
        find.descendant(of: sheet, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }

    await tester.tap(
      find.descendant(
        of: sheet,
        matching: find.text('First to the finish · three attempts each'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(settings.choice, GameChoice.race);
    expect(changed, 1);
    // Race exposes the finish-line picker.
    expect(
      find.descendant(of: sheet, matching: find.text('Race finish line')),
      findsOneWidget,
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    // Home screen now reflects the new mode.
    expect(find.text('Race'), findsOneWidget);
    // Persisted for the next launch.
    expect(prefs.getInt('choice'), GameChoice.race.index);
  });
}
