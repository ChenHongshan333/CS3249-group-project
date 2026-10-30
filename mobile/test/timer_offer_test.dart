import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_voice_channels.dart';

/// Answers questions like the demo assistant, and remembers the offer
/// each question carried.
class _RecordingAssistant extends MockAssistantService {
  final List<AssistantAction?> offers = [];

  @override
  Future<AssistantResponse> askQuestion({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required String question,
    required List<ChatMessage> history,
    VisionCapture? visionCapture,
    List<String> acceptedSwaps = const [],
    String phase = 'cooking',
    Map<String, bool> ingredients = const {},
    Map<String, String> substitutes = const {},
    AssistantAction? pendingOffer,
  }) async {
    offers.add(pendingOffer);
    return const AssistantResponse(reply: 'When nothing looks wet.');
  }
}

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

  testWidgets('the timer offer outlasts a question in between', (
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
    final assistant = _RecordingAssistant();
    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.recipes,
        assistantService: assistant,
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
    await tester.tap(find.text('All steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cook the eggs'));
    await tester.pump(const Duration(seconds: 1));

    for (final text in ['how do I know the eggs are done?', "they're in"]) {
      if (find.byType(TextField).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Type instead'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(seconds: 2));
    }

    expect(assistant.offers, hasLength(2));
    expect(assistant.offers.last?.type, 'start_timer');
    expect(assistant.offers.last?.seconds, 120);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
