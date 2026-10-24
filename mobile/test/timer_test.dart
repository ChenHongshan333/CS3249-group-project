import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/voice_intent_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

VoiceIntentType _type(String text) => VoiceIntentParser.parse(text).type;

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

/// Opens the salad on step 3, which has a 1-minute "Toss salad gently" timer.
Future<void> _openStepThree(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const CookTogetherApp(
      showInitialWelcome: false,
      initialScreen: AppScreen.cook,
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('Start'));
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('All steps'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Build your bowl'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('Step 3 of 4'), findsOneWidget);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  group('timer commands (#34)', () {
    test('a question that mentions a timer goes to the AI', () {
      expect(
        _type(
          'What do I do if my noodles get a bit sticky before the timer '
          'hits 3 minutes?',
        ),
        VoiceIntentType.generalQuestion,
      );
      expect(
        _type('Should I start the timer now'),
        isNot(VoiceIntentType.startTimer),
      );
      expect(_type('the timer went off'), VoiceIntentType.generalQuestion);
    });

    test('clear commands and requests still start a timer', () {
      for (final text in [
        'set a timer for 3 minutes',
        "let's start the timer",
        'start timer',
        '3 minute timer',
        'timer for five minutes',
        'can you set a timer for 2 minutes?',
        'please put on a timer',
      ]) {
        expect(_type(text), VoiceIntentType.startTimer, reason: text);
      }
      expect(
        VoiceIntentParser.parse('set a timer for 3 minutes').timerSeconds,
        180,
      );
    });

    test('"stop the timer" cancels it; "pause the timer" pauses it', () {
      expect(_type('stop the timer'), VoiceIntentType.cancelTimer);
      expect(_type('cancel the timer'), VoiceIntentType.cancelTimer);
      expect(_type('pause the timer'), VoiceIntentType.pauseTimer);
    });
  });

  group('one timer per step (#35)', () {
    testWidgets('a voice timer hides the start button and never duplicates', (
      tester,
    ) async {
      await _openStepThree(tester);
      expect(find.text('Start 1 min timer'), findsOneWidget);

      await _say(tester, 'set a timer for 2 minutes');
      expect(find.text('Start 1 min timer'), findsNothing);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.textContaining('1:5'), findsOneWidget);

      await _say(tester, 'set a timer for 3 minutes');
      // Replaced, not added: still one timer, now counting down from 3:00.
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.textContaining('2:5'), findsOneWidget);
      expect(find.textContaining('1:5'), findsNothing);
      await _finish(tester);
    });

    testWidgets('"stop the timer" ends it and brings the button back', (
      tester,
    ) async {
      await _openStepThree(tester);
      await tester.tap(find.text('Start 1 min timer'));
      await tester.pump();
      expect(find.text('1:00'), findsOneWidget);

      await _say(tester, 'stop the timer');
      expect(find.text('1:00'), findsNothing);
      expect(find.text('Start 1 min timer'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('saying the step is done ends its timer quietly', (
      tester,
    ) async {
      await _openStepThree(tester);
      await tester.tap(find.text('Start 1 min timer'));
      await tester.pump();

      await _say(tester, "it's done");
      expect(find.text('1:00'), findsNothing);
      // Well past the minute: no "finished" announcement.
      await tester.pump(const Duration(seconds: 70));
      expect(find.textContaining('timer just finished'), findsNothing);
      await _finish(tester);
    });

    testWidgets('moving to the next step ends the timer', (tester) async {
      await _openStepThree(tester);
      await tester.tap(find.text('Start 1 min timer'));
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pump();
      // Not checked, so Next asks first (#20).
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      await _finish(tester);
    });
  });
}
