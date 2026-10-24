import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Moves on without a photo check, answering Skip when asked.
Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pump(const Duration(milliseconds: 300));
  if (find.text('Skip').evaluate().isNotEmpty) {
    await tester.tap(find.text('Skip'));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  // #29: the chat is grouped by step, with a divider only where something
  // was said.
  testWidgets('the chat shows a step divider only where something was said', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        assistantService: MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final steps = kStarterRecipes.first.steps;
    // The chat scrolls, so look beyond what's on screen.
    Finder divider(int i) =>
        find.text('Step ${i + 1}: ${steps[i].title}', skipOffstage: false);

    // Opening chat comes before any step, so it has no divider.
    await _say(tester, 'Do I need all of it?');
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(divider(0), findsNothing);

    // A question on step 1 starts its group.
    await _say(tester, 'How small should I tear them?');
    expect(divider(0), findsOneWidget);

    // Nothing said on step 2: no divider.
    await _tapNext(tester);
    await _tapNext(tester);
    expect(find.text('Step 3 of ${steps.length}'), findsOneWidget);
    expect(divider(1), findsNothing);

    await _say(tester, 'How much dressing?');
    expect(divider(2), findsOneWidget);

    // Scrolling back up: step 1's group is still there, and step 2 has none.
    final chat = find.ancestor(
      of: find.text('How much dressing?', skipOffstage: false),
      matching: find.byType(ListView),
    );
    await tester.drag(chat, const Offset(0, 2000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(divider(0), findsOneWidget);
    expect(divider(1), findsNothing);

    // Let toasts and timers finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
