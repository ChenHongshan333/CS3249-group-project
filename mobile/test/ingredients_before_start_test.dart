import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #31: every ingredient is ticked or marked "Don't have" on Get ready, and
// the opening only talks about the missing ones.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.stepHintSeen': true,
    });
  });

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

  Finder row(String label) => find.widgetWithText(CheckRow, label);

  Future<void> dontHave(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: row(label), matching: find.text("Don't have")),
    );
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> startCooking(WidgetTester tester) async {
    await tester.tap(find.text('Start cooking'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('Start cooking waits until every ingredient is decided', (
    tester,
  ) async {
    await openGetReady(tester);
    expect(
      find.text("Tick each ingredient, or tap Don't have"),
      findsOneWidget,
    );

    await startCooking(tester);
    expect(find.text('Get ready'), findsOneWidget);

    await dontHave(tester, 'Chickpeas');
    for (final label in [
      'Mixed greens',
      'Cherry tomatoes',
      'Cucumber',
      'Olive oil',
    ]) {
      await tick(tester, label);
    }
    expect(
      find.descendant(of: row('Chickpeas'), matching: find.text('Missing')),
      findsOneWidget,
    );
    expect(
      find.text("I'll adjust the steps for what you don't have"),
      findsOneWidget,
    );

    await startCooking(tester);
    expect(find.text('Before we start'), findsOneWidget);
    expect(
      find.text(
        "Today we're making Rainbow salad bowl. You don't have the "
        "chickpeas, that's fine. I've adjusted the steps. Say 'let's start' "
        "when you're ready.",
      ),
      findsOneWidget,
    );
    // Only the missing one is listed in the opening.
    expect(row('Chickpeas'), findsOneWidget);
    expect(row('Cucumber'), findsNothing);
    await finish(tester);
  });

  testWidgets('tapping a missing ingredient ticks it', (tester) async {
    await openGetReady(tester);
    await dontHave(tester, 'Cucumber');
    expect(
      find.descendant(of: row('Cucumber'), matching: find.text('Missing')),
      findsOneWidget,
    );

    await tick(tester, 'Cucumber');
    expect(
      find.descendant(of: row('Cucumber'), matching: find.text('Missing')),
      findsNothing,
    );
    expect(tester.widget<CheckRow>(row('Cucumber')).checked, isTrue);
    await finish(tester);
  });

  testWidgets('Mark all ticks the rest but keeps what is missing', (
    tester,
  ) async {
    await openGetReady(tester);
    await dontHave(tester, 'Olive oil');
    await tester.tap(find.text('Mark all'));
    await tester.pump();

    expect(tester.widget<CheckRow>(row('Olive oil')).missing, isTrue);
    expect(tester.widget<CheckRow>(row('Cucumber')).checked, isTrue);
    expect(
      find.text("I'll adjust the steps for what you don't have"),
      findsOneWidget,
    );
    await finish(tester);
  });

  // A swap that needs a missing ingredient is greyed out, but still listed
  // so every participant sees the same swaps.
  Switch swapSwitch(WidgetTester tester, String title) => tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
      matching: find.byType(Switch),
    ),
  );

  testWidgets('a swap that needs a missing ingredient is greyed out', (
    tester,
  ) async {
    await openGetReady(tester);
    expect(swapSwitch(tester, 'Add more chickpeas').onChanged, isNotNull);

    await dontHave(tester, 'Chickpeas');
    expect(swapSwitch(tester, 'Add more chickpeas').onChanged, isNull);
    expect(find.text("Needs chickpeas, which you don't have"), findsOneWidget);
    // Other swaps are unaffected.
    expect(
      swapSwitch(tester, 'Lemon instead of extra oil').onChanged,
      isNotNull,
    );

    // Found it after all.
    await tick(tester, 'Chickpeas');
    expect(swapSwitch(tester, 'Add more chickpeas').onChanged, isNotNull);
    await finish(tester);
  });

  testWidgets('marking an ingredient missing turns off its chosen swap', (
    tester,
  ) async {
    await openGetReady(tester);
    await tester.tap(find.text('Add more chickpeas'));
    await tester.pump();
    expect(swapSwitch(tester, 'Add more chickpeas').value, isTrue);

    await dontHave(tester, 'Chickpeas');
    expect(swapSwitch(tester, 'Add more chickpeas').value, isFalse);
    await finish(tester);
  });

  test("every swap's needs are ingredients of its recipe", () {
    for (final recipe in kStarterRecipes) {
      for (final swap in recipe.swaps) {
        expect(recipe.ingredients, containsAll(swap.needs), reason: swap.id);
      }
    }
  });
}
