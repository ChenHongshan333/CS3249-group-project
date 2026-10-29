import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  testWidgets('a running timer is a small chip, without a pause button', (
    tester,
  ) async {
    // A narrow phone, so the step row has to fit the chip too.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('All steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Build your bowl'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // On a short screen the step card scrolls.
    await tester.ensureVisible(find.text('Start 1 min timer'));
    await tester.tap(find.text('Start 1 min timer'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('0:5'), findsOneWidget);
    expect(find.byTooltip('Pause timer'), findsNothing);
    expect(find.text('Toss salad gently'), findsNothing);

    // ✕ stops it.
    await tester.ensureVisible(find.byTooltip('Dismiss timer'));
    await tester.tap(find.byTooltip('Dismiss timer'));
    await tester.pump();
    expect(find.byTooltip('Dismiss timer'), findsNothing);

    // Let toasts and plugin timeouts finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('"pause the timer" leaves it running and says how to stop it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('All steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Build your bowl'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Start 1 min timer'));
    await tester.tap(find.text('Start 1 min timer'));
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Type instead'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'pause the timer');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(seconds: 3));

    // Still counting down: 10 s later it has dropped below 0:50.
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('0:4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
