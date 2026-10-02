import 'package:cloud_hop/ui/cartoon_controls.dart';
import 'package:cloud_hop/main.dart';
import 'package:cloud_hop/services/progress_store.dart';
import 'package:cloud_hop/services/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The UMP channel codec lives under src/ and is not re-exported, so tests
// import it directly to build a matching mock channel.
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The UMP consent API is fire-and-forget inside google_mobile_ads, so a
/// missing native side escapes as an unhandled async error. Stand in for it.
void _mockConsentChannel() {
  const ump = 'plugins.flutter.io/google_mobile_ads/ump';
  // The plugin encodes this channel with UserMessagingCodec, so the mock has
  // to decode with the same codec.
  final channel = MethodChannel(ump, StandardMethodCodec(UserMessagingCodec()));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'ConsentInformation#canRequestAds' => false,
          'ConsentInformation#getConsentStatus' => 1,
          'ConsentInformation#isConsentFormAvailable' => false,
          'UserMessagingPlatform#getPrivacyOptionsRequirementStatus' => 0,
          _ => null,
        };
      });
}

void main() {
  setUp(_mockConsentChannel);

  testWidgets('small phone HUD fits and back returns to home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final store = ProgressStore();
    final progress = await store.load();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton && w.art == artForIcon(Icons.play_arrow_rounded),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton &&
            w.art == artForIcon(Icons.rocket_launch_rounded),
      ),
      findsOneWidget,
    );
    final rocket = tester.getCenter(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton &&
            w.art == artForIcon(Icons.rocket_launch_rounded),
      ),
    );
    final spring = tester.getCenter(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton &&
            w.art == artForIcon(Icons.horizontal_rule_rounded),
      ),
    );
    final life = tester.getCenter(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton && w.art == artForIcon(Icons.favorite_rounded),
      ),
    );
    expect(rocket.dy, spring.dy);
    expect(spring.dy, life.dy);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton && w.art == artForIcon(Icons.arrow_back_rounded),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Create a room & invite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('offline quick challenge starts a labelled bot after the window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'choice': 2,
      'onboardingDone': true,
    });
    final store = ProgressStore();
    final progress = await store.load();
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is CartoonButton && w.art == artForIcon(Icons.play_arrow_rounded),
      ),
    );
    await tester.pump();
    expect(find.text('Finding your challenger…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Finding your challenger…'), findsOneWidget);
    // The search window is a wall-clock deadline (SocialService.matchWindowMs,
    // 8s in findMatch), so the fake test clock cannot expire it. Let real time
    // pass instead.
    await tester.runAsync(
      () => Future<void>.delayed(
        Duration(milliseconds: SocialService.matchWindowMs + 600),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Finding your challenger…'), findsNothing);
    expect(find.textContaining('Goal 100'), findsWidgets);
    expect(find.textContaining(' · BOT'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
