import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replies from a script and records the step text the app sent.
class _ScriptedAssistant implements AssistantService {
  final List<AssistantResponse> replies;
  final List<String> stepTexts = [];

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
    AssistantAction? pendingOffer,
  }) async {
    stepTexts.add(recipe.steps[stepIndex].instruction);
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
  }) async {}
}

const _noTomatoes = 'Rinse the greens and cucumber. Pat the greens dry.';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  // #32
  group('adapt_steps from the backend', () {
    test('is read with its changed steps', () {
      final action = AssistantAction.fromJson({
        'type': 'adapt_steps',
        'steps': [
          {'step': 0, 'text': _noTomatoes},
          {'step': 'x', 'text': 'ignored'},
        ],
      });
      expect(action?.type, 'adapt_steps');
      expect(action?.steps, {0: _noTomatoes});
    });

    test('without changes is ignored', () {
      expect(
        AssistantAction.fromJson({'type': 'adapt_steps', 'steps': []}),
        isNull,
      );
    });

    test('the opening sends every step, and cooking does not', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = HttpAssistantService(
        baseUrlProvider: () => 'https://backend.test',
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'reply': 'Okay.'}), 200);
        }),
      );
      final recipe = kStarterRecipes.first;
      for (final phase in ['opening', 'cooking']) {
        await service.askQuestion(
          sessionId: 's',
          recipe: recipe,
          stepIndex: 0,
          question: 'I have no tomatoes.',
          history: const [],
          phase: phase,
        );
      }
      final steps = bodies[0]['steps'] as List;
      expect(steps, hasLength(recipe.steps.length));
      expect(steps.first, {
        'title': recipe.steps.first.title,
        'text': recipe.steps.first.instruction,
      });
      expect(bodies[1].containsKey('steps'), isFalse);
    });
  });

  testWidgets('adapted steps show in the chat, on the step, and in later '
      'questions', (tester) async {
    final assistant = _ScriptedAssistant([
      const AssistantResponse(
        reply: "No problem. I've changed step 1 to leave them out.",
        action: AssistantAction('adapt_steps', steps: {0: _noTomatoes}),
      ),
      const AssistantResponse(reply: 'Pat them gently.'),
    ]);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        assistantService: assistant,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    Future<void> say(String text) async {
      if (find.byType(TextField).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Type instead'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await say("I'll leave the tomatoes out.");
    expect(
      find.textContaining('Changed for you:', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Step 1, Wash & prepare: $_noTomatoes',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_noTomatoes), findsOneWidget);
    expect(find.text('Changed for your ingredients'), findsOneWidget);

    // Answers while cooking are about the adapted step.
    await say('How dry should they be?');
    expect(assistant.stepTexts.last, _noTomatoes);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
