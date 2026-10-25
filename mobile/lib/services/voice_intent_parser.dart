/// Structured intents parsed from user voice utterances on the Cooking screen.
enum VoiceIntentType {
  nextStep,

  /// "We can continue" after "hold on": say the cut-off reply again, or
  /// resume a paused session, or else move on like "next step".
  carryOn,
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
    final lower = trimmed.toLowerCase().replaceAll('’', "'");
    // Commands said naturally: "Okay, next step please."
    final command = _bareCommand(lower);

    // 1-2. Timer commands. A question that mentions a timer ("what do I do
    // if it's sticky before the timer hits 3 minutes?") goes to the AI;
    // only a request ("can you set a timer…") counts as a command.
    if (lower.contains('timer') && (!_isQuestion(lower) || _isRequest(lower))) {
      if (RegExp(
        r'\b(cancel|clear|remove|delete|reset|stop|end|turn off)\b.*\btimer\b',
      ).hasMatch(lower)) {
        return ParsedVoiceIntent(
          type: VoiceIntentType.cancelTimer,
          rawText: trimmed,
        );
      }
      if (RegExp(r'\bpause\b.*\btimer\b').hasMatch(lower)) {
        return ParsedVoiceIntent(
          type: VoiceIntentType.pauseTimer,
          rawText: trimmed,
        );
      }
      if (_isTimerRequest(lower)) {
        final parsedSeconds = _extractDurationSeconds(lower);
        return ParsedVoiceIntent(
          type: VoiceIntentType.startTimer,
          rawText: trimmed,
          timerSeconds: parsedSeconds ?? defaultStepTimerSeconds ?? 180,
          timerLabel: defaultStepTimerLabel ?? 'Cooking timer',
        );
      }
    }

    // 3. Explicit step check ("check this step", "check my progress", "verify step")
    if (RegExp(
      r'^(check|check it|check this step|check step|check this|verify this step|check my bowl|check my pan|check my food)$',
    ).hasMatch(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.visualCheckStep,
        rawText: trimmed,
        requiresVision: true,
      );
    }

    // 4. Visual questions that need a frame from the Meta glasses
    if (_hasVisualIntent(lower) || _hasVisualIntent(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.visualQuestion,
        rawText: trimmed,
        requiresVision: true,
      );
    }

    // 5. Step navigation
    if (RegExp(
      r'^(next|next step|next up|move on|done with this step|i finished this step|go to (the )?next step)$',
    ).hasMatch(command)) {
      return ParsedVoiceIntent(type: VoiceIntentType.nextStep, rawText: trimmed);
    }
    if (RegExp(
      r"^((we|you) can |let's )?(continue|carry on|go on|keep going)$|^i'?m back$",
    ).hasMatch(command)) {
      return ParsedVoiceIntent(type: VoiceIntentType.carryOn, rawText: trimmed);
    }
    if (RegExp(
      r'^(previous|previous step|go back|back a step|last step)$',
    ).hasMatch(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.previousStep,
        rawText: trimmed,
      );
    }
    if (RegExp(
      r'^(repeat|repeat that|say that again|read step again|what is this step)$',
    ).hasMatch(command)) {
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
      r'^(finish cooking|finish recipe|complete session|we are done)$',
    ).hasMatch(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.finishCooking,
        rawText: trimmed,
      );
    }

    // 6. Session & audio controls
    if (RegExp(r'^(pause|pause session|pause cooking)$').hasMatch(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.pauseSession,
        rawText: trimmed,
      );
    }
    if (RegExp(
      r'^(resume|resume session|continue cooking|unpause)$',
    ).hasMatch(command)) {
      return ParsedVoiceIntent(
        type: VoiceIntentType.resumeSession,
        rawText: trimmed,
      );
    }
    if (RegExp(r'^(mute|mute audio|quiet|stop speaking)$').hasMatch(command)) {
      return ParsedVoiceIntent(type: VoiceIntentType.muteAudio, rawText: trimmed);
    }
    if (RegExp(r'^(unmute|unmute audio|speak aloud)$').hasMatch(command)) {
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

  /// The user is ready to leave the opening chat and start step 1, as in
  /// the script's "I've got everything" or "let's start".
  static bool isReadyToStart(String input) => RegExp(
    r"^(let'?s (start|go|cook|begin)|let (us )?(start|go|cook|begin)|"
    r"start( cooking)?|i'?m ready|(we'?re )?ready|"
    r"(i'?ve |i have )?got (it all|everything)|i have everything|"
    r"that'?s everything|everything'?s (here|ready)|(yes,? )?all set|yes)$",
  ).hasMatch(_bareCommand(input.toLowerCase().replaceAll('’', "'")));

  /// Strips what people say around a command: "okay, ", "all right, ",
  /// "hey cooky, ", "please", "now" and end punctuation.
  static String _bareCommand(String lower) {
    final lead = RegExp(
      r'^(ok(ay)?|alright|all right|right|so|um+|uh+|well|great|cool|'
      r'(hey[,!.?;:\s]+|hi[,!.?;:\s]+|okay[,!.?;:\s]+|ok[,!.?;:\s]+|yo[,!.?;:\s]+|hello[,!.?;:\s]+)?'
      r'(cooky|cookie|cookies|kooky|cuki|cook ?along|cook ?together|cook))[,.!?]?\s+',
    );
    final tail = RegExp(r',?\s+(please|now|then|thanks|thank you)$');
    final end = RegExp(r'[.!?,\s]+$');
    var s = lower.trim().replaceFirst(end, '');
    String before;
    do {
      before = s;
      s = s.replaceFirst(lead, '').replaceFirst(tail, '').replaceFirst(end, '');
    } while (s != before);
    return s;
  }

  /// Asks something rather than tells CookTogether to do something.
  static bool _isQuestion(String lower) =>
      lower.contains('?') ||
      RegExp(
        r"^(what|how|why|when|where|which|who|should|shall|do|does|did|is|are|was|were|will|would|can|could|if|am)\b",
      ).hasMatch(lower);

  /// A polite command phrased as a question: "can you set a timer…".
  static bool _isRequest(String lower) => RegExp(
    r"^(can|could|would|will) you\b|^please\b",
  ).hasMatch(lower);

  /// Asks for a timer: "set / start / put on a timer…", or a short command
  /// such as "timer", "3 minute timer" or "timer for 5 minutes".
  static bool _isTimerRequest(String lower) =>
      RegExp(
        r'\b(set|start|begin|put on|put|add|make|run)\b[^.?!]*\btimer\b',
      ).hasMatch(lower) ||
      RegExp(
        r"^(a |the )?([\w-]+[ -](minute|min|second|sec)s?[ -])?timer( for [^.?!]*)?[.!?]*$",
      ).hasMatch(lower);

  static bool _hasVisualIntent(String lower) {
    final visualPatterns = [
      r'^(help|help me|i need help|can you help( me)?)[.!?]*$',
      r'\b(look at|take a look|have a look|see this|see my|what do you see|can you see)\b',
      // The script takes a photo when the cook says it looks good.
      r'^(it|this|that) looks (good|done|right|ready)\b',
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
