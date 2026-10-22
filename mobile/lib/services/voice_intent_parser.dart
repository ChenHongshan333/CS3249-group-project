/// Structured intents parsed from user voice utterances on the Cooking screen.
enum VoiceIntentType {
  nextStep,
  previousStep,
  repeatStep,
  openStepsSheet,
  startTimer,
  pauseTimer,
  cancelTimer,
  pauseSession,
  resumeSession,
  muteAudio,
  unmuteAudio,
  finishCooking,
  visualCheckStep,
  visualQuestion,
  generalQuestion,
}

class ParsedVoiceIntent {
  final VoiceIntentType type;
  final String rawText;
  final int? timerSeconds;
  final String? timerLabel;
  final bool requiresVision;

  const ParsedVoiceIntent({
    required this.type,
    required this.rawText,
    this.timerSeconds,
    this.timerLabel,
    this.requiresVision = false,
  });
}

class VoiceIntentParser {
  VoiceIntentParser._();

  static const Map<String, int> _wordNumbers = {
    'one': 1,
    'a': 1,
    'an': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'twelve': 12,
    'fifteen': 15,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'forty-five': 45,
    'sixty': 60,
  };

  /// Parses a spoken or typed command into a [ParsedVoiceIntent].
  static ParsedVoiceIntent parse(
    String input, {
    int? defaultStepTimerSeconds,
    String? defaultStepTimerLabel,
  }) {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();

    // 1. Timer cancellation / pause
    if (RegExp(
      r'\b(cancel|clear|remove|delete|reset)\b.*\btimer\b',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(type: VoiceIntentType.cancelTimer, rawText: trimmed);
    }
    if (RegExp(r'\b(pause|stop)\b.*\btimer\b').hasMatch(lower)) {
      return ParsedVoiceIntent(type: VoiceIntentType.pauseTimer, rawText: trimmed);
    }

    // 2. Timer creation ("set a timer for 5 minutes", "start timer", "3 minute timer")
    if (lower.contains('timer')) {
      final parsedSeconds = _extractDurationSeconds(lower);
      return ParsedVoiceIntent(
        type: VoiceIntentType.startTimer,
        rawText: trimmed,
        timerSeconds: parsedSeconds ?? defaultStepTimerSeconds ?? 180,
        timerLabel: defaultStepTimerLabel ?? 'Cooking timer',
      );
    }

    // 3. Explicit step check ("check this step", "check my progress", "verify step")
    if (RegExp(
      r'^(check this step|check step|check this|verify this step|check my bowl|check my pan|check my food)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.visualCheckStep,
        rawText: trimmed,
        requiresVision: true,
      );
    }

    // 4. Visual questions that need a frame from the Meta glasses
    if (_hasVisualIntent(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.visualQuestion,
        rawText: trimmed,
        requiresVision: true,
      );
    }

    // 5. Step navigation
    if (RegExp(
      r'^(next|next step|move on|continue|done with this step|i finished this step|go to next step)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(type: VoiceIntentType.nextStep, rawText: trimmed);
    }
    if (RegExp(
      r'^(previous|previous step|go back|back a step|last step)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.previousStep,
        rawText: trimmed,
      );
    }
    if (RegExp(
      r'^(repeat|repeat that|say that again|read step again|what is this step)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(type: VoiceIntentType.repeatStep, rawText: trimmed);
    }
    if (RegExp(
      r'\b(show|open|view|see)\b.*\b(all steps|steps|ingredients|recipe)\b',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.openStepsSheet,
        rawText: trimmed,
      );
    }
    if (RegExp(
      r'^(finish cooking|finish recipe|complete session|we are done)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.finishCooking,
        rawText: trimmed,
      );
    }

    // 6. Session & audio controls
    if (RegExp(r'^(pause|pause session|pause cooking)[.!?]*$').hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.pauseSession,
        rawText: trimmed,
      );
    }
    if (RegExp(
      r'^(resume|resume session|continue cooking|unpause)[.!?]*$',
    ).hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.resumeSession,
        rawText: trimmed,
      );
    }
    if (RegExp(r'^(mute|mute audio|quiet|stop speaking)[.!?]*$').hasMatch(lower)) {
      return ParsedVoiceIntent(type: VoiceIntentType.muteAudio, rawText: trimmed);
    }
    if (RegExp(r'^(unmute|unmute audio|speak aloud)[.!?]*$').hasMatch(lower)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.unmuteAudio,
        rawText: trimmed,
      );
    }

    // 7. Default to general conversational question
    return ParsedVoiceIntent(
      type: VoiceIntentType.generalQuestion,
      rawText: trimmed,
      requiresVision: false,
    );
  }

  static bool _hasVisualIntent(String lower) {
    final visualPatterns = [
      r'\b(look at|take a look|see this|see my|what do you see)\b',
      r'\b(does this look|how does this look|do these look)\b',
      r'\b(is this|are these)\b.*\b(small enough|thin enough|done|ready|cooked|translucent|soft|wilted|chopped|diced|sliced|good|right|burnt|brown)\b',
      r'\b(check if|can you check)\b',
      r'\b(enough oil|too much|heat too high)\b',
    ];
    for (final pattern in visualPatterns) {
      if (RegExp(pattern).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  static int? _extractDurationSeconds(String lower) {
    // Digit match: "5 minutes", "30 seconds", "2 min"
    final digitMatch = RegExp(
      r'(\d+)\s*(minute|minutes|min|mins|second|seconds|sec|secs)\b',
    ).firstMatch(lower);
    if (digitMatch != null) {
      final value = int.tryParse(digitMatch.group(1)!);
      final unit = digitMatch.group(2)!;
      if (value != null && value > 0) {
        return unit.startsWith('sec') ? value : value * 60;
      }
    }

    // Word number match: "three minutes", "a minute", "thirty seconds"
    for (final entry in _wordNumbers.entries) {
      final wordPattern = RegExp(
        '\\b${entry.key}\\s+(minute|minutes|min|mins|second|seconds|sec|secs)\\b',
      );
      final match = wordPattern.firstMatch(lower);
      if (match != null) {
        final unit = match.group(1)!;
        return unit.startsWith('sec') ? entry.value : entry.value * 60;
      }
    }

    return null;
  }
}
