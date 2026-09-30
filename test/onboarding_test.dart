import 'package:cloud_hop/main.dart';
import 'package:cloud_hop/services/progress_store.dart';
import 'package:cloud_hop/ui/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first run walks through onboarding and finishes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          prefs: prefs,
          onDone: () => done = true,
        ),
      ),
    );
    Future<void> settleOn(String text) async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text(text).evaluate().isNotEmpty) return;
      }
      fail('never settled on "$text"');
    }

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Welcome to Cloud Hop'), findsOneWidget);
    // Language comes first, then controls, then character.
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Choose how to play'), findsNothing);

    // Pick Arabic on page one; labels switch immediately.
    await tester.tap(
      find.ancestor(
        of: find.text('العربية'),
        matching: find.byType(ListTile),
      ),
    );
    await settleOn('اختر لغتك');
    await tester.tap(find.text('التالي'));
    // Controls page follows, already in Arabic.
    await settleOn('اختر طريقة اللعب');
    expect(find.text('اختر لغتك'), findsNothing);
    await tester.tap(find.text('التالي'));
    await settleOn('اختر شخصيتك');
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow_rounded));
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, isTrue);
    expect(prefs.getBool('onboardingDone'), isTrue);
    expect(prefs.getString('language'), 'ar');
  });

  testWidgets('CloudHop gates home behind first-run onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ProgressStore();
    final progress = await store.load();
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Cloud Hop'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('CloudHop skips onboarding when already completed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final store = ProgressStore();
    final progress = await store.load();
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
