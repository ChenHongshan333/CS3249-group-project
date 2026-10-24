import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openCooking(WidgetTester tester) async {
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

Future<void> _finish(WidgetTester tester) async {
  // Let toasts and plugin timeouts finish before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('without glasses, the top bar offers to reconnect them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
    await _openCooking(tester);

    expect(find.byTooltip('Reconnect your glasses'), findsOneWidget);
    final icon = tester.widget<GlassesIcon>(find.byType(GlassesIcon));
    expect(icon.connected, isFalse);
    await _finish(tester);
  });

  testWidgets('with simulated glasses, the top bar takes a photo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.preferences': const UserPreferences(
        simulatedGlassesPhotos: true,
      ).encode(),
    });
    await _openCooking(tester);

    expect(find.byTooltip('Take a photo with your glasses'), findsOneWidget);
    final icon = tester.widget<GlassesIcon>(find.byType(GlassesIcon));
    expect(icon.connected, isTrue);
    await _finish(tester);
  });
}
