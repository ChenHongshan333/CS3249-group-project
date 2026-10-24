import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/camera/phone_camera.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

/// Real glasses whose camera always fails, like glasses that are folded.
class _BrokenCameraGlasses extends MetaWearablesDatGlassesService {
  @override
  bool get usingRealGlasses => true;

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

  Future<void> openStepOne(
    WidgetTester tester, {
    required GlassesService glasses,
    required FakePhoneCamera camera,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        glassesService: glasses,
        phoneCamera: camera,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Check is off during the opening chat; start step 1 first.
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.text('Check'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finish(WidgetTester tester) async {
    // Let the toast and plugin timeouts finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a failed glasses photo falls back to the phone camera', (
    tester,
  ) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.samplePhoto);
    await openStepOne(tester, glasses: _BrokenCameraGlasses(), camera: camera);

    await tapCheck(tester);

    expect(
      // The chat scrolls, so look beyond what's on screen.
      find.text(
        "Unfold your glasses to take a photo. Let's use your phone camera instead.",
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(camera.opened, 1);
    expect(find.text('Looks ready'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('without real glasses, a check uses the phone camera', (
    tester,
  ) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.samplePhoto);
    await openStepOne(
      tester,
      glasses: MetaWearablesDatGlassesService(),
      camera: camera,
    );

    await tapCheck(tester);

    expect(camera.opened, 1);
    expect(find.text('Looks ready'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('closing the phone camera sends nothing to the AI', (
    tester,
  ) async {
    final camera = FakePhoneCamera();
    await openStepOne(
      tester,
      glasses: MetaWearablesDatGlassesService(),
      camera: camera,
    );

    await tapCheck(tester);

    expect(camera.opened, 1);
    expect(find.textContaining('No photo taken.'), findsOneWidget);
    expect(find.text('Looks ready'), findsNothing);
    await finish(tester);
  });

  testWidgets('a phone camera error is explained, not sent to the AI', (
    tester,
  ) async {
    final camera = FakePhoneCamera(
      error: const PhoneCameraException('The phone camera could not open.'),
    );
    await openStepOne(
      tester,
      glasses: MetaWearablesDatGlassesService(),
      camera: camera,
    );

    await tapCheck(tester);

    expect(find.text('The phone camera could not open.'), findsOneWidget);
    expect(find.text('Looks ready'), findsNothing);
    await finish(tester);
  });
}
