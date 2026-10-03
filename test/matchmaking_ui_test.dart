import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_hop/ui/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> ready(WidgetTester tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    SharedPreferences.setMockInitialValues({});
  }

  Widget host(Widget child) => MaterialApp(
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: inner!,
    ),
    home: Scaffold(body: child),
  );

  group('cartoon race target slider', () {
    test('clamping keeps every value on the 100..1000 ten-step scale', () {
      expect(CartoonTargetSlider.clampTarget(0), 100);
      expect(CartoonTargetSlider.clampTarget(49), 100);
      expect(CartoonTargetSlider.clampTarget(100), 100);
      expect(CartoonTargetSlider.clampTarget(140), 100);
      expect(CartoonTargetSlider.clampTarget(160), 200);
      expect(CartoonTargetSlider.clampTarget(999), 1000);
      expect(CartoonTargetSlider.clampTarget(5000), 1000);
      expect(CartoonTargetSlider.stepCount, 10);
      expect(CartoonTargetSlider.minTarget, 100);
      expect(CartoonTargetSlider.maxTarget, 1000);
    });

    testWidgets('renders ten notches and the current step', (tester) async {
      await ready(tester);
      var picked = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (ctx, setHost) => CartoonTargetSlider(
              value: 300,
              onChanged: (v) {
                picked = v;
                setHost(() {});
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final slider = find.byType(CartoonTargetSlider);
      expect(find.descendant(of: slider, matching: find.text('300')), findsOneWidget);
      // Ten notches plus the track, the active fill and the knob.
      expect(
        find.descendant(
          of: slider,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.margin == null,
          ),
        ),
        findsWidgets,
      );
      expect(find.byType(DropdownButton<int>), findsNothing);
    });

    testWidgets('tapping the right half jumps to a later step', (tester) async {
      await ready(tester);
      var value = 100;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (ctx, setHost) => CartoonTargetSlider(
              value: value,
              onChanged: (v) {
                value = v;
                setHost(() {});
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strip = find.descendant(
        of: find.byType(CartoonTargetSlider),
        matching: find.byType(GestureDetector),
      );
      expect(strip, findsWidgets);
      final box = tester.getRect(strip.last);
      // Tap the far right: the last step.
      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(value, 1000);

      // And the far left: the first step.
      await tester.tapAt(Offset(box.left + 2, box.center.dy));
      await tester.pumpAndSettle();
      expect(value, 100);
    });

    testWidgets('a disabled slider ignores taps', (tester) async {
      await ready(tester);
      var changed = 0;
      await tester.pumpWidget(
        host(
          CartoonTargetSlider(
            value: 500,
            enabled: false,
            onChanged: (_) => changed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = find.descendant(
        of: find.byType(CartoonTargetSlider),
        matching: find.byType(GestureDetector),
      );
      final box = tester.getRect(strip.last);
      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pumpAndSettle();
      expect(changed, 0);
    });
  });

  group('match found banner', () {
    testWidgets('shows the cartoon confirmation and dismisses itself', (
      tester,
    ) async {
      await ready(tester);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showGeneralDialog<void>(
                  context: ctx,
                  barrierColor: Colors.transparent,
                  barrierLabel: 'match',
                  transitionDuration: const Duration(milliseconds: 180),
                  pageBuilder: (_, _, _) => const MatchFoundBanner(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MatchFoundBanner), findsOneWidget);
      expect(find.text('Match found!'), findsOneWidget);

      // It must not gate the transition: it removes itself on its own.
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.byType(MatchFoundBanner), findsNothing);
    });

    test('the banner copy is localized in Arabic', () {
      final source = File('lib/ui/lang.dart').readAsStringSync();
      expect(source, contains("'Match found!': 'تم العثور على منافس! ⚔️'"));
      expect(
        source,
        contains(
          "'Jump in! Your rival is waiting.': 'ادخل الآن! منافسك بانتظارك.'",
        ),
      );
    });
  });
}
