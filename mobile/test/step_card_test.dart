import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hint = 'Your step stays here while the chat scrolls below.';

void main() {
  Future<void> openCooking(WidgetTester tester, {bool hintSeen = false}) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      if (hintSeen) 'cooktogether.stepHintSeen': true,
    });
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
  }

  Color panelColor(WidgetTester tester) {
    final panel = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('step-panel')),
    );
    return (panel.decoration! as BoxDecoration).color!;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  // #18
  testWidgets('the step panel flashes when the step changes', (tester) async {
    await openCooking(tester, hintSeen: true);
    expect(panelColor(tester), CookTogetherTheme.surface);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(panelColor(tester), CookTogetherTheme.warningSoft);
    await tester.pump(const Duration(seconds: 2));
    expect(panelColor(tester), CookTogetherTheme.surface);
    await finish(tester);
  });

  testWidgets('first use shows a one-time hint; Got it hides it for good', (
    tester,
  ) async {
    await openCooking(tester);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_hint), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text(_hint), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cooktogether.stepHintSeen'), isTrue);
    await finish(tester);
  });

  testWidgets('the hint goes away by itself after step 1', (tester) async {
    await openCooking(tester);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Next'));
    await tester.pump();
    // Step 1 wasn't checked, so CookTogether asks first.
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text(_hint), findsNothing);
    await finish(tester);
  });

  testWidgets('no hint once it was seen', (tester) async {
    await openCooking(tester, hintSeen: true);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_hint), findsNothing);
    await finish(tester);
  });
}
