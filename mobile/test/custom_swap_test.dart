import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replies from a script and records what the app logged.
class _ScriptedAssistant implements AssistantService {
  final List<AssistantResponse> replies;
  final List<(String, Map<String, dynamic>)> logged = [];

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
  }) async => replies.removeAt(0);

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
  }) async => logged.add((type, data));
}

const _lessOil = 'Dress with a teaspoon of olive oil and a squeeze of lemon.';

// #22: the cook's own healthier swap, judged by CookAlong and logged apart
// from the fixed swaps.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
  });

  group('custom_swap from the backend', () {
    test('is read with its verdict and steps', () {
      final action = AssistantAction.fromJson({
        'type': 'custom_swap',
        'swap': ' Lemon instead of some oil ',
        'healthier': true,
        'fits': true,
        'steps': [
          {'step': 3, 'text': _lessOil},
        ],
      });
      expect(action?.type, 'custom_swap');
      expect(action?.swap, 'Lemon instead of some oil');
      expect(action?.healthier, isTrue);
      expect(action?.fits, isTrue);
      expect(action?.steps, {3: const StepEdit(text: _lessOil)});
    });

    for (final missing in ['swap', 'healthier', 'fits']) {
      test('without $missing is ignored', () {
        final json = <String, dynamic>{
          'type': 'custom_swap',
          'swap': 'Lemon instead of some oil',
          'healthier': true,
          'fits': true,
        }..remove(missing);
        expect(AssistantAction.fromJson(json), isNull);
      });
    }
  });

  Future<_ScriptedAssistant> suggest(
    WidgetTester tester,
    AssistantResponse reply,
  ) async {
    final assistant = _ScriptedAssistant([reply]);
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
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Type instead'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byType(TextField),
      'Could I use lemon and less oil?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    return assistant;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a healthier swap that fits changes the steps', (tester) async {
    const reason =
        "Yes, that's lighter and still fresh. I've adjusted the steps.";
    final assistant = await suggest(
      tester,
      const AssistantResponse(
        reply: reason,
        action: AssistantAction(
          'custom_swap',
          swap: 'Lemon instead of some oil',
          healthier: true,
          fits: true,
          steps: {3: StepEdit(text: _lessOil)},
        ),
      ),
    );

    expect(
      find.textContaining('Changed for you:', skipOffstage: false),
      findsOneWidget,
    );
    expect(assistant.logged.map((e) => e.$1), isNot(contains('swap')));
    final (_, data) = assistant.logged.singleWhere(
      (e) => e.$1 == 'custom_swap',
    );
    expect(data, {
      'swap': 'Lemon instead of some oil',
      'healthier': true,
      'fits': true,
      'applied': true,
      'reason': reason,
    });
    await finish(tester);
  });

  testWidgets('a swap that is not healthier changes nothing but is logged', (
    tester,
  ) async {
    final assistant = await suggest(
      tester,
      const AssistantResponse(
        reply: "Mayo would add a lot of fat, so I'd keep the olive oil.",
        action: AssistantAction(
          'custom_swap',
          swap: 'Mayo instead of olive oil',
          healthier: false,
          fits: true,
          // Ignored: it isn't healthier.
          steps: {3: StepEdit(text: 'Dress with mayo.')},
        ),
      ),
    );

    expect(
      find.textContaining('Changed for you:', skipOffstage: false),
      findsNothing,
    );
    final (_, data) = assistant.logged.singleWhere(
      (e) => e.$1 == 'custom_swap',
    );
    expect(data['applied'], isFalse);
    expect(data['healthier'], isFalse);
    await finish(tester);
  });
}
