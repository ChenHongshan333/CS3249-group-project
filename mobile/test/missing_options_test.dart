import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/missing_options.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/step_adapter.dart';
import 'package:mobile/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rice = kStarterRecipes.firstWhere((r) => r.id == 'rice');

/// How a step may name [ingredient]: "cherry tomatoes", "tomatoes",
/// "tomato".
RegExp _naming(String ingredient) {
  final last = ingredient.split(' ').last;
  final names = {
    ingredient,
    last,
    if (last.endsWith('oes')) last.substring(0, last.length - 2),
    if (last.endsWith('s')) last.substring(0, last.length - 1),
  };
  return RegExp(
    '\\b(${names.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );
}

/// Everything about a step that is shown or spoken.
List<String> _said(RecipeStep step) => [
  step.title,
  step.instruction,
  step.tip,
  step.check,
  ?step.suggestedTimerLabel,
];

void main() {
  // #98: the ways to manage without each ingredient, written by hand.
  group('the hand-written options', () {
    for (final recipe in kStarterRecipes) {
      for (final ingredient in recipe.ingredients) {
        test('${recipe.id} without $ingredient', () {
          final options = waysWithout(recipe, ingredient);
          expect(options.first.leavesOut, isTrue);
          expect(options.where((o) => o.leavesOut), hasLength(1));
          expect(
            options.map((o) => o.label).toSet(),
            hasLength(options.length),
          );

          for (final option in options) {
            expect(option.steps, isNotEmpty, reason: option.label);
            for (final i in option.steps.keys) {
              expect(i, inInclusiveRange(0, recipe.steps.length - 1));
            }
            final adapted = StepAdapter.forChoices(recipe, {
              ingredient: option,
            });
            expect(adapted.recipe.steps, isNotEmpty);
            final said = [
              for (final step in adapted.recipe.steps) ..._said(step),
            ].join('\n');
            // Nothing still names it, except the substitute's own name
            // ("tomato paste").
            final withoutUse = option.use == null
                ? said
                : said.replaceAll(
                    RegExp(RegExp.escape(option.use!), caseSensitive: false),
                    '',
                  );
            expect(
              _naming(ingredient).hasMatch(withoutUse),
              isFalse,
              reason: '${option.label}:\n$said',
            );
            if (option.use case final use?) {
              expect(said.toLowerCase(), contains(use));
            }
            expect(said, isNot(matches(RegExp(r'boil\w*\s+(the\s+)?oil'))));
          }
        });
      }
    }
  });

  group('StepAdapter.forChoices', () {
    test('removes a step with nothing left to do (#94)', () {
      final adapted = StepAdapter.forChoices(_rice, {
        'onion': waysWithout(_rice, 'onion').first,
      });
      expect(adapted.recipe.steps, hasLength(3));
      expect(adapted.removed, ['Soften the onion']);
      expect(adapted.changed, {0, 1});
      // Warming the oil moved into the next step, which kept its timer.
      expect(
        adapted.recipe.steps[1].instruction,
        startsWith('Warm a little oil over medium heat. Add the tomatoes'),
      );
      expect(adapted.recipe.steps[1].suggestedTimerSeconds, 240);
      expect(adapted.moved, {0: 0, 2: 1, 3: 2});
    });

    test('a step changed for two ingredients uses the rewrite for the '
        'second', () {
      final adapted = StepAdapter.forChoices(_rice, {
        'tomatoes': waysWithout(_rice, 'tomatoes').first,
        'onion': waysWithout(_rice, 'onion').first,
      });
      expect(
        adapted.recipe.steps.first.instruction,
        'Rinse and drain the chickpeas.',
      );
      for (final step in adapted.recipe.steps) {
        expect(step.instruction, isNot(contains('onion')));
        expect(step.instruction, isNot(contains('tomato')));
      }
    });

    test('a timer can change or go', () {
      final noodles = kStarterRecipes.firstWhere((r) => r.id == 'noodles');
      final spaghetti = StepAdapter.forChoices(noodles, {
        'noodles': waysWithout(noodles, 'noodles')[1],
      }).recipe;
      expect(spaghetti.steps[1].suggestedTimerSeconds, 540);
      expect(spaghetti.steps[1].suggestedTimerLabel, 'Boil spaghetti');

      final noRice = StepAdapter.forChoices(_rice, {
        'cooked rice': waysWithout(_rice, 'cooked rice').first,
      }).recipe;
      expect(noRice.steps.last.suggestedTimerSeconds, isNull);
      expect(noRice.steps.last.suggestedTimerLabel, isNull);
    });

    test('never removes every step', () {
      final adapted = StepAdapter.apply(_rice, {
        for (var i = 0; i < _rice.steps.length; i++) i: const StepEdit.remove(),
      });
      expect(adapted.recipe.steps, hasLength(_rice.steps.length));
      expect(adapted.removed, isEmpty);
    });
  });

  test('adapt_steps from the backend can change a title and check, or '
      'remove a step', () {
    final action = AssistantAction.fromJson({
      'type': 'adapt_steps',
      'steps': [
        {'step': 0, 'text': 'Dice the tomatoes.', 'check': 'Diced.'},
        {'step': 1, 'remove': true},
        {'step': 2, 'title': 'No text'},
      ],
    });
    expect(action?.steps, {
      0: const StepEdit(text: 'Dice the tomatoes.', check: 'Diced.'),
      1: const StepEdit.remove(),
    });
    expect(action?.toJson()['steps'], [
      {'step': 0, 'text': 'Dice the tomatoes.', 'check': 'Diced.'},
      {'step': 1, 'remove': true},
    ]);
  });

  group('Get ready to the opening', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'cooktogether.seen': true,
        'cooktogether.stepHintSeen': true,
      });
    });

    Finder row(String label) => find.widgetWithText(CheckRow, label);

    Future<void> openGetReady(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const CookTogetherApp(
          initialScreen: AppScreen.prep,
          assistantService: MockAssistantService(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> missingTomatoesAndStart(
      WidgetTester tester, {
      String? choose,
    }) async {
      await tester.tap(
        find.descendant(
          of: row('Cherry tomatoes'),
          matching: find.text("Don't have"),
        ),
      );
      await tester.pump();
      if (choose != null) {
        await tester.tap(find.text(choose));
        await tester.pump();
      }
      await tester.tap(find.text('Mark all'));
      await tester.pump();
      await tester.tap(find.text('Start cooking'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    ChoiceChip chip(WidgetTester tester, String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    testWidgets('a missing ingredient offers substitutes, leaving it out by '
        'default', (tester) async {
      await openGetReady(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(
        find.descendant(of: row('Cucumber'), matching: find.text("Don't have")),
      );
      await tester.pump();
      expect(chip(tester, 'Leave it out').selected, isTrue);
      expect(chip(tester, 'Use celery').selected, isFalse);

      await tester.tap(find.text('Use celery'));
      await tester.pump();
      expect(chip(tester, 'Use celery').selected, isTrue);
      expect(chip(tester, 'Leave it out').selected, isFalse);

      // Found it after all.
      await tester.tap(find.text('Cucumber'));
      await tester.pump();
      expect(find.byType(ChoiceChip), findsNothing);
      await finish(tester);
    });

    testWidgets('the opening sums up a substitute and waits for "let\'s '
        'start"', (tester) async {
      await openGetReady(tester);
      await missingTomatoesAndStart(tester, choose: 'Use red pepper');

      expect(
        find.text(
          "Today we're making Rainbow salad bowl. You're using red pepper "
          "instead of the cherry tomatoes. I've adjusted the steps. Say "
          "'let's start' when you're ready.",
        ),
        findsOneWidget,
      );
      expect(find.text('Using red pepper'), findsOneWidget);
      expect(
        find.textContaining('Changed for you:', skipOffstage: false),
        findsOneWidget,
      );
      // Still before step 1.
      expect(find.text('Before we start'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
          'Rinse the greens, red pepper and cucumber. Pat the greens dry '
          'before adding them to a large bowl.',
        ),
        findsOneWidget,
      );
      expect(find.text('Changed for your ingredients'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('leaving it out says so, and ticking it in the opening puts '
        'the steps back', (tester) async {
      await openGetReady(tester);
      await missingTomatoesAndStart(tester);

      expect(
        find.text(
          "Today we're making Rainbow salad bowl. You don't have the cherry "
          "tomatoes, that's fine. I've adjusted the steps. Say 'let's "
          "start' when you're ready.",
        ),
        findsOneWidget,
      );
      expect(find.text('Leaving it out'), findsOneWidget);

      await tester.tap(find.text('Cherry tomatoes'));
      await tester.pump();
      expect(
        find.text('Back to the steps as written.', skipOffstage: false),
        findsOneWidget,
      );
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(kStarterRecipes.first.steps.first.instruction),
        findsOneWidget,
      );
      await finish(tester);
    });
  });
}
