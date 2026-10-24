import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

const _question = 'Skip this step without checking?';

Future<void> _openStep1(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CookTogetherApp(
      showInitialWelcome: false,
      initialScreen: AppScreen.cook,
      phoneCamera: FakePhoneCamera(photo: FakePhoneCamera.samplePhoto),
      assistantService: const MockAssistantService(),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('Start'));
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('Step 1 of 4'), findsOneWidget);
}

Future<void> _say(WidgetTester tester, String text) async {
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Type instead'));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _finish(WidgetTester tester) async {
  // Let toasts and plugin timeouts finish before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  testWidgets('Next on an unchecked step asks, and Skip moves on', (
    tester,
  ) async {
    await _openStep1(tester);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text(_question), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_question), findsNothing);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('Check first takes a photo, then Next moves on without asking', (
    tester,
  ) async {
    await _openStep1(tester);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Check first'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text(_question), findsNothing);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_question), findsNothing);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('saying "next step" asks too, and "skip" answers it', (
    tester,
  ) async {
    await _openStep1(tester);
    await _say(tester, 'next step');
    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining("You haven't checked this step"), findsWidgets);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await _say(tester, 'skip');
    expect(find.text(_question), findsNothing);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await _finish(tester);
  });
}
