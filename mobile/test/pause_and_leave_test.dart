import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openStep1(WidgetTester tester) async {
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
  await tester.tap(find.text('Start'));
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('Step 1 of 4'), findsOneWidget);
}

Future<void> _openLeaveQuestion(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Leave session'));
  await tester.pump();
  expect(find.text('Leave this session?'), findsOneWidget);
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

  testWidgets('Pause and leave keeps the session, and Home resumes it', (
    tester,
  ) async {
    await _openStep1(tester);
    await tester.tap(find.text('Next'));
    await tester.pump();
    // Step 1 wasn't checked, so CookTogether asks first.
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await _openLeaveQuestion(tester);
    await tester.tap(find.text('Pause and leave for now'));
    await tester.pump(const Duration(seconds: 1));

    // Home, with the paused session on top.
    expect(find.text('Choose a recipe'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Resume cooking'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Same step, and running again.
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('back while a session is paused is for the screen on top', (
    tester,
  ) async {
    await _openStep1(tester);
    await _openLeaveQuestion(tester);
    await tester.tap(find.text('Pause and leave for now'));
    await tester.pump(const Duration(seconds: 1));

    // The hidden cooking screen must not catch the back gesture.
    await tester.tap(find.text('Recipes'));
    await tester.pump(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resume cooking'), findsOneWidget);

    await tester.tap(find.text('Resume cooking'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Leave this session?'), findsNothing);
    await _finish(tester);
  });

  testWidgets('End session leaves nothing to resume', (tester) async {
    await _openStep1(tester);
    await _openLeaveQuestion(tester);
    await tester.tap(find.text('End session'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Choose a recipe'), findsOneWidget);
    expect(find.text('Resume cooking'), findsNothing);
    await _finish(tester);
  });

  testWidgets('Stay closes the question and keeps cooking', (tester) async {
    await _openStep1(tester);
    await _openLeaveQuestion(tester);
    await tester.tap(find.text('Stay'));
    await tester.pump();

    expect(find.text('Leave this session?'), findsNothing);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await _finish(tester);
  });
}
