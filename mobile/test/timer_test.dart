import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/voice_intent_parser.dart';

VoiceIntentType _type(String text) => VoiceIntentParser.parse(text).type;

void main() {
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
}
