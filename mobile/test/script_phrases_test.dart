import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/voice_intent_parser.dart';

// #23: the conversation script's phrases work as commands, with no wake
// phrase. Lines the AI should handle stay questions.
void main() {
  group('script lines during cooking', () {
    const expected = {
      'Okay, next step please.': VoiceIntentType.nextStep,
      'Next step.': VoiceIntentType.nextStep,
      'All right, we can continue.': VoiceIntentType.carryOn,
      'Continue': VoiceIntentType.carryOn,
      'Check this, please.': VoiceIntentType.visualCheckStep,
      "Can you have a look? I'm worried I'm burning it.":
          VoiceIntentType.visualQuestion,
      "I've cut into the thickest part. Can you see the middle?":
          VoiceIntentType.visualQuestion,
      'Okay, it looks good.': VoiceIntentType.visualQuestion,
      'Okay, repeat that.': VoiceIntentType.repeatStep,
      // For the AI: questions, answers and implicit progress.
      'How fine does the garlic need to be?': VoiceIntentType.generalQuestion,
      'Okay, I can do that.': VoiceIntentType.generalQuestion,
      'Those are ready. What about the chicken?':
          VoiceIntentType.generalQuestion,
      "Okay, the oil's moving around now.": VoiceIntentType.generalQuestion,
      "The water's boiling.": VoiceIntentType.generalQuestion,
      'Yes, start it now.': VoiceIntentType.generalQuestion,
      'Please.': VoiceIntentType.generalQuestion,
      "So you can check how it looks, but you can't tell me for sure?":
          VoiceIntentType.generalQuestion,
      "Sure, I'm a cheese fan for real.": VoiceIntentType.generalQuestion,
    };
    for (final MapEntry(key: line, value: type) in expected.entries) {
      test(line, () => expect(VoiceIntentParser.parse(line).type, type));
    }
  });

  group('script lines in the opening chat', () {
    const ready = [
      "I've got everything.",
      'I’ve got everything',
      "Okay, let's start.",
      'All set!',
      'Got everything',
    ];
    const notReady = [
      'Hi CookAlong, could you help me make dinner?',
      'Some chicken thighs, pasta, cherry tomatoes, and a jar of tomato sauce.',
      'Yes, and some cheese.',
      "I have wholemeal. Let's use that.",
      "I don't really know where to start.",
    ];
    for (final line in ready) {
      test('starts: $line', () {
        expect(VoiceIntentParser.isReadyToStart(line), isTrue);
      });
    }
    for (final line in notReady) {
      test('does not start: $line', () {
        expect(VoiceIntentParser.isReadyToStart(line), isFalse);
      });
    }
  });
}
