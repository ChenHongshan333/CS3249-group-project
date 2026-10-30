import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_voice_channels.dart';

void main() {
  final voice = FakeVoiceChannels();
  setUp(voice.install);
  tearDown(voice.uninstall);

  testWidgets('a step with a timer offers it for the right moment', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      'cooktogether.preferences': const UserPreferences(
        serverBaseUrl: '',
      ).encode(),
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.recipes,
        assistantService: MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Egg & spinach wraps'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Mark all'));
    await tester.pump();
    await tester.tap(find.text('Start cooking'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));

    // Step 1 has no timer, so nothing is offered.
    expect(voice.spoken.where((s) => s.contains("I'll start a")), isEmpty);

    await tester.tap(find.text('All steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cook the eggs'));
    await tester.pump(const Duration(seconds: 1));

    expect(
      voice.spoken.where(
        (s) => s.contains(
          "Tell me when the eggs are in the pan, and I'll start a 2-minute "
          'timer.',
        ),
      ),
      hasLength(1),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
