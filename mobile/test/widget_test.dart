import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/voice_intent_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

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

    test(
      'identifies visual questions and step checks requiring glasses POV',
      () {
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
      },
    );
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

      // No real glasses here, so a check uses the phone camera. Demo
      // answers: tests must not call the deployed backend.
      final camera = FakePhoneCamera(photo: FakePhoneCamera.samplePhoto);
      await tester.pumpWidget(
        CookTogetherApp(
          showInitialWelcome: false,
          phoneCamera: camera,
          assistantService: const MockAssistantService(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Home: one primary action. Simulated glasses stay hidden (#15).
      expect(find.text('CookTogether'), findsOneWidget);
      expect(find.text('Choose a recipe'), findsOneWidget);
      expect(find.text('Glasses not connected'), findsOneWidget);
      expect(find.textContaining('Mock Kit'), findsNothing);

      // 2. Recipes: tapping a recipe opens it directly
      await tester.tap(find.text('Choose a recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Rainbow salad bowl'), findsOneWidget);
      await tester.tap(find.text('Rainbow salad bowl'));
      await tester.pumpAndSettle();

      // 3. Prep: every ingredient is ticked or marked missing first (#31)
      expect(find.text('Get ready'), findsOneWidget);
      expect(
        find.text("Tick each ingredient, or tap Don't have"),
        findsOneWidget,
      );
      await tester.tap(find.text('Mark all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tick each ingredient'), findsNothing);

      // Connecting glasses lives in a sheet, away from the main flow
      await tester.dragUntilVisible(
        find.text('Connect'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Connect my glasses'), findsOneWidget);
      expect(find.text('Test touchpad tap'), findsNothing);
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start cooking'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 4. Opening chat before step 1; everything is ticked, so it only
      // confirms the recipe.
      expect(find.text('Before we start'), findsOneWidget);
      expect(find.textContaining('Everything is ticked'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));

      // 5. Cooking: step panel with Next as the primary action
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Wash & prepare'), findsOneWidget);

      // Open the steps sheet and jump to Step 3 (which has a suggested timer)
      await tester.tap(find.text('All steps'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Build your bowl'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Step 3 of 4'), findsOneWidget);
      await tester.tap(find.text('Start 1 min timer'));
      await tester.pump();
      // The timer runs as a small chip next to the step count.
      expect(find.byTooltip('Dismiss timer'), findsOneWidget);

      // Glasses visual check from the dock
      await tester.tap(find.text('Check'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Looks ready'), findsOneWidget);
      expect(camera.opened, 1);

      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Step 4 of 4'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pump();
      // Step 4 wasn't checked, so Finish asks first.
      expect(find.text('Skip this step without checking?'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // 5. Finish screen & History
      expect(find.text('You made it!'), findsOneWidget);
      expect(find.text('View cooking history'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Cooking history'), findsOneWidget);
      expect(find.text('Rainbow salad bowl'), findsOneWidget);
    },
  );
}
