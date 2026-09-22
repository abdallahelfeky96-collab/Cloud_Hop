import 'package:cloud_hop/main.dart';
import 'package:cloud_hop/services/progress_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('small phone HUD fits and back returns to home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ProgressStore();
    final progress = await store.load();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
    final rocket = tester.getCenter(find.byIcon(Icons.rocket_launch_rounded));
    final spring = tester.getCenter(find.byIcon(Icons.horizontal_rule_rounded));
    final life = tester.getCenter(find.byIcon(Icons.favorite_rounded));
    expect(rocket.dy, spring.dy);
    expect(spring.dy, life.dy);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Create a room & invite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('offline quick challenge starts a labelled bot at five seconds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'choice': 2});
    final store = ProgressStore();
    final progress = await store.load();
    await tester.pumpWidget(CloudHop(store: store, progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('Finding your challenger…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Finding your challenger…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Finding your challenger…'), findsNothing);
    expect(find.textContaining('BOT'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
