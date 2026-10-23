import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation.dart';
import '../models/recipe.dart';

/// Response returned by [AssistantService] for a conversational or visual turn.
class AssistantResponse {
  final String reply;
  final VisualCheckStatus? visualStatus;
  final VisionCapture? visionCapture;

  const AssistantResponse({
    required this.reply,
    this.visualStatus,
    this.visionCapture,
  });
}

/// Pluggable interface for communicating with the LLM & Vision backend
/// (`docs/api.md` web protocols) or the local context-aware mock assistant.
abstract class AssistantService {
  Future<AssistantResponse> askQuestion({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required String question,
    required List<ChatMessage> history,
    VisionCapture? visionCapture,
    List<String> acceptedSwaps = const [],
  });

  Future<AssistantResponse> checkStepWithVision({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required VisionCapture visionCapture,
    String? userQuestion,
  });

  Future<void> logEvent({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  });
}

/// Smart context-aware local implementation of [AssistantService] that
/// processes step instructions, cooking tips, and Meta glasses POV snapshots.
class MockAssistantService implements AssistantService {
  const MockAssistantService();

  @override
  Future<AssistantResponse> askQuestion({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required String question,
    required List<ChatMessage> history,
    VisionCapture? visionCapture,
    List<String> acceptedSwaps = const [],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final step = recipe.steps[stepIndex.clamp(0, recipe.steps.length - 1)];
    final lower = question.toLowerCase();

    // If a Meta glasses snapshot was captured alongside a visual question:
    if (visionCapture != null) {
      return _evaluateVisualQuestion(
        recipe: recipe,
        step: step,
        stepIndex: stepIndex,
        question: question,
        capture: visionCapture,
      );
    }

    if (RegExp(r'allerg|substitut|replace|swap|instead').hasMatch(lower)) {
      return const AssistantResponse(
        reply:
            'I cannot verify that a substitute is safe for an allergy. Please check the ingredient label directly—we can pause while you check.',
      );
    }

    if (RegExp(r'small|size|bite-sized|thin|thick|dice|slice|cut').hasMatch(lower)) {
      return AssistantResponse(
        reply:
            'Aim for pieces about 1 to 2 cm wide so they are easy to eat. ${step.tip} Say "does this look right?" if you want me to look through your Meta glasses.',
      );
    }

    if (RegExp(r'how long|minutes|time|when is it done').hasMatch(lower)) {
      final durationHint = step.suggestedTimerSeconds != null
          ? 'This step takes about ${(step.suggestedTimerSeconds! / 60).ceil()} minutes. You can say "set a timer" anytime.'
          : step.check;
      return AssistantResponse(
        reply: '$durationHint ${step.tip}',
      );
    }

    if (RegExp(r'ingredient|what do i need|how much').hasMatch(lower)) {
      return AssistantResponse(
        reply:
            'For ${recipe.name}, we use ${recipe.ingredients.join(", ")}. Right now on Step ${stepIndex + 1}: ${step.instruction}',
      );
    }

    return AssistantResponse(
      reply:
          'Good question! ${step.tip} When you are ready, ${step.instruction} You can also ask me to look through your glasses to check your progress.',
    );
  }

  @override
  Future<AssistantResponse> checkStepWithVision({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required VisionCapture visionCapture,
    String? userQuestion,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final step = recipe.steps[stepIndex.clamp(0, recipe.steps.length - 1)];
    return _evaluateVisualQuestion(
      recipe: recipe,
      step: step,
      stepIndex: stepIndex,
      question: userQuestion ?? 'Check this step',
      capture: visionCapture,
    );
  }

  AssistantResponse _evaluateVisualQuestion({
    required Recipe recipe,
    required RecipeStep step,
    required int stepIndex,
    required String question,
    required VisionCapture capture,
  }) {
    final lower = question.toLowerCase();

    VisualCheckStatus status = VisualCheckStatus.done;
    String reply;

    if (lower.contains('blurry') || lower.contains('dark') || lower.contains('unsure')) {
      status = VisualCheckStatus.unsure;
      reply =
          'The view from your glasses is a bit angled. Try tilting your head slightly toward the counter and ask me to check again.';
    } else if (lower.contains('not yet') || lower.contains('raw') || lower.contains('too big')) {
      status = VisualCheckStatus.notYet;
      reply =
          'Looking through your glasses at the ${step.visionSceneDescription.toLowerCase()}: a few pieces still need a little more work. ${step.tip}';
    } else if (lower.contains('small enough') || lower.contains('chop') || lower.contains('slice')) {
      status = VisualCheckStatus.done;
      reply =
          'Looking through your Meta glasses: ${step.check} The pieces look even and bite-sized. Ready to move on whenever you are!';
    } else {
      status = VisualCheckStatus.done;
      reply =
          'I can see your ${step.visionSceneDescription.toLowerCase()}. ${step.check} Remember to verify heat and doneness yourself before moving to the next step.';
    }

    final updatedCapture = capture.copyWith(status: status);
    return AssistantResponse(
      reply: reply,
      visualStatus: status,
      visionCapture: updatedCapture,
    );
  }

  @override
  Future<void> logEvent({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    // No-op in local mock mode.
  }
}

/// Web protocol client implementing `POST /ask`, `POST /check-step`, and `POST /log`
/// from `docs/api.md`, with automatic fallback to [MockAssistantService] when
/// the server URL is not configured or unreachable.
class HttpAssistantService implements AssistantService {
  final String Function() baseUrlProvider;
  http.Client? _client;
  final MockAssistantService fallback;

  HttpAssistantService({
    required this.baseUrlProvider,
    http.Client? client,
    this.fallback = const MockAssistantService(),
  }) {
    _client = client;
  }

  http.Client get _httpClient => _client ??= http.Client();

  String get _cleanBaseUrl => baseUrlProvider().trim().replaceAll(RegExp(r'/+$'), '');

  @override
  Future<AssistantResponse> askQuestion({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required String question,
    required List<ChatMessage> history,
    VisionCapture? visionCapture,
    List<String> acceptedSwaps = const [],
  }) async {
    // If a visual snapshot is attached, route through `/check-step` or hybrid vision flow
    if (visionCapture != null && _cleanBaseUrl.isNotEmpty) {
      return checkStepWithVision(
        sessionId: sessionId,
        recipe: recipe,
        stepIndex: stepIndex,
        visionCapture: visionCapture,
        userQuestion: question,
      );
    }

    if (_cleanBaseUrl.isEmpty) {
      return fallback.askQuestion(
        sessionId: sessionId,
        recipe: recipe,
        stepIndex: stepIndex,
        question: question,
        history: history,
        visionCapture: visionCapture,
      );
    }

    try {
      final recentTurns = history
          .where((m) => m.sender == MessageSender.ai || m.sender == MessageSender.user)
          .take(6)
          .map(
            (m) => {
              'from': m.sender == MessageSender.ai ? 'assistant' : 'user',
              'text': m.text,
            },
          )
          .toList();

      final response = await _httpClient
          .post(
            Uri.parse('$_cleanBaseUrl/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionId': sessionId,
              'recipeId': recipe.id,
              'recipeName': recipe.name,
              'step': stepIndex,
              'stepText': recipe.steps[stepIndex].instruction,
              'nextStepTitle': stepIndex + 1 < recipe.steps.length
                  ? recipe.steps[stepIndex + 1].title
                  : '',
              'question': question,
              'acceptedSwaps': acceptedSwaps,
              'history': recentTurns,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = data['reply'] as String?;
        if (reply != null && reply.isNotEmpty) {
          return AssistantResponse(reply: reply);
        }
      }
    } catch (_) {
      // Fall back cleanly when backend is offline
    }

    return fallback.askQuestion(
      sessionId: sessionId,
      recipe: recipe,
      stepIndex: stepIndex,
      question: question,
      history: history,
      visionCapture: visionCapture,
    );
  }

  @override
  Future<AssistantResponse> checkStepWithVision({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required VisionCapture visionCapture,
    String? userQuestion,
  }) async {
    if (_cleanBaseUrl.isEmpty) {
      return fallback.checkStepWithVision(
        sessionId: sessionId,
        recipe: recipe,
        stepIndex: stepIndex,
        visionCapture: visionCapture,
        userQuestion: userQuestion,
      );
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_cleanBaseUrl/check-step'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionId': sessionId,
              'recipeId': recipe.id,
              'step': stepIndex,
              'stepText': recipe.steps[stepIndex].instruction,
              'doneLooksLike': recipe.steps[stepIndex].check,
              'image': visionCapture.base64Jpeg,
              'source': visionCapture.source,
              'question': ?userQuestion,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = VisualCheckStatus.fromWire(data['status'] as String?);
        final say = data['say'] as String? ?? recipe.steps[stepIndex].check;
        final updatedCapture = visionCapture.copyWith(status: status);
        return AssistantResponse(
          reply: say,
          visualStatus: status,
          visionCapture: updatedCapture,
        );
      }
    } catch (_) {
      // Fall back to local mock vision evaluation when server is unreachable
    }

    return fallback.checkStepWithVision(
      sessionId: sessionId,
      recipe: recipe,
      stepIndex: stepIndex,
      visionCapture: visionCapture,
      userQuestion: userQuestion,
    );
  }

  @override
  Future<void> logEvent({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    if (_cleanBaseUrl.isEmpty) return;
    try {
      await _httpClient
          .post(
            Uri.parse('$_cleanBaseUrl/log'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionId': sessionId,
              'type': type,
              'time': DateTime.now().toIso8601String(),
              'data': data,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
