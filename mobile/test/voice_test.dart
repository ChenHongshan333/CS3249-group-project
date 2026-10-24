import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const audioRouteChannel = MethodChannel('cooktogether/audio_route');

  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
    // Speech recognition reports it can't start, as on a phone where
    // microphone permission was denied.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, (call) async {
          if (call.method == 'initialize') return false;
          return null;
        });
    // No Bluetooth headset: the phone's own mic stays in use.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioRouteChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioRouteChannel, null);
  });

  testWidgets(
    'tapping the mic without speech recognition explains, never sends a phrase',
    (tester) async {
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

      await tester.tap(find.bySemanticsLabel('Talk to CookTogether'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining("I can't use the microphone"), findsOneWidget);
      // The old demo fallback sent "Let's start." and began step 1.
      expect(find.text("Let's start."), findsNothing);
      expect(find.text('Step 1 of 4'), findsNothing);

      // Let the toast timer finish before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
