import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation.dart';
import '../models/recipe.dart';

/// Response returned by [AssistantService] for a conversational or visual turn.
class AssistantResponse {
  final String reply;
  final VisualCheckStatus? visualStatus;
  final VisionCapture? visionCapture;

  /// Something the reply proposes ("Would you like a timer?"). Send it back
  /// as `pendingOffer` with the next question.
  final AssistantAction? offer;

  /// Something to do now, because the user accepted an offer.
  final AssistantAction? action;

  /// The backend couldn't answer; [reply] says so and is safe to speak.
  final bool isError;

  const AssistantResponse({
    required this.reply,
    this.visualStatus,
    this.visionCapture,
    this.offer,
    this.action,
    this.isError = false,
  });
}

/// An offer or action from `/ask` (docs/api.md). Unknown types are ignored.
class AssistantAction {
  static const knownTypes = {
    'start_timer',
    'next_step',
    'repeat_step',
    'start_cooking',
    'tick_ingredient',
  };

  final String type;
  final int? seconds;
  final String? label;
  final String? name;

  /// For `tick_ingredient`: every ingredient to tick. Older backends send
  /// only [name].
  final List<String> names;

  const AssistantAction(
    this.type, {
    this.seconds,
    this.label,
    this.name,
    this.names = const [],
  });

  static AssistantAction? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    if (type is! String || !knownTypes.contains(type)) return null;
    final seconds = (json['seconds'] as num?)?.toInt();
    if (type == 'start_timer' && (seconds == null || seconds < 1)) return null;
    return AssistantAction(
      type,
      seconds: seconds,
      label: json['label'] as String?,
      name: json['name'] as String?,
      names: [
        for (final n in json['names'] as List? ?? const []) ?(n as String?),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'seconds': ?seconds,
    'label': ?label,
    'name': ?name,
    if (names.isNotEmpty) 'names': names,
  };
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
    String phase = 'cooking',
    Map<String, bool> ingredients = const {},
    AssistantAction? pendingOffer,
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

  /// Wakes the backend ahead of time. A free Render instance sleeps after
  /// 15 idle minutes and takes up to a minute to wake, far longer than the
  /// app waits for an answer. Never throws.
  Future<void> warmUp();
}

/// Smart context-aware local implementation of [AssistantService] that
/// processes step instructions, cooking tips, and Meta glasses POV snapshots.
class MockAssistantService implements AssistantService {
  const MockAssistantService();

  @override
  Future<void> warmUp() async {}

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
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final step = recipe.steps[stepIndex.clamp(0, recipe.steps.length - 1)];
    final lower = question.toLowerCase();

    if (phase == 'opening') return _openingReply(lower, ingredients);

    if (pendingOffer != null) {
      if (_isYes(lower)) {
        return AssistantResponse(
          reply: pendingOffer.type == 'start_timer'
              ? '${(pendingOffer.seconds! / 60).ceil()}-minute timer started.'
              : 'Okay.',
          action: pendingOffer,
        );
      }
      if (_isNo(lower)) return const AssistantResponse(reply: 'No problem.');
    }

    final timerSeconds = step.suggestedTimerSeconds;
    if (timerSeconds != null &&
        RegExp(r'how long|how many minutes|time').hasMatch(lower)) {
      final mins = (timerSeconds / 60).ceil();
      return AssistantResponse(
        reply: 'About $mins minutes. Would you like a $mins-minute timer?',
        offer: AssistantAction(
          'start_timer',
          seconds: timerSeconds,
          label: step.suggestedTimerLabel ?? step.title,
        ),
      );
    }

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

  static bool _isYes(String lower) => RegExp(
    r"^(yes|yeah|yep|sure|please|ok|okay|go ahead|do it|start it)\b",
  ).hasMatch(lower.trim());

  static bool _isNo(String lower) =>
      RegExp(r"^(no|nope|not now|no thanks)\b").hasMatch(lower.trim());

  AssistantResponse _openingReply(
    String lower,
    Map<String, bool> ingredients,
  ) {
    if (RegExp(
      r"let'?s (start|go|cook)|ready|that'?s everything|all set",
    ).hasMatch(lower)) {
      return const AssistantResponse(
        reply: "Lovely, let's start.",
        action: AssistantAction('start_cooking'),
      );
    }
    final missing = ingredients.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();
    final mentioned = missing.where((name) => lower.contains(name)).toList();
    if (mentioned.isNotEmpty &&
        RegExp(r"don'?t have|no |out of|missing").hasMatch(lower)) {
      return AssistantResponse(
        reply:
            "No problem, it still works without the ${mentioned.first}. "
            "Say 'let's start' when you're ready.",
      );
    }
    if (mentioned.isNotEmpty) {
      final left = missing.where((n) => n != mentioned.first).toList();
      return AssistantResponse(
        reply: left.isEmpty
            ? "Great, that's everything. Say 'let's start' when you're ready."
            : 'Great. What about the ${left.first}?',
        action: AssistantAction('tick_ingredient', name: mentioned.first),
      );
    }
    return const AssistantResponse(
      reply: "Okay. Say 'let's start' when you're ready.",
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
/// from `docs/api.md`.
///
/// With no backend URL it uses [MockAssistantService] (demo mode). With a
/// URL, a failure is reported as a spoken error, never replaced by a demo
/// answer that would look real.
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

  // The wording follows docs/api.md, "Errors".
  static const unreachableReply =
      "Sorry, I couldn't reach the assistant. You can keep going and ask me again.";
  static const tooSlowReply =
      'The assistant took too long to answer. Ask me again in a moment.';

  static String _errorReply(Object error) =>
      error is TimeoutException ? tooSlowReply : unreachableReply;

  @override
  Future<void> warmUp() async {
    if (_cleanBaseUrl.isEmpty) return;
    try {
      await _httpClient
          .get(Uri.parse('$_cleanBaseUrl/health'))
          .timeout(const Duration(seconds: 90));
    } catch (_) {}
  }

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
        phase: phase,
        ingredients: ingredients,
        pendingOffer: pendingOffer,
      );
    }

    try {
      // The last few turns, oldest first (docs/api.md). Step announcements
      // repeat stepText, which is sent separately.
      final turns = history
          .where(
            (m) =>
                !m.isStepAnnouncement &&
                (m.sender == MessageSender.ai ||
                    m.sender == MessageSender.user),
          )
          .toList();
      final recentTurns = turns
          .skip(turns.length > 6 ? turns.length - 6 : 0)
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
              'phase': phase,
              'ingredients': [
                for (final e in ingredients.entries)
                  {'name': e.key, 'ready': e.value},
              ],
              'pendingOffer': ?pendingOffer?.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = data['reply'] as String?;
        if (reply != null && reply.isNotEmpty) {
          return AssistantResponse(
            reply: reply,
            offer: AssistantAction.fromJson(data['offer']),
            action: AssistantAction.fromJson(data['action']),
          );
        }
      }
      return const AssistantResponse(reply: unreachableReply, isError: true);
    } catch (e) {
      return AssistantResponse(reply: _errorReply(e), isError: true);
    }
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
      return const AssistantResponse(reply: unreachableReply, isError: true);
    } catch (e) {
      // No verdict at all, so the screen can't show "Looks ready" by mistake.
      return AssistantResponse(reply: _errorReply(e), isError: true);
    }
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
