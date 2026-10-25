import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/missing_options.dart';
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

  // #94: the demo never says "that's fine" without changing the steps.
  group('the demo assistant in the opening', () {
    const assistant = MockAssistantService();

    Future<AssistantResponse> say(
      String text, {
      Recipe? recipe,
      Set<String> missing = const {},
    }) {
      final r = recipe ?? _rice;
      return assistant.askQuestion(
        sessionId: 's',
        recipe: r,
        stepIndex: 0,
        question: text,
        history: const [],
        phase: 'opening',
        ingredients: {for (final i in r.ingredients) i: !missing.contains(i)},
      );
    }

    test('leaves out an ingredient the cook says they lack, the written '
        'way', () async {
      final adapted = await say("Oh, I don't have any onions.");
      expect(adapted.action?.type, 'adapt_steps');
      expect(adapted.action?.steps, waysWithout(_rice, 'onion').first.steps);
      expect(adapted.reply, contains("I've adjusted the steps"));
      expect(adapted.reply, isNot(contains('step 1')));
    });

    test('falls back to the rule-based rewrite on changed steps', () async {
      final changed = StepAdapter.forChoices(_rice, {
        'tomatoes': waysWithout(_rice, 'tomatoes').first,
      }).recipe;
      final adapted = await say(
        "I don't have the onion.",
        recipe: changed,
        missing: {'tomatoes'},
      );
      expect(
        adapted.action?.steps[0],
        const StepEdit(text: 'Rinse and drain the chickpeas.'),
      );
    });

    test('does not ask again about what was decided on Get ready', () async {
      final reply = await say("I don't have tomatoes.", missing: {'tomatoes'});
      expect(reply.action, isNull);
      expect(reply.reply, contains('already adjusted the steps'));
    });
  });
}
