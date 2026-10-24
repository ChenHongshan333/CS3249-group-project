import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    AppScreen initialScreen = AppScreen.home,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: initialScreen,
        assistantService: const MockAssistantService(),
      ),
    );
    // The cooking screen's clock keeps ticking, so it never settles.
    if (initialScreen == AppScreen.cook) {
      await tester.pump(const Duration(seconds: 1));
    } else {
      await tester.pumpAndSettle();
    }
  }

  /// The Android back gesture or button.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('back from Recipes goes to Home, not out of the app', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Choose a recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Rainbow salad bowl'), findsOneWidget);

    await systemBack(tester);
    expect(find.text('Choose a recipe'), findsOneWidget);
  });

  testWidgets('back from Get ready goes to the screen it was opened from', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Choose a recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rainbow salad bowl'));
    await tester.pumpAndSettle();
    expect(find.text('Get ready'), findsOneWidget);

    await systemBack(tester);
    expect(find.text('Rainbow salad bowl'), findsOneWidget);
    expect(find.text('Get ready'), findsNothing);
  });

  testWidgets('Back from Get ready after "Cook again" goes to Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.history': CookingHistoryItem.encodeList(const [
        CookingHistoryItem(
          id: 'hist-1',
          recipeId: 'salad',
          recipeName: 'Rainbow salad bowl',
          recipeIcon: '🥗',
          date: '1 Oct 2026',
          durationSeconds: 600,
          stepsCompleted: 4,
          visualChecksCount: 1,
        ),
      ]),
    });
    await pumpApp(tester);
    await tester.tap(find.text('Rainbow salad bowl'));
    await tester.pumpAndSettle();
    expect(find.text('Get ready'), findsOneWidget);

    // The in-app Back button and the system back go to the same place.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a recipe'), findsOneWidget);

    await tester.tap(find.text('Rainbow salad bowl'));
    await tester.pumpAndSettle();
    await systemBack(tester);
    expect(find.text('Choose a recipe'), findsOneWidget);
  });

  testWidgets('back while cooking asks first; back again stays', (
    tester,
  ) async {
    await pumpApp(tester, initialScreen: AppScreen.cook);
    expect(find.text('Leave this session?'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Leave this session?'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Leave this session?'), findsNothing);
    expect(find.text('Before we start'), findsOneWidget);

    // Let toasts and plugin timeouts finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
