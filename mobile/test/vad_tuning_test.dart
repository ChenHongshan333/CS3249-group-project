import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/screens/vad_tuning_sheet.dart';
import 'package:mobile/services/voice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VAD Tuning & Preferences', () {
    test('UserPreferences default VAD parameters', () {
      const prefs = UserPreferences();
      expect(prefs.vadFixedFloor, 0.012);
      expect(prefs.vadNoiseMultiplier, 2.2);

      final decoded = UserPreferences.decode('{}');
      expect(decoded.vadFixedFloor, 0.012);
      expect(decoded.vadNoiseMultiplier, 2.2);
    });

    test('UserPreferences encodes and decodes custom VAD parameters', () {
      const custom = UserPreferences(
        vadFixedFloor: 0.007,
        vadNoiseMultiplier: 1.8,
      );
      final json = custom.encode();
      final decoded = UserPreferences.decode(json);

      expect(decoded.vadFixedFloor, 0.007);
      expect(decoded.vadNoiseMultiplier, 1.8);
    });

    test('VoiceController updates and resets VAD tuning', () {
      final controller = VoiceController();
      expect(controller.vadFixedFloor, 0.012);
      expect(controller.vadNoiseMultiplier, 2.2);

      var notified = false;
      controller.addListener(() => notified = true);

      controller.setVadTuning(fixedFloor: 0.006, noiseMultiplier: 1.6);
      expect(controller.vadFixedFloor, 0.006);
      expect(controller.vadNoiseMultiplier, 1.6);
      expect(notified, isTrue);

      notified = false;
      controller.resetVadTuning();
      expect(controller.vadFixedFloor, 0.012);
      expect(controller.vadNoiseMultiplier, 2.2);
      expect(notified, isTrue);
    });

    testWidgets('VadTuningSheet renders and updates VAD parameters', (
      tester,
    ) async {
      final controller = VoiceController();
      var prefs = const UserPreferences();
      UserPreferences? savedPrefs;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VadTuningSheet(
              voiceController: controller,
              preferences: prefs,
              onSavePreferences: (updated) => savedPrefs = updated,
            ),
          ),
        ),
      );

      expect(find.text('Voice Detection Tuning'), findsOneWidget);
      expect(find.text('Fixed Energy Floor'), findsOneWidget);
      expect(find.text('Adaptive Noise Multiplier'), findsOneWidget);
      expect(find.text('0.012'), findsOneWidget);
      expect(find.text('2.2x'), findsOneWidget);

      // Tap the Sensitive preset
      await tester.tap(find.text('Sensitive / Whisper (0.006 / 1.6x)'));
      await tester.pumpAndSettle();

      expect(controller.vadFixedFloor, 0.006);
      expect(controller.vadNoiseMultiplier, 1.6);
      expect(savedPrefs?.vadFixedFloor, 0.006);
      expect(savedPrefs?.vadNoiseMultiplier, 1.6);
      expect(find.text('0.006'), findsOneWidget);
      expect(find.text('1.6x'), findsOneWidget);

      // Tap Reset
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(controller.vadFixedFloor, 0.012);
      expect(controller.vadNoiseMultiplier, 2.2);
      expect(savedPrefs?.vadFixedFloor, 0.012);
      expect(savedPrefs?.vadNoiseMultiplier, 2.2);
    });
  });
}
