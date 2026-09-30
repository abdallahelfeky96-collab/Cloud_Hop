import 'package:cloud_hop/main.dart';
import 'package:cloud_hop/services/progress_store.dart';
import 'package:cloud_hop/ui/cartoon_controls.dart';
import 'package:cloud_hop/ui/lang.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every home entry point the player can use besides Play.
const _buttons = <String, IconData>{
  'shop': Icons.shopping_bag_rounded,
  'friends': Icons.people_alt_rounded,
  'profile': Icons.account_circle_rounded,
  'settings': Icons.settings_rounded,
};

void _mockConsentChannel() {
  final channel = MethodChannel(
    'plugins.flutter.io/google_mobile_ads/ump',
    StandardMethodCodec(UserMessagingCodec()),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'ConsentInformation#canRequestAds' => false,
          'ConsentInformation#getConsentStatus' => 1,
          _ => null,
        };
      });
}

Set<String> _texts(WidgetTester tester) => find
    .byType(Text)
    .evaluate()
    .map((e) => '${(e.widget as Text).data ?? ''}')
    .toSet();

/// Taps a home button and reports whether its sheet actually rendered.
Future<bool> _opens(WidgetTester tester, IconData icon) async {
  final button = find.byWidgetPredicate(
    (w) => w is CartoonButton && w.art == artForIcon(icon),
  );
  if (button.evaluate().isEmpty) return false;
  final before = _texts(tester);
  await tester.tap(button.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final opened = _texts(tester).difference(before).isNotEmpty;
  expect(
    tester.takeException(),
    isNull,
    reason: 'opening a sheet must not throw',
  );
  if (opened) {
    await tester.tapAt(const Offset(195, 25));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
  }
  return opened;
}

Future<void> _boot(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'onboardingDone': true});
  final store = ProgressStore();
  final progress = await store.load();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(CloudHop(store: store, progress: progress));
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

Future<void> _setLanguage(WidgetTester tester, String code) async {
  appLang.value = code;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(_mockConsentChannel);

  for (final code in ['en', 'ar']) {
    testWidgets('home sheets open in $code', (tester) async {
      appLang.value = code;
      await _boot(tester);
      for (final entry in _buttons.entries) {
        expect(
          await _opens(tester, entry.value),
          isTrue,
          reason: '${entry.key} must open in $code',
        );
      }
    });
  }

  testWidgets('home sheets keep working after switching to Arabic', (
    tester,
  ) async {
    appLang.value = 'en';
    await _boot(tester);
    await _setLanguage(tester, 'ar');
    for (final entry in _buttons.entries) {
      expect(
        await _opens(tester, entry.value),
        isTrue,
        reason: '${entry.key} must open after switching to Arabic',
      );
    }
  });

  testWidgets('home sheets keep working after switching back to English', (
    tester,
  ) async {
    appLang.value = 'ar';
    await _boot(tester);
    await _setLanguage(tester, 'en');
    for (final entry in _buttons.entries) {
      expect(
        await _opens(tester, entry.value),
        isTrue,
        reason: '${entry.key} must open after switching back to English',
      );
    }
  });
}
