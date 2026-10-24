import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_phone_camera.dart';

/// The user's own glasses, connected, taking [photo].
class _ConnectedGlasses extends MetaWearablesDatGlassesService {
  int photos = 0;

  @override
  bool get usingRealGlasses => true;

  @override
  GlassesConnectionState get connectionState =>
      GlassesConnectionState.connectedHardware;

  @override
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  }) async {
    photos++;
    return VisionCapture(
      id: 'dish',
      recipeId: recipe.id,
      stepIndex: stepIndex,
      source: 'glasses',
      deviceName: 'Ray-Ban Meta',
      sceneDescription: '',
      recipeIcon: recipe.icon,
      recipeTone: recipe.tone,
      jpegBytes: FakePhoneCamera.pngPhoto,
      base64Jpeg: base64Encode(FakePhoneCamera.pngPhoto),
      capturedAt: DateTime(2026, 10, 24),
    );
  }
}

const _meal = CookingHistoryItem(
  id: 'h1',
  recipeId: 'salad',
  recipeName: 'Rainbow salad bowl',
  recipeIcon: '🥗',
  date: '24 Oct 2026',
  durationSeconds: 1260,
  stepsCompleted: 4,
  visualChecksCount: 2,
);

void main() {
  /// Opens the Finish screen for [_meal], the meal just cooked.
  Future<void> openFinish(
    WidgetTester tester, {
    required FakePhoneCamera camera,
    GlassesService? glasses,
    Map<String, Object> saved = const {},
    AppScreen screen = AppScreen.finish,
  }) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.history': CookingHistoryItem.encodeList([_meal]),
      ...saved,
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CookTogetherApp(
        initialScreen: screen,
        glassesService: glasses,
        phoneCamera: camera,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder historyPhoto() => find.bySemanticsLabel('Photo of Rainbow salad bowl');

  // #24
  testWidgets('without glasses, the dish photo comes from the phone and is '
      'kept in History', (tester) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.pngPhoto);
    await openFinish(tester, camera: camera);

    await tester.tap(find.text('Take a photo of your dish'));
    await tester.pumpAndSettle();
    // No choice to make without glasses.
    expect(find.text('With my glasses'), findsNothing);
    expect(camera.opened, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Retake photo'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('cooktogether.photo.h1'),
      base64Encode(FakePhoneCamera.pngPhoto),
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(historyPhoto(), findsOneWidget);
  });

  testWidgets('with glasses, the user picks the camera', (tester) async {
    final camera = FakePhoneCamera(photo: FakePhoneCamera.pngPhoto);
    final glasses = _ConnectedGlasses();
    await openFinish(tester, camera: camera, glasses: glasses);

    await tester.tap(find.text('Take a photo of your dish'));
    await tester.pumpAndSettle();
    expect(find.text('With my phone'), findsOneWidget);
    await tester.tap(find.text('With my glasses'));
    await tester.pumpAndSettle();

    expect(glasses.photos, 1);
    expect(camera.opened, 0);
    expect(find.text('Retake photo'), findsOneWidget);
  });

  testWidgets('closing the camera saves nothing', (tester) async {
    final camera = FakePhoneCamera();
    await openFinish(tester, camera: camera);

    await tester.tap(find.text('Take a photo of your dish'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo of your dish'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cooktogether.photo.h1'), isNull);
  });

  testWidgets('a saved dish photo shows in History after a restart', (
    tester,
  ) async {
    await openFinish(
      tester,
      camera: FakePhoneCamera(),
      screen: AppScreen.history,
      saved: {'cooktogether.photo.h1': base64Encode(FakePhoneCamera.pngPhoto)},
    );
    expect(historyPhoto(), findsOneWidget);
  });
}
