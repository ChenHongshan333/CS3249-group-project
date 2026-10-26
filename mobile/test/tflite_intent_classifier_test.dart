import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/tflite_intent_classifier.dart';
import 'package:mobile/services/voice_intent_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TfliteIntentClassifier & parseAsync tests', () {
    test('classifier handles uninitialized state gracefully', () {
      final classifier = TfliteIntentClassifier.instance;
      // Before initialization or when unavailable, classify returns null
      expect(classifier.isReady, isFalse);
      expect(classifier.classify('next step'), isNull);
    });

    test('parseAsync falls back to rule-based parse when classifier is not ready', () async {
      final intent = await VoiceIntentParser.parseAsync('next step');
      expect(intent.type, VoiceIntentType.nextStep);
      expect(intent.rawText, 'next step');

      final timer = await VoiceIntentParser.parseAsync('set a timer for 5 minutes');
      expect(timer.type, VoiceIntentType.startTimer);
      expect(timer.timerSeconds, 300);

      final visual = await VoiceIntentParser.parseAsync('check this step');
      expect(visual.type, VoiceIntentType.visualCheckStep);
      expect(visual.requiresVision, isTrue);

      final general = await VoiceIntentParser.parseAsync('how much salt should I put?');
      expect(general.type, VoiceIntentType.generalQuestion);
      expect(general.requiresVision, isFalse);

      // Conversational questions with wake words must route to generalQuestion
      final doingRightThing = await VoiceIntentParser.parseAsync(
        'Hey cookie, am I doing the right thing',
      );
      expect(doingRightThing.type, VoiceIntentType.generalQuestion);

      final doingRightThingNoWake = await VoiceIntentParser.parseAsync(
        'am I doing the right thing',
      );
      expect(doingRightThingNoWake.type, VoiceIntentType.generalQuestion);
    });

    test('all 15 major intents are represented in intentExemplars', () {
      final keys = TfliteIntentClassifier.intentExemplars.keys.toSet();
      expect(keys.contains(VoiceIntentType.nextStep), isTrue);
      expect(keys.contains(VoiceIntentType.carryOn), isTrue);
      expect(keys.contains(VoiceIntentType.previousStep), isTrue);
      expect(keys.contains(VoiceIntentType.repeatStep), isTrue);
      expect(keys.contains(VoiceIntentType.openStepsSheet), isTrue);
      expect(keys.contains(VoiceIntentType.startTimer), isTrue);
      expect(keys.contains(VoiceIntentType.pauseTimer), isTrue);
      expect(keys.contains(VoiceIntentType.cancelTimer), isTrue);
      expect(keys.contains(VoiceIntentType.pauseSession), isTrue);
      expect(keys.contains(VoiceIntentType.resumeSession), isTrue);
      expect(keys.contains(VoiceIntentType.muteAudio), isTrue);
      expect(keys.contains(VoiceIntentType.unmuteAudio), isTrue);
      expect(keys.contains(VoiceIntentType.finishCooking), isTrue);
      expect(keys.contains(VoiceIntentType.visualCheckStep), isTrue);
      expect(keys.contains(VoiceIntentType.visualQuestion), isTrue);
      expect(keys.length, 15);
    });
  });
}
