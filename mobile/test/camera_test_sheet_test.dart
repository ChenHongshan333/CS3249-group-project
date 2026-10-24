import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

/// Real glasses whose camera always fails, like glasses that are folded.
class _FoldedGlasses extends MetaWearablesDatGlassesService {
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

  Future<void> testCamera(
    WidgetTester tester, {
    required FakePhoneCamera camera,
    GlassesService? glasses,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CookTogetherApp(
        initialScreen: AppScreen.prep,
        glassesService: glasses,
        phoneCamera: camera,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Scroll to the end, so the button is clear of the bottom bar.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Test camera'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  // #17
  testWidgets('without glasses, the camera test shows a phone photo', (
    tester,
  ) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.pngPhoto);
    await testCamera(tester, camera: camera);

    expect(camera.opened, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('from your phone camera'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Camera test'), findsNothing);
    await finish(tester);
  });

  testWidgets('closing the phone camera says no photo was taken', (
    tester,
  ) async {
    final camera = FakePhoneCamera();
    await testCamera(tester, camera: camera);

    expect(find.text('No photo taken.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(camera.opened, 2);
    await finish(tester);
  });

  testWidgets('a glasses camera problem is explained before cooking', (
    tester,
  ) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.pngPhoto);
    await testCamera(tester, camera: camera, glasses: _FoldedGlasses());

    expect(
      find.textContaining('Unfold your glasses to take a photo.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('use your phone camera instead'),
      findsOneWidget,
    );
    expect(camera.opened, 0);
    await finish(tester);
  });
}
