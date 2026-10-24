import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #19: Check is off before step 1 and while paused; a tap says why.
void main() {
  Future<void> openCooking(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.stepHintSeen': true,
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        assistantService: MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('tapping Check before step 1 says when it works', (tester) async {
    await openCooking(tester);
    await tester.tap(find.text('Check'));
    await tester.pump();

    expect(find.text('Check works once you start step 1.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tapping Check while paused says to resume', (tester) async {
    await openCooking(tester);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Check'));
    await tester.pump();

    expect(find.text('Resume the session first.'), findsOneWidget);
    await finish(tester);
  });
}
