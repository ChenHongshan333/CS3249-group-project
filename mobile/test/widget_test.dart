import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/voice_intent_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  group('VoiceIntentParser unit tests', () {
    test('parses step navigation commands accurately', () {
      expect(
        VoiceIntentParser.parse('next step').type,
        equals(VoiceIntentType.nextStep),
      );
      expect(
        VoiceIntentParser.parse('go back').type,
        equals(VoiceIntentType.previousStep),
      );
      expect(
        VoiceIntentParser.parse('repeat that').type,
        equals(VoiceIntentType.repeatStep),
      );
      expect(
        VoiceIntentParser.parse('show all steps').type,
        equals(VoiceIntentType.openStepsSheet),
      );
    });

    test('parses smart contextual timer durations from digits and words', () {
      final fiveMin = VoiceIntentParser.parse('set a timer for 5 minutes');
      expect(fiveMin.type, equals(VoiceIntentType.startTimer));
      expect(fiveMin.timerSeconds, equals(300));

      final wordMin = VoiceIntentParser.parse('start a three minute timer');
      expect(wordMin.type, equals(VoiceIntentType.startTimer));
      expect(wordMin.timerSeconds, equals(180));

      final cancel = VoiceIntentParser.parse('cancel timer');
      expect(cancel.type, equals(VoiceIntentType.cancelTimer));
    });

    test('identifies visual questions and step checks requiring glasses POV', () {
      final checkCmd = VoiceIntentParser.parse('check this step');
      expect(checkCmd.type, equals(VoiceIntentType.visualCheckStep));
      expect(checkCmd.requiresVision, isTrue);

      final visualQuestion = VoiceIntentParser.parse(
        'Does this look chopped small enough?',
      );
      expect(visualQuestion.type, equals(VoiceIntentType.visualQuestion));
      expect(visualQuestion.requiresVision, isTrue);

      final generalQuestion = VoiceIntentParser.parse(
        'What ingredients do I need?',
      );
      expect(generalQuestion.type, equals(VoiceIntentType.generalQuestion));
      expect(generalQuestion.requiresVision, isFalse);
    });
  });

  testWidgets(
    'CookTogether full flow: Home -> Recipes -> Prep (Mock Kit) -> Cooking CUI -> Finish',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const CookTogetherApp(showInitialWelcome: false),
      );
      await tester.pumpAndSettle();

      // 1. Verify CookTogether Home screen & Meta glasses Mock Device Kit card
      expect(find.text('CookTogether'), findsOneWidget);
      expect(find.text('Start cooking'), findsOneWidget);
      expect(find.textContaining('Ray-Ban Meta (Mock Kit)'), findsOneWidget);

      // 2. Navigate to Recipes screen
      await tester.tap(find.text('Start cooking'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a recipe'), findsOneWidget);
      expect(find.text('Rainbow salad bowl'), findsOneWidget);
      expect(find.text('Continue with Rainbow salad bowl'), findsOneWidget);

      // 3. Navigate to Prep & Meta Glasses Check screen
      await tester.tap(find.text('Continue with Rainbow salad bowl'));
      await tester.pumpAndSettle();

      expect(find.text('Prep & Meta glasses check'), findsOneWidget);
      expect(find.text('PAIRED · MOCK KIT'), findsOneWidget);

      // Check off all ingredients to enable Start cooking
      await tester.ensureVisible(find.text('I have my ingredients ready'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I have my ingredients ready'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start cooking'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 4. Verify Refined Cooking Screen
      expect(find.text('STEP 1 OF 4'), findsOneWidget);
      expect(find.text('Wash & prepare'), findsOneWidget);
      expect(find.text('META GLASSES POV'), findsOneWidget);

      // Open Expandable Step & Ingredient Sheet and jump to Step 3 (which has a suggested timer)
      await tester.tap(find.text('Steps & Items'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('RECIPE OVERVIEW'), findsOneWidget);
      await tester.tap(find.text('Build your bowl'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('STEP 3 OF 4'), findsOneWidget);
      expect(
        find.textContaining('Suggested timer: Toss salad gently'),
        findsOneWidget,
      );

      // Start the smart contextual timer
      await tester.tap(find.text('Start timer'));
      await tester.pump();
      expect(find.text('Toss salad gently'), findsOneWidget);

      // Trigger a Meta glasses visual step check from the dock
      await tester.tap(find.text('Check Step'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Inline Vision Assessment Card rendered in conversation stream
      expect(find.text('LOOKS READY'), findsOneWidget);
      expect(find.text('CAPTURED GLASSES VIEW · STEP 3'), findsOneWidget);

      // Advance to Step 4 and finish cooking
      await tester.ensureVisible(
        find.text('Looks good — continue to Step 4'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Looks good — continue to Step 4'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('STEP 4 OF 4'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // 5. Verify Finish screen & History
      expect(find.text('You made it!'), findsOneWidget);
      await tester.tap(find.text('View cooking history'));
      await tester.pumpAndSettle();

      expect(find.text('Cooking history'), findsOneWidget);
      expect(find.text('Rainbow salad bowl'), findsOneWidget);
    },
  );
}
