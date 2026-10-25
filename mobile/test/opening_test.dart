import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replies from a script and records what the app sent.
class _ScriptedAssistant implements AssistantService {
  final List<AssistantResponse> replies;
  final List<Map<String, Object?>> asked = [];
  final List<String> logged = [];
  Completer<AssistantResponse>? pendingReply;

  _ScriptedAssistant(this.replies);

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
    asked.add({
      'question': question,
      'phase': phase,
      'ingredients': ingredients,
      'pendingOffer': pendingOffer?.toJson(),
    });
    if (pendingReply != null) return pendingReply!.future;
    return replies.removeAt(0);
  }

  @override
  Future<AssistantResponse> checkStepWithVision({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required VisionCapture visionCapture,
    String? userQuestion,
  }) async => const AssistantResponse(reply: 'Looks fine.');

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> logEvent({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) async => logged.add(type);
}

class _LiveVoice extends VoiceController {
  String transcript = '';

  @override
  String get partialTranscript => transcript;

  void hear(String words) {
    transcript = words;
    notifyListeners();
  }

  void send() {
    final words = transcript;
    hear('');
    onFinalUtterance?.call(words);
  }

  @override
  Future<void> speak(String text, {required bool voiceGuidanceEnabled}) async {
    setActivityState(VoiceActivityState.idle);
  }
}

Future<void> _openCooking(
  WidgetTester tester,
  AssistantService assistant, {
  VoiceController? voiceController,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CookTogetherApp(
      showInitialWelcome: false,
      initialScreen: AppScreen.cook,
      assistantService: assistant,
      voiceController: voiceController,
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _say(WidgetTester tester, String text) async {
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('More'));
    // The menu's animation starts on the next frame; let it finish.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Type instead'));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  // Reply, then the scroll that brings it into view.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _finish(WidgetTester tester) async {
  // Let toasts and plugin timeouts finish before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  testWidgets('live speech grows in chat and becomes one message while waiting', (
    tester,
  ) async {
    final voice = _LiveVoice();
    addTearDown(voice.dispose);
    final assistant = _ScriptedAssistant([])
      ..pendingReply = Completer<AssistantResponse>();
    await _openCooking(tester, assistant, voiceController: voice);

    voice.hear('Can I replace');
    await tester.pump();
    expect(find.text('Can I replace'), findsOneWidget);
    expect(assistant.asked, isEmpty);

    const words =
        'Can I replace the cucumber with another vegetable that I '
        'already have in my kitchen, and should I use the same amount?';
    voice.hear(words);
    await tester.pump();
    expect(find.text('Can I replace'), findsNothing);
    final liveText = tester.widget<Text>(find.text(words));
    expect(liveText.maxLines, isNull);
    expect(liveText.overflow, isNot(TextOverflow.ellipsis));

    voice.send();
    await tester.pump();
    expect(find.text(words), findsOneWidget);
    expect(find.byKey(const ValueKey('live-transcript')), findsNothing);
    // The chat scrolls, so look beyond what's on screen.
    expect(
      find.byKey(const ValueKey('chat-thinking'), skipOffstage: false),
      findsOneWidget,
    );
    expect(assistant.asked.single['question'], words);

    assistant.pendingReply!.complete(
      const AssistantResponse(reply: 'You can use chopped bell pepper.'),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('chat-thinking'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.text('You can use chopped bell pepper.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text(words, skipOffstage: false), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('opening asks about unticked ingredients, then starts', (
    tester,
  ) async {
    final assistant = _ScriptedAssistant([
      const AssistantResponse(
        reply: 'Great. What about the chickpeas?',
        action: AssistantAction('tick_ingredient', name: 'cucumber'),
      ),
      const AssistantResponse(
        reply: "Lovely, let's start.",
        action: AssistantAction('start_cooking'),
      ),
    ]);
    await _openCooking(tester, assistant);

    // Nothing was ticked on Get ready, so every ingredient is listed.
    expect(find.text('Before we start'), findsOneWidget);
    expect(find.text("You don't have"), findsOneWidget);
    expect(find.text('Cucumber'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await _say(tester, "I've got the cucumber.");
    expect(assistant.asked.last['phase'], 'opening');
    expect((assistant.asked.last['ingredients'] as Map)['cucumber'], isFalse);
    expect(find.text('Great. What about the chickpeas?'), findsOneWidget);

    await _say(tester, 'That is everything I need.');
    // The second request already sees cucumber as ticked.
    expect((assistant.asked.last['ingredients'] as Map)['cucumber'], isTrue);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(assistant.logged, contains('opening_end'));
    await _finish(tester);
  });

  testWidgets('saying "let\'s start" begins step 1 without the backend', (
    tester,
  ) async {
    final assistant = _ScriptedAssistant([]);
    await _openCooking(tester, assistant);
    await _say(tester, "Let's start.");
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(assistant.asked, isEmpty);
    await _finish(tester);
  });

  for (final phrase in [
    'I have everything.',
    "That's everything!",
    'Got it all.',
    'Yes.',
    'I’m ready.',
  ]) {
    testWidgets('opening readiness "$phrase" starts without the backend', (
      tester,
    ) async {
      final assistant = _ScriptedAssistant([]);
      await _openCooking(tester, assistant);
      await _say(tester, phrase);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(assistant.asked, isEmpty);
      await _finish(tester);
    });
  }

  for (final phrase in [
    'I have everything except garlic.',
    "Yes, but I'm not ready.",
  ]) {
    testWidgets('opening qualification "$phrase" still goes to the assistant', (
      tester,
    ) async {
      final assistant = _ScriptedAssistant([
        const AssistantResponse(reply: "Say 'let's start' when you're ready."),
      ]);
      await _openCooking(tester, assistant);
      await _say(tester, phrase);
      expect(find.text('Before we start'), findsOneWidget);
      expect(assistant.asked.single['question'], phrase);
      await _finish(tester);
    });
  }

  testWidgets('an offer is sent back once and its action runs', (tester) async {
    const timer = AssistantAction('start_timer', seconds: 60, label: 'Toss');
    final assistant = _ScriptedAssistant([
      const AssistantResponse(
        reply: 'Would you like a one-minute timer?',
        offer: timer,
      ),
      const AssistantResponse(
        reply: 'One-minute timer started.',
        action: timer,
      ),
      const AssistantResponse(reply: 'Sure.'),
    ]);
    await _openCooking(tester, assistant);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));

    await _say(tester, 'What should I watch for?');
    expect(assistant.asked.last['phase'], 'cooking');
    expect(assistant.asked.last['pendingOffer'], isNull);

    await _say(tester, 'Please.');
    expect(assistant.asked.last['pendingOffer'], timer.toJson());
    expect(find.text('Toss'), findsOneWidget);

    // The offer is sent only once.
    await _say(tester, 'Thanks.');
    expect(assistant.asked.last['pendingOffer'], isNull);
    await _finish(tester);
  });

  testWidgets('a photo check drops an unanswered offer', (tester) async {
    final assistant = _ScriptedAssistant([
      const AssistantResponse(
        reply: 'Would you like a two-minute timer?',
        offer: AssistantAction('start_timer', seconds: 120, label: 'Pasta'),
      ),
      const AssistantResponse(reply: 'Enjoy the cheese.'),
    ]);
    await _openCooking(tester, assistant);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));

    await _say(tester, 'The pasta is still firm.');
    await tester.tap(find.text('Check'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    // "Sure" is about the photo reply, not the earlier timer.
    await _say(tester, "Sure, I'm a cheese fan.");
    expect(assistant.asked.last['pendingOffer'], isNull);
    await _finish(tester);
  });

  testWidgets('the built-in demo assistant handles the opening too', (
    tester,
  ) async {
    await _openCooking(tester, const MockAssistantService());
    await _say(tester, "I've got the cucumber.");
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('What about the'), findsOneWidget);
    await _finish(tester);
  });

  test('tick_ingredient reads every name', () {
    final action = AssistantAction.fromJson({
      'type': 'tick_ingredient',
      'name': 'garlic',
      'names': ['garlic', 'cucumber'],
    });
    expect(action?.names, ['garlic', 'cucumber']);
  });

  test('unknown action types are ignored', () {
    expect(AssistantAction.fromJson({'type': 'order_pizza'}), isNull);
    expect(AssistantAction.fromJson({'type': 'start_timer'}), isNull);
    expect(AssistantAction.fromJson({'type': 'next_step'})?.type, 'next_step');
  });
}
