import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the phone recipe mode opens a plain step list', (tester) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.preferences': const UserPreferences(
        serverBaseUrl: '',
        phoneRecipeMode: true,
      ).encode(),
    });
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.recipes,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Egg & spinach wraps'));
    await tester.pump(const Duration(seconds: 1));

    // Every step is on one page, with no Get ready checklist.
    expect(find.text('1. Get everything ready'), findsOneWidget);
    expect(find.text('Amounts are on your ingredient card.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('4. Warm, fill & fold'), 200);
    expect(find.text('4. Warm, fill & fold'), findsOneWidget);

    await tester.tap(find.text('Start cooking'));
    await tester.pump();
    await tester.tap(find.text("I've finished"));
    await tester.pump();
    expect(find.textContaining('Finished in'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the guide pages through and opens again from Help', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CookTogetherApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Meet CookTogether'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }
    expect(find.text('The phone is a backup'), findsOneWidget);
    await tester.tap(find.text("Let's cook"));
    await tester.pump();
    expect(find.text('The phone is a backup'), findsNothing);

    await tester.tap(find.byTooltip('How CookTogether works'));
    await tester.pump();
    expect(find.text('Meet CookTogether'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
