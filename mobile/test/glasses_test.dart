import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Glasses whose camera always fails, like real glasses that are folded.
class _BrokenCameraGlasses extends MetaWearablesDatGlassesService {
  @override
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  }) async {
    throw const GlassesCaptureException('Unfold your glasses to take a photo.');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  // flutter test has no native plugin, like the web build.
  test(
    'start falls back to the Mock Device Kit without native glasses',
    () async {
      final glasses = MetaWearablesDatGlassesService();
      await glasses.start();
      expect(glasses.usingRealGlasses, isFalse);
      expect(glasses.isConnected, isTrue);
      expect(glasses.deviceName, contains('Mock Kit'));
    },
  );

  test('connecting real glasses without the native plugin says why', () async {
    final glasses = MetaWearablesDatGlassesService();
    expect(await glasses.connectRealGlasses(), isFalse);
    expect(glasses.usingRealGlasses, isFalse);
    expect(glasses.connectionState, GlassesConnectionState.disconnected);
    expect(glasses.lastStatusNote, contains('Android or iPhone app'));
  });

  testWidgets('a failed glasses photo is explained, not sent to the AI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        glassesService: _BrokenCameraGlasses(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Check is off during the opening chat; start step 1 first.
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Check'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Unfold your glasses to take a photo.'), findsOneWidget);
    expect(find.text('Looks ready'), findsNothing);

    // Let the toast and plugin timeouts finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
