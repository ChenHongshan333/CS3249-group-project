import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

void main() {
  test('the forced check result is saved with the preferences', () {
    final prefs = UserPreferences.decode(
      const UserPreferences(forcedCheckResult: 'not_yet').encode(),
    );
    expect(prefs.forcedCheckResult, 'not_yet');
    expect(UserPreferences.decode('{}').forcedCheckResult, '');
  });

  testWidgets('Profile → Developer offers the forced result', (tester) async {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.profile,
        assistantService: MockAssistantService(),
      ),
    );
    await tester.pumpAndSettle();
    // Scroll to the end, so Developer is clear of the Save bar.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Developer'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Step check result'), findsOneWidget);
    expect(find.text('Real check (photo + AI)'), findsOneWidget);
  });

  testWidgets('a forced result skips the camera and shows that result', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.preferences': const UserPreferences(
        forcedCheckResult: 'not_yet',
      ).encode(),
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final camera = FakePhoneCamera(photo: FakePhoneCamera.samplePhoto);
    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        phoneCamera: camera,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Check'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Not quite yet'), findsWidgets);
    expect(camera.opened, 0);

    // Let toasts and plugin timeouts finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
