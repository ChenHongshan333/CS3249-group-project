import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/step_adapter.dart';

final _salad = kStarterRecipes.firstWhere((r) => r.id == 'salad');
final _rice = kStarterRecipes[2];

void main() {
  // #32: the demo assistant adapts steps without a backend.
  group('StepAdapter', () {
    test('takes an ingredient out of a list', () {
      expect(StepAdapter.leaveOut(_salad, 'cherry tomatoes'), {
        0:
            'Rinse the greens and cucumber. Pat the greens dry before adding '
            'them to a large bowl.',
        1:
            'Slice the cucumber into bite-sized pieces. Keep your fingers '
            'tucked away from the knife.',
      });
    });

    test('keeps the rest of a sentence', () {
      expect(
        StepAdapter.leaveOut(_salad, 'chickpeas')[2],
        'Add the greens and chopped vegetables to the bowl. Toss gently for '
        'a minute.',
      );
      expect(
        StepAdapter.leaveOut(_rice, 'chickpeas')[0],
        'Dice the onion and tomatoes.',
      );
    });

    test('uses a substitute in place of the ingredient', () {
      expect(
        StepAdapter.substitute(_salad, 'cherry tomatoes', 'red pepper')[1],
        startsWith('Cut the red pepper in half'),
      );
    });

    test('leaves steps that never name it alone', () {
      final changes = StepAdapter.leaveOut(_salad, 'olive oil');
      expect(changes.keys, [3]);
    });
  });

  group('the demo assistant in the opening', () {
    const assistant = MockAssistantService();
    final history = <ChatMessage>[];

    Future<AssistantResponse> say(String text) async {
      history.add(
        ChatMessage(
          id: 'u${history.length}',
          sender: MessageSender.user,
          text: text,
          timestamp: DateTime(2026),
        ),
      );
      final response = await assistant.askQuestion(
        sessionId: 's',
        recipe: _salad,
        stepIndex: 0,
        question: text,
        history: history,
        phase: 'opening',
        ingredients: {for (final i in _salad.ingredients) i: false},
      );
      history.add(
        ChatMessage(
          id: 'a${history.length}',
          sender: MessageSender.ai,
          text: response.reply,
          timestamp: DateTime(2026),
        ),
      );
      return response;
    }

    setUp(history.clear);

    test('offers a substitute, then leaves it out when asked', () async {
      final asked = await say("I don't have cherry tomatoes.");
      expect(asked.reply, contains('red pepper'));
      expect(asked.action, isNull);

      final adapted = await say("I'll leave them out.");
      expect(adapted.action?.type, 'adapt_steps');
      expect(adapted.action?.steps.keys, [0, 1]);
      expect(adapted.reply, contains('steps 1 and 2'));
    });

    test('uses the substitute the cook picks', () async {
      await say("I don't have cherry tomatoes.");
      final adapted = await say('Use red pepper instead.');
      expect(adapted.action?.steps[1], startsWith('Cut the red pepper'));
      expect(adapted.reply, contains('use the red pepper'));
    });
  });
}
