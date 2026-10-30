import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/phone_camera.dart';
import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';
import '../models/user_preferences.dart';
import '../services/assistant_service.dart';
import '../services/cue_sounds.dart';
import '../services/step_adapter.dart';
import '../services/voice_controller.dart';
import '../services/voice_intent_parser.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'step_ingredient_sheet.dart';

/// Voice-first cooking workspace, built to be read at arm's length.
///
/// Layout hierarchy:
/// 1. Slim top bar: leave, recipe name, mute, pause, more
/// 2. Pinned step panel: progress, step title, instruction, tip, timers
/// 3. Quieter conversation with inline glasses-check results
/// 4. Dock: Check, the mic orb, and the primary Next action
class CookingScreen extends StatefulWidget {
  final Recipe recipe;
  final UserPreferences preferences;
  final GlassesService glassesService;
  final AssistantService assistantService;
  final VoiceController voiceController;
  final PhoneCamera? phoneCamera;
  final CueSounds? cueSounds;
  final Set<String> initialCheckedIngredients;
  final VoiceListeningMode initialListeningMode;
  final Set<String> acceptedSwapIds;
  final void Function({
    required int elapsedSeconds,
    required int stepsCompleted,
    required int visualChecksCount,
  })
  onFinishCooking;

  /// Ends the session without saving it.
  final VoidCallback onExitToHome;

  /// Leaves the session paused, to resume later from Home.
  final VoidCallback onPauseAndLeave;
  final ValueChanged<String> onShowToast;

  /// How the cook manages without each missing ingredient, chosen on Get
  /// ready. The steps are adapted for these before the opening (#98).
  final Map<String, MissingOption> missingChoices;

  /// False while the session is paused and left. Coming back resumes it.
  final bool isVisible;

  const CookingScreen({
    super.key,
    required this.recipe,
    required this.preferences,
    required this.glassesService,
    required this.assistantService,
    required this.voiceController,
    this.phoneCamera,
    this.cueSounds,
    required this.initialCheckedIngredients,
    this.missingChoices = const {},
    required this.initialListeningMode,
    this.acceptedSwapIds = const {},
    required this.onFinishCooking,
    required this.onExitToHome,
    required this.onPauseAndLeave,
    required this.onShowToast,
    this.isVisible = true,
  });

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen>
    with SingleTickerProviderStateMixin {
  late final String _sessionId;
  int _currentStep = 0;
  int _elapsedSeconds = 0;
  int _visualChecksCount = 0;
  bool _isPaused = false;
  bool _composerOpen = false;
  bool _confirmEndOpen = false;
  bool _waitingForReply = false;
  bool _confirmSkipOpen = false;
  bool _visualCheckInProgress = false;

  /// Steps the user has checked with a photo, so Next doesn't ask again.
  final Set<int> _checkedSteps = {};

  /// Paused by "Pause and leave for now", not by the Pause button, so coming
  /// back resumes.
  bool _pausedByLeaving = false;

  // The short chat before step 1 (docs/api.md, "The opening conversation").
  bool _opening = true;
  int _openingTurns = 0;
  final DateTime _openingStartedAt = DateTime.now();
  late final List<String> _openingAsked;

  // An offer from the last reply, such as "Would you like a timer?". It is
  // sent back once with the next question so "please" can accept it.
  AssistantAction? _pendingOffer;

  // The current step's timer, offered when the step was read out. It stays
  // on offer through other questions until the timer starts or the step
  // changes.
  AssistantAction? _stepTimerOffer;

  late Set<String> _checkedIngredients;

  /// This session's recipe. The opening can adapt its steps to a missing
  /// ingredient (adapt_steps); everything else then uses the new text.
  late Recipe _recipe = widget.recipe;
  final Set<int> _adaptedSteps = {};

  /// The step panel flashes briefly when the step changes, so a new step
  /// isn't mistaken for part of the chat.
  bool _stepHighlighted = false;
  Timer? _stepHighlightTimer;

  /// A one-time hint on first use: "Your current step is always here".
  static const _kStepHintSeenKey = 'cooktogether.stepHintSeen';
  bool _stepHintSeen = true;
  final List<ChatMessage> _messages = [];
  final List<CookingTimer> _timers = [];

  /// Finished timers fade out on their own after [_finishedTimerShown].
  static const _finishedTimerShown = Duration(seconds: 8);
  final Set<String> _fadingTimerIds = {};
  final Map<String, Timer> _fadeTimers = {};
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _clockTimer;
  late final AnimationController _orbPulseController;

  RecipeStep get _step => _recipe.steps[_currentStep];

  @override
  void initState() {
    super.initState();
    _sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';
    _checkedIngredients = Set<String>.from(widget.initialCheckedIngredients);

    _orbPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    widget.voiceController.onFinalUtterance = _handleUserUtterance;
    widget.voiceController.addListener(_onVoiceChanged);
    widget.voiceController.onNothingHeard = () =>
        _appendAiMessage("Sorry, I didn't catch that. Could you say it again?");
    widget.voiceController.onListeningStopped = () =>
        _appendAiMessage('Tap the mic when you need me.');

    // Fall back to the Mock Device Kit, unless the user chose real glasses
    // (those reconnect on their own).
    if (!widget.glassesService.isConnected &&
        !widget.glassesService.usingRealGlasses) {
      widget.glassesService.initializeAndPairMockDevice();
    }

    _loadStepHintSeen();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused) return;
      final finished = <CookingTimer>[];
      final reminders = <String>[];
      setState(() {
        _elapsedSeconds++;
        for (int i = 0; i < _timers.length; i++) {
          final t = _timers[i];
          if (t.isRunning && t.remainingSeconds > 0) {
            final nextRemaining = t.remainingSeconds - 1;
            _timers[i] = t.copyWith(
              remainingSeconds: nextRemaining,
              isRunning: nextRemaining > 0,
            );
            if (nextRemaining == 0) finished.add(t);
            final reminder = _timerReminder(t, nextRemaining);
            if (reminder != null) reminders.add(reminder);
          }
        }
      });
      for (final t in finished) {
        _onTimerFinished(t);
      }
      for (final reminder in reminders) {
        _speakOnly(reminder);
      }
    });

    // A fixed first line, so every participant hears the same opening.
    _openingAsked = _recipe.ingredients
        .where((i) => !_checkedIngredients.contains(i))
        .toList();
    final adapted = StepAdapter.forChoices(widget.recipe, _activeChoices);
    _recipe = adapted.recipe;
    _adaptedSteps.addAll(adapted.changed);
    final openingText = _openingLine(adjusted: adapted.changed.isNotEmpty);
    _messages.add(
      ChatMessage(
        id: 'init-0',
        sender: MessageSender.ai,
        text: openingText,
        timestamp: DateTime.now(),
      ),
    );
    if (_changesNote(adapted) case final note?) _messages.add(_note(note));
    _initializeVoiceAndAnnounce(openingText);
  }

  /// The Get ready choices for ingredients that are still missing.
  Map<String, MissingOption> get _activeChoices => {
    for (final e in widget.missingChoices.entries)
      if (!_checkedIngredients.contains(e.key)) e.key: e.value,
  };

  /// What the cook chose instead of each missing ingredient, for the
  /// backend.
  Map<String, String> get _substitutes => {
    for (final e in _activeChoices.entries) e.key: ?e.value.use,
  };

  /// A short summary of the missing ingredients, with no question about
  /// them: they were decided on Get ready (#98).
  String _openingLine({required bool adjusted}) {
    final name = _recipe.name;
    final missing = _openingAsked;
    if (missing.isEmpty) {
      return "Today we're making $name, right? You've got everything, "
          "so say 'let's start' when you're ready.";
    }
    final choices = widget.missingChoices;
    final leaving = [
      for (final i in missing)
        if (choices[i]?.use == null) i,
    ];
    final using = [
      for (final i in missing)
        if (choices[i]?.use case final use?) '$use instead of the $i',
    ];
    final prepare = {for (final i in missing) ?choices[i]?.prepare};
    // "That's fine" only once the steps match (#94); tests and screenshots
    // can open the cooking screen without Get ready choices.
    final decided = leaving.every(choices.containsKey);
    return [
      "Today we're making $name.",
      if (leaving.isNotEmpty)
        "You don't have the ${_listed(leaving)}${decided ? ", that's fine" : ''}.",
      if (using.isNotEmpty) "You're using ${_listed(using)}.",
      if (adjusted) "I've adjusted the steps.",
      ...prepare,
      "Say 'let's start' when you're ready.",
    ].join(' ');
  }

  static String _listed(List<String> items) => items.length == 1
      ? items.first
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  ChatMessage _note(String text) => ChatMessage(
    id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
    sender: MessageSender.system,
    text: text,
    timestamp: DateTime.now(),
  );

  /// The changed and removed steps, shown in the chat but not spoken.
  String? _changesNote(AdaptedRecipe adapted) {
    if (adapted.changed.isEmpty && adapted.removed.isEmpty) return null;
    final steps = adapted.recipe.steps;
    return [
      'Changed for you:',
      for (final i in adapted.changed.toList()..sort())
        'Step ${i + 1}, ${steps[i].title}: ${steps[i].instruction}',
      for (final title in adapted.removed) 'No longer needed: $title',
    ].join('\n');
  }

  /// A missing ingredient turned up in the opening, or went missing again:
  /// the steps follow the Get ready choices that still apply. Changes made
  /// in the chat are dropped then, since they were for other steps.
  void _followChoices(Set<String> before) {
    final choices = _activeChoices;
    if (choices.keys.toSet().containsAll(before) &&
        before.containsAll(choices.keys)) {
      return;
    }
    final adapted = StepAdapter.forChoices(widget.recipe, choices);
    setState(() {
      _recipe = adapted.recipe;
      _adaptedSteps
        ..clear()
        ..addAll(adapted.changed);
      _messages.add(
        _note(_changesNote(adapted) ?? 'Back to the steps as written.'),
      );
    });
    _scrollToBottom();
  }

  /// Leaves the opening, once, and records how it went.
  void _endOpening() {
    if (!_opening) return;
    setState(() {
      _opening = false;
      _pendingOffer = null;
    });
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'opening_end',
      data: {
        'ms': DateTime.now().difference(_openingStartedAt).inMilliseconds,
        'turns': _openingTurns,
        'missing': _recipe.ingredients
            .where((i) => !_checkedIngredients.contains(i))
            .toList(),
        'using': _substitutes,
      },
    );
  }

  Future<void> _loadStepHintSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_kStepHintSeenKey) ?? false;
      if (mounted) setState(() => _stepHintSeen = seen);
    } catch (_) {}
  }

  Future<void> _dismissStepHint() async {
    setState(() => _stepHintSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kStepHintSeenKey, true);
    } catch (_) {}
  }

  void _highlightStep() {
    _stepHighlightTimer?.cancel();
    setState(() => _stepHighlighted = true);
    _stepHighlightTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _stepHighlighted = false);
    });
  }

  void _startCooking({String? lead}) {
    if (!_opening) return;
    _goToStep(0, lead: lead);
  }

  Future<void> _initializeVoiceAndAnnounce(String openingText) async {
    widget.voiceController.useGlassesMic =
        kGlassesMicEnabled && !widget.preferences.phoneMicOnly;
    await widget.voiceController.configureVoice(
      voiceName: widget.preferences.ttsVoiceName,
      voiceLocale: widget.preferences.ttsVoiceLocale,
      pitch: widget.preferences.ttsPitch,
      rate: widget.preferences.ttsRate,
    );
    await widget.voiceController.initialize(
      initialMode: widget.initialListeningMode,
      initialMuted: !widget.preferences.voiceGuidance,
      startListeningImmediately: false,
    );
    if (!mounted) return;
    await widget.voiceController.speak(
      openingText,
      voiceGuidanceEnabled: widget.preferences.voiceGuidance,
    );
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'session_start',
      data: {'recipeId': _recipe.id, 'condition': 'glasses_cui'},
    );
    for (final swap in _recipe.swaps) {
      widget.assistantService.logEvent(
        sessionId: _sessionId,
        type: 'swap',
        data: {
          'swapId': swap.id,
          'accepted': widget.acceptedSwapIds.contains(swap.id),
        },
      );
    }
  }

  @override
  void didUpdateWidget(CookingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && _pausedByLeaving) {
      _pausedByLeaving = false;
      // After this frame: resuming updates the app's toast too.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isPaused) _togglePause(forcePause: false);
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _stepHighlightTimer?.cancel();
    for (final t in _fadeTimers.values) {
      t.cancel();
    }
    _orbPulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    
    widget.voiceController.removeListener(_onVoiceChanged);
    
    // A new session may already have taken over the voice controller (it
    // starts in the same frame that ends a paused one), so leave it alone.
    if (widget.voiceController.onFinalUtterance == _handleUserUtterance) {
      widget.voiceController
        ..onFinalUtterance = null
        ..onNothingHeard = null
        ..onListeningStopped = null;
      widget.voiceController.shutdownSession();
    }
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.voiceController.partialTranscript.isNotEmpty ||
        widget.voiceController.activityState == VoiceActivityState.thinking) {
      _scrollToBottom();
    }
  }

  void _appendUserMessage(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'usr-${DateTime.now().microsecondsSinceEpoch}',
          sender: MessageSender.user,
          text: text,
          timestamp: DateTime.now(),
          stepIndex: _opening ? null : _currentStep,
        ),
      );
    });
    _scrollToBottom();
  }

  /// [stepIndex] defaults to the step the photo was taken on, or else the
  /// current step.
  void _appendAiMessage(
    String text, {
    VisionCapture? visionCapture,
    bool isStepAnnouncement = false,
    int? stepIndex,
    bool? isQuestion,
  }) {
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'ai-${DateTime.now().microsecondsSinceEpoch}',
          sender: MessageSender.ai,
          text: text,
          timestamp: DateTime.now(),
          visionCapture: visionCapture,
          isStepAnnouncement: isStepAnnouncement,
          stepIndex:
              stepIndex ??
              visionCapture?.stepIndex ??
              (_opening ? null : _currentStep),
        ),
      );
    });
    _scrollToBottom();
    // A paused session stays quiet, also when a reply arrives after the
    // user paused and left; the message is still in the chat.
    if (_isPaused) return;
    widget.voiceController.speak(
      text,
      voiceGuidanceEnabled: widget.preferences.voiceGuidance,
      isQuestion: isQuestion,
    );
  }

  /// Spoken reminders for timers of 3 minutes or more: halfway (when that
  /// isn't close to the end) and 1 minute before the end.
  String? _timerReminder(CookingTimer t, int remaining) {
    if (t.totalSeconds < 180) return null;
    final name = t.label.toLowerCase();
    if (remaining == 60) return '1 minute left on your $name timer.';
    final half = t.totalSeconds ~/ 2;
    if (remaining == half && half - 60 >= 30) {
      final minutes = (half / 60).round();
      return 'Halfway there: $minutes minutes left on your $name timer.';
    }
    return null;
  }

  /// A ding, then CookTogether says so; the row fades out a little later.
  void _onTimerFinished(CookingTimer t) {
    widget.cueSounds?.play(Cue.timerDone);
    widget.onShowToast('Timer finished: ${t.label} — check your food!');
    // After the ding, so the two don't talk over each other.
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _appendAiMessage(
        'Your ${t.label.toLowerCase()} timer just finished! Take a look or say "check this step" so we can inspect it together.',
      );
    });
    _fadeTimers[t.id]?.cancel();
    _fadeTimers[t.id] = Timer(_finishedTimerShown, () {
      if (mounted) setState(() => _fadingTimerIds.add(t.id));
    });
  }

  void _removeTimer(String id) {
    _fadeTimers.remove(id)?.cancel();
    _fadingTimerIds.remove(id);
    setState(() => _timers.removeWhere((t) => t.id == id));
  }

  /// Says [text] without adding it to the chat, when the screen already
  /// shows it (the timer row, the Skip/Check prompt).
  void _speakOnly(String text, {bool? isQuestion}) {
    if (_isPaused) return;
    widget.voiceController.speak(
      text,
      voiceGuidanceEnabled: widget.preferences.voiceGuidance,
      isQuestion: isQuestion,
    );
  }

  Future<void> _startOrUpdateTimer({
    required int seconds,
    required String label,
  }) async {
    if (identical(_pendingOffer, _stepTimerOffer)) _pendingOffer = null;
    _stepTimerOffer = null;
    setState(() {
      // One timer per step: a new one for this step replaces the old one,
      // whatever it's called (the button, voice and the AI name it
      // differently).
      final existingIdx = _timers.indexWhere(
        (t) => t.stepIndex == _currentStep,
      );
      final timer = CookingTimer(
        id: 'tmr-${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        totalSeconds: seconds,
        remainingSeconds: seconds,
        isRunning: true,
        stepIndex: _currentStep,
      );
      if (existingIdx >= 0) {
        _timers[existingIdx] = timer;
      } else {
        _timers.add(timer);
      }
    });
    try {
      await widget.cueSounds?.play(Cue.timerStart);
    } catch (_) {}
    final mins = (seconds / 60).ceil();
    widget.onShowToast('$label started ($mins min)');
  }

  /// Offers the step's timer for the moment it should start, such as
  /// "Tell me when the eggs are in the pan, and I'll start a 2-minute timer."
  String? _timerCue(RecipeStep step) {
    final seconds = step.suggestedTimerSeconds;
    final start = step.timerStart;
    if (seconds == null || start == null) return null;
    final length = seconds % 60 == 0
        ? '${seconds ~/ 60}-minute'
        : '$seconds-second';
    return "Tell me when $start, and I'll start a $length timer.";
  }

  void _goToStep(int targetStep, {bool fromVoice = false, String? lead}) {
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
    _endOpening();
    _pendingOffer = null;
    if (targetStep >= _recipe.steps.length) {
      _completeSession();
      return;
    }
    final clamped = targetStep.clamp(0, _recipe.steps.length - 1);
    // Moving on means the step is done, so its timer ends quietly.
    if (clamped > _currentStep) _endTimerForStep(_currentStep);
    // The hint has done its job once the cook moves past step 1.
    if (clamped > 0 && !_stepHintSeen) _dismissStepHint();
    setState(() {
      _currentStep = clamped;
    });
    _highlightStep();
    final nextStepObj = _recipe.steps[clamped];
    final cue = _timerCue(nextStepObj);
    final announcement =
        'Step ${clamped + 1}: ${nextStepObj.title}. ${nextStepObj.instruction}'
        '${cue == null ? '' : ' $cue'}';
    // So "yes" or "they're in" starts the timer the cue offered.
    _stepTimerOffer = cue == null
        ? null
        : AssistantAction(
            'start_timer',
            seconds: nextStepObj.suggestedTimerSeconds,
            label: nextStepObj.suggestedTimerLabel ?? nextStepObj.title,
          );
    _pendingOffer = _stepTimerOffer;
    _appendAiMessage(
      lead == null ? announcement : '$lead $announcement',
      isStepAnnouncement: true,
      stepIndex: clamped,
    );
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'step_next',
      data: {'step': clamped, 'fromVoice': fromVoice},
    );
  }

  void _completeSession() {
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'session_end',
      data: {'completed': true},
    );
    widget.onFinishCooking(
      elapsedSeconds: _elapsedSeconds,
      stepsCompleted: _recipe.steps.length,
      visualChecksCount: _visualChecksCount,
    );
  }

  /// Takes the photo for a step check: from the real glasses when they are
  /// connected, otherwise from the phone camera. If the glasses fail, says
  /// why and uses the phone camera instead. Returns null, after saying why,
  /// when no photo was taken. The Mock Device Kit is only used when the
  /// Developer setting asks for it.
  Future<VisionCapture?> _takeStepPhoto(String promptText) async {
    final glasses = widget.glassesService;
    final useGlasses =
        glasses.usingRealGlasses || widget.preferences.simulatedGlassesPhotos;
    if (useGlasses) {
      final step = _currentStep;
      final ready = await widget.voiceController.prepareForPhoto(
        voiceGuidanceEnabled: widget.preferences.voiceGuidance,
      );
      if (!mounted || _isPaused || !widget.isVisible || _currentStep != step) {
        return null;
      }
      if (!ready) {
        _appendAiMessage('Photo cancelled. Say "check this" to try again.');
        return null;
      }
      widget.voiceController.setActivityState(
        VoiceActivityState.capturingVision,
        hint: 'Taking a photo with your glasses…',
      );
      try {
        final capture = await glasses.captureFrame(
          recipe: _recipe,
          stepIndex: _currentStep,
          userPrompt: promptText,
        );
        if (!mounted || _isPaused || !widget.isVisible || _currentStep != step) {
          return null;
        }
        await widget.voiceController.playPhotoShutter();
        return capture;
      } on GlassesCaptureException catch (e) {
        if (e.busy) {
          if (mounted) _appendAiMessage(e.message);
          return null;
        }
        if (mounted) {
          _appendAiMessage(
            '${e.message} Let\'s use your phone camera instead.',
          );
        }
      }
    }
    if (!mounted || _isPaused || !widget.isVisible) return null;
    return _takePhonePhoto(promptText);
  }

  Future<VisionCapture?> _takePhonePhoto(String promptText) async {
    final camera = widget.phoneCamera;
    if (camera == null) {
      if (mounted) {
        _appendAiMessage('No camera is available for a photo check.');
      }
      return null;
    }
    widget.voiceController.setActivityState(
      VoiceActivityState.capturingVision,
      hint: 'Take a photo of your food with the phone…',
    );
    final Uint8List? bytes;
    try {
      bytes = await camera.takePhoto();
    } on PhoneCameraException catch (e) {
      if (mounted) _appendAiMessage(e.message);
      return null;
    }
    if (bytes == null) {
      if (mounted) {
        _appendAiMessage(
          'No photo taken. Say "check this" when you\'re ready.',
        );
      }
      return null;
    }
    final step = _recipe.steps[_currentStep];
    return VisionCapture(
      id: 'phone-${DateTime.now().millisecondsSinceEpoch}',
      recipeId: _recipe.id,
      stepIndex: _currentStep,
      source: 'phone',
      deviceName: 'Phone camera',
      sceneDescription: step.visionSceneDescription,
      recipeIcon: _recipe.icon,
      recipeTone: _recipe.tone,
      jpegBytes: bytes,
      base64Jpeg: base64Encode(bytes),
      capturedAt: DateTime.now(),
      userQuestion: promptText,
    );
  }

  /// A stand-in for a photo when the Developer option forces the result.
  VisionCapture _forcedCapture(String promptText, VisualCheckStatus status) {
    final step = _recipe.steps[_currentStep];
    return VisionCapture(
      id: 'forced-${DateTime.now().millisecondsSinceEpoch}',
      recipeId: _recipe.id,
      stepIndex: _currentStep,
      source: 'developer',
      deviceName: 'Developer option',
      sceneDescription: step.visionSceneDescription,
      recipeIcon: _recipe.icon,
      recipeTone: _recipe.tone,
      base64Jpeg: '',
      capturedAt: DateTime.now(),
      status: status,
      userQuestion: promptText,
    );
  }

  Future<void> _triggerVisualCheck({String? userQuestion}) async {
    if (_visualCheckInProgress) return;
    _visualCheckInProgress = true;
    try {
      await _performVisualCheck(userQuestion: userQuestion);
    } finally {
      _visualCheckInProgress = false;
    }
  }

  Future<void> _performVisualCheck({String? userQuestion}) async {
    if (_opening) {
      _appendAiMessage("Let's start the first step, then I can take a look.");
      return;
    }
    // A photo check changes the subject; a later "sure" isn't an answer
    // to an offer made before it, except the step's own timer offer.
    _pendingOffer = _stepTimerOffer;
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
    final promptText = userQuestion ?? 'Check this step through my glasses';
    if (userQuestion == null) {
      _appendUserMessage('Check this step 🕶️');
    }

    final startTime = DateTime.now();
    final checkedStep = _currentStep;
    final forced = widget.preferences.forcedCheckResult.isEmpty
        ? null
        : VisualCheckStatus.fromWire(widget.preferences.forcedCheckResult);
    final capture = forced != null
        ? _forcedCapture(promptText, forced)
        : await _takeStepPhoto(promptText);
    if (!mounted) return;
    if (capture == null) {
      widget.voiceController.setActivityState(VoiceActivityState.idle);
      return;
    }

    widget.voiceController.setActivityState(
      VoiceActivityState.thinking,
      hint: 'Analyzing visual view with CookTogether AI…',
    );

    final response = forced != null
        ? AssistantResponse(
            reply:
                '${forced.badgeLabel}. ${forced.subtitle}. '
                '(Set under Profile → Developer.)',
            visualStatus: forced,
            visionCapture: capture,
          )
        : await widget.assistantService.checkStepWithVision(
            sessionId: _sessionId,
            recipe: _recipe,
            stepIndex: _currentStep,
            visionCapture: capture,
            userQuestion: userQuestion,
          );

    if (!mounted) return;
    if (response.isError) {
      _appendAiMessage(response.reply);
      return;
    }
    setState(() {
      _visualChecksCount++;
      _checkedSteps.add(checkedStep);
    });

    _appendAiMessage(
      response.reply,
      visionCapture: response.visionCapture ?? capture,
    );

    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'check',
      data: {
        'step': _currentStep,
        'status': (response.visualStatus ?? VisualCheckStatus.done).wireValue,
        'ms': elapsedMs,
        // So study data can leave out results nobody actually saw.
        if (forced != null) 'forced': true,
      },
    );
  }

  Future<void> _handleUserUtterance(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    _appendUserMessage(text);
    _textController.clear();

    final intent = await VoiceIntentParser.parseAsync(
      text,
      defaultStepTimerSeconds: _step.suggestedTimerSeconds,
      defaultStepTimerLabel: _step.suggestedTimerLabel ?? _step.title,
    );

    if (_opening && !_worksInOpening.contains(intent.type)) {
      if (intent.type == VoiceIntentType.nextStep ||
          intent.type == VoiceIntentType.carryOn ||
          VoiceIntentParser.isReadyToStart(text)) {
        _startCooking();
      } else {
        await _askAssistant(text);
      }
      return;
    }

    // An answer to "Skip this step without checking?". Anything else closes
    // the question and is handled as usual ("check" takes the photo).
    if (_confirmSkipOpen) {
      setState(() => _confirmSkipOpen = false);
      if (RegExp(
        r"^(yes|yeah|yep|ok(ay)?|sure|skip( it)?|next( step)?|move on|go ahead)\b",
      ).hasMatch(text.toLowerCase())) {
        _moveOn(fromVoice: true);
        return;
      }
      if (RegExp(
        r"^(check|check first|check it|check this|take a look|inspect|look at this)\b",
      ).hasMatch(text.toLowerCase())) {
        _triggerVisualCheck(userQuestion: text);
        return;
      }
      if (RegExp(
        r"^(no|nope|don'?t|stay|cancel)\b",
      ).hasMatch(text.toLowerCase())) {
        return;
      }
    }

    // "It's done" ends the step's timer quietly, so it doesn't announce
    // later; the reply carries on as usual.
    if (RegExp(
      r"\b(it'?s|they'?re|that'?s|i'?m|we'?re|it is|they are) (all )?(done|finished|ready|cooked)\b",
    ).hasMatch(text.toLowerCase())) {
      _endTimerForStep(_currentStep);
    }

    // A command the app handles itself replaces any open offer.
    // A command answers any offer, except the step's own timer offer.
    if (intent.type != VoiceIntentType.generalQuestion) {
      _pendingOffer = _stepTimerOffer;
    }

    switch (intent.type) {
      case VoiceIntentType.nextStep:
        _nextOrFinish(fromVoice: true);
        return;

      case VoiceIntentType.carryOn:
        if (_isPaused) {
          _togglePause(forcePause: false);
        } else {
          _nextOrFinish(fromVoice: true);
        }
        return;

      case VoiceIntentType.previousStep:
        if (_currentStep > 0) {
          _goToStep(_currentStep - 1, fromVoice: true);
        } else {
          _appendAiMessage(
            'You are already on Step 1: ${_step.title}. ${_step.instruction}',
          );
        }
        return;

      case VoiceIntentType.repeatStep:
        _appendAiMessage(
          'Repeating Step ${_currentStep + 1}: ${_step.instruction} Tip: ${_step.tip}',
        );
        widget.assistantService.logEvent(
          sessionId: _sessionId,
          type: 'step_repeat',
          data: {'step': _currentStep},
        );
        return;

      case VoiceIntentType.openStepsSheet:
        _openStepAndIngredientSheet();
        _appendAiMessage(
          'I opened the recipe steps and ingredient checklist for you.',
        );
        return;

      case VoiceIntentType.startTimer:
        final seconds = intent.timerSeconds ?? 180;
        final label = intent.timerLabel ?? _step.title;
        await _startOrUpdateTimer(seconds: seconds, label: label);
        // Beep chime plays before the assistant confirms aloud
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        final mins = (seconds / 60).ceil();
        _appendAiMessage(
          'I set a $mins-minute timer for ${label.toLowerCase()}. Keep going—I will let you know when it finishes.',
        );
        return;

      case VoiceIntentType.pauseTimer:
        if (_timers.isEmpty) {
          _appendAiMessage('There is no active timer running right now.');
        } else {
          // Timers don't pause (#93): with no resume button, a paused one
          // would be stuck. Letting it run is the way to wait longer.
          _appendAiMessage(
            'The timer keeps running. Say "stop the timer" if you '
            "don't need it.",
          );
        }
        return;

      case VoiceIntentType.cancelTimer:
        if (_timers.isEmpty) {
          _appendAiMessage('There is no timer running right now.');
        } else if (_hasActiveTimerForCurrentStep) {
          _endTimerForStep(_currentStep);
          _appendAiMessage('I stopped the timer.');
        } else {
          setState(() => _timers.clear());
          _appendAiMessage('I stopped your timers.');
        }
        return;

      case VoiceIntentType.pauseSession:
        _togglePause(forcePause: true);
        return;

      case VoiceIntentType.resumeSession:
        _togglePause(forcePause: false);
        return;

      case VoiceIntentType.muteAudio:
        await widget.voiceController.setAudioMuted(true);
        widget.onShowToast('Voice audio muted');
        return;

      case VoiceIntentType.unmuteAudio:
        await widget.voiceController.setAudioMuted(false);
        _appendAiMessage('Voice guidance is back on.');
        return;

      case VoiceIntentType.finishCooking:
        _completeSession();
        return;

      case VoiceIntentType.visualCheckStep:
      case VoiceIntentType.visualQuestion:
        await _triggerVisualCheck(userQuestion: text);
        return;

      case VoiceIntentType.generalQuestion:
        await _askAssistant(text);
        return;
    }
  }

  // Commands that still make sense before step 1.
  static const _worksInOpening = {
    VoiceIntentType.pauseSession,
    VoiceIntentType.resumeSession,
    VoiceIntentType.muteAudio,
    VoiceIntentType.unmuteAudio,
    VoiceIntentType.openStepsSheet,
  };

  Future<void> _askAssistant(String text) async {
    setState(() => _waitingForReply = true);
    widget.voiceController.setActivityState(
      VoiceActivityState.thinking,
      hint: 'Thinking…',
    );
    final offer = _pendingOffer;
    _pendingOffer = null;
    final startTime = DateTime.now();
    // The answer goes with the step the question was asked on.
    final askedOnStep = _opening ? null : _currentStep;
    final response = await widget.assistantService.askQuestion(
      sessionId: _sessionId,
      recipe: _recipe,
      stepIndex: _currentStep,
      question: text,
      history: _messages,
      acceptedSwaps: widget.acceptedSwapIds.toList(),
      phase: _opening ? 'opening' : 'cooking',
      ingredients: {
        for (final i in _recipe.ingredients) i: _checkedIngredients.contains(i),
      },
      substitutes: _substitutes,
      pendingOffer: offer,
    ).whenComplete(() {
      if (mounted) setState(() => _waitingForReply = false);
    });
    if (!mounted) return;
    if (_opening) _openingTurns++;
    // After an error the question was never answered, so the offer stands.
    _pendingOffer = response.isError
        ? offer
        : response.offer ?? _stepTimerOffer;

    final action = response.action;
    // These read a step aloud, so the reply leads into that announcement
    // instead of being spoken on its own and cut off.
    final leadsIn =
        action != null &&
        const {
          'next_step',
          'repeat_step',
          'start_cooking',
        }.contains(action.type);
    if (action != null && action.type == 'start_timer' && !_opening) {
      await _startOrUpdateTimer(
        seconds: action.seconds ?? _step.suggestedTimerSeconds ?? 180,
        label: action.label ?? _step.suggestedTimerLabel ?? _step.title,
      );
      // Give start chime time to play before the reply is spoken
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      _appendAiMessage(response.reply, stepIndex: askedOnStep);
    } else {
      if (!leadsIn) _appendAiMessage(response.reply, stepIndex: askedOnStep);
      if (action != null) {
        _runAction(
          action,
          lead: leadsIn ? response.reply : null,
          reply: response.reply,
        );
      }
    }

    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'question',
      data: {
        'step': _opening ? -1 : _currentStep,
        'question': text,
        'reply': response.reply,
        'ms': DateTime.now().difference(startTime).inMilliseconds,
      },
    );
  }

  /// Does what the assistant asked, the same way the buttons would.
  void _runAction(AssistantAction action, {String? lead, String? reply}) {
    switch (action.type) {
      case 'start_timer' when !_opening:
        _startOrUpdateTimer(
          seconds: action.seconds!,
          label: action.label ?? _step.title,
        );
      case 'next_step' when !_opening:
        if (_isLastStep) {
          if (lead != null) _appendAiMessage(lead);
          _completeSession();
        } else {
          _goToStep(_currentStep + 1, fromVoice: true, lead: lead);
        }
      case 'repeat_step' when !_opening:
        _appendAiMessage(
          '${lead ?? ''} Step ${_currentStep + 1}: ${_step.instruction}'.trim(),
          isStepAnnouncement: true,
          stepIndex: _currentStep,
        );
      case 'start_cooking' when _opening:
        _startCooking(lead: lead);
      case 'adapt_steps' when _opening:
        _adaptSteps(action.steps);
      case 'custom_swap' when _opening:
        _customSwap(action, reason: reply ?? '');
      case 'tick_ingredient' when _opening:
        final names = {...action.names, ?action.name};
        final before = _activeChoices.keys.toSet();
        setState(
          () => _checkedIngredients.addAll(
            names.where(_recipe.ingredients.contains),
          ),
        );
        _followChoices(before);
      default:
        // Doesn't fit the current phase; the backend should not send it.
        if (lead != null) _appendAiMessage(lead);
    }
  }

  /// Changes or removes steps for a missing ingredient, and notes the
  /// changes in the chat. The reply already said so aloud, so the note
  /// isn't spoken. Returns whether any step changed.
  ///
  /// The cook's own swaps log as `custom_swap` instead of `swap` (#22).
  bool _adaptSteps(Map<int, StepEdit> changes, {bool logAsSwap = true}) {
    final adapted = StepAdapter.apply(_recipe, changes);
    final note = _changesNote(adapted);
    if (note == null) return false;
    setState(() {
      _recipe = adapted.recipe;
      final kept = {for (final i in _adaptedSteps) ?adapted.moved[i]};
      _adaptedSteps
        ..clear()
        ..addAll({...kept, ...adapted.changed});
      _messages.add(_note(note));
    });
    _scrollToBottom();
    if (logAsSwap) {
      widget.assistantService.logEvent(
        sessionId: _sessionId,
        type: 'swap',
        data: {
          'adaptedSteps': [for (final i in changes.keys) i],
        },
      );
    }
    return true;
  }

  /// A swap the cook suggested (#22). Steps change only when CookAlong
  /// judged it healthier and a fit. It is logged apart from the fixed
  /// swaps, so they stay the same for every participant.
  void _customSwap(AssistantAction action, {required String reason}) {
    final works = action.healthier == true && action.fits == true;
    final applied = works && _adaptSteps(action.steps, logAsSwap: false);
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'custom_swap',
      data: {
        'swap': action.swap,
        'healthier': action.healthier,
        'fits': action.fits,
        'applied': applied,
        'reason': reason,
      },
    );
  }

  void _togglePause({bool? forcePause}) {
    final nextPaused = forcePause ?? !_isPaused;
    setState(() {
      _isPaused = nextPaused;
    });
    widget.voiceController.setSessionPaused(nextPaused);
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: nextPaused ? 'pause' : 'resume',
      data: {'step': _currentStep},
    );
    widget.onShowToast(
      nextPaused ? 'Cooking session paused' : 'Cooking session resumed',
    );
  }

  void _openStepAndIngredientSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.8,
        child: StepIngredientSheet(
          recipe: _recipe,
          currentStepIndex: _currentStep,
          checkedIngredients: _checkedIngredients,
          onSelectStep: (idx) => _goToStep(idx),
          onToggleIngredient: (ingredient) {
            setState(() {
              if (_checkedIngredients.contains(ingredient)) {
                _checkedIngredients.remove(ingredient);
              } else {
                _checkedIngredients.add(ingredient);
              }
            });
          },
        ),
      ),
    );
  }

  String _formatElapsed(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  bool get _hasActiveTimerForCurrentStep =>
      _timers.any((t) => t.stepIndex == _currentStep);

  /// Ends this step's timer without a "finished" announcement, for when the
  /// user says the step is done or moves on.
  void _endTimerForStep(int step) {
    for (final t in _timers.where((t) => t.stepIndex == step).toList()) {
      _removeTimer(t.id);
    }
  }

  bool get _isLastStep => _currentStep == _recipe.steps.length - 1;

  /// Next and "next step" ask first when this step hasn't been checked.
  /// Users can always skip; this only confirms.
  void _nextOrFinish({bool fromVoice = false}) {
    if (!_isPaused && !_checkedSteps.contains(_currentStep)) {
      setState(() => _confirmSkipOpen = true);
      const ask =
          "You haven't checked this step yet. Would you like to skip, or "
          'check first?';
      // A tap already shows Skip and Check on screen, so it's only said
      // aloud: the chat stays for what was actually talked about.
      if (fromVoice) {
        _appendAiMessage(ask, isQuestion: true);
      } else {
        _speakOnly(ask, isQuestion: true);
      }
      return;
    }
    _moveOn(fromVoice: fromVoice);
  }

  void _moveOn({bool fromVoice = false}) {
    if (_isLastStep) {
      _completeSession();
    } else {
      _goToStep(_currentStep + 1, fromVoice: fromVoice);
    }
  }

  void _toggleListeningMode() {
    final nextMode =
        widget.voiceController.listeningMode == VoiceListeningMode.handsFree
        ? VoiceListeningMode.tapToSpeak
        : VoiceListeningMode.handsFree;
    widget.voiceController.setListeningMode(nextMode);
    widget.onShowToast(
      nextMode == VoiceListeningMode.handsFree
          ? 'Hands-free listening on'
          : 'Tap the mic when you want to talk',
    );
  }

  @override
  Widget build(BuildContext context) {
    // The back gesture asks before leaving, like the close button; with a
    // question open, back answers "stay" (or "don't skip").
    // While paused and left, the screen is kept but hidden; back is then
    // for the screen on top.
    return PopScope(
      canPop: !widget.isVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.isVisible) return;
        setState(() {
          if (_confirmSkipOpen) {
            _confirmSkipOpen = false;
          } else {
            _confirmEndOpen = !_confirmEndOpen;
          }
        });
      },
      child: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              // On short phones the step scrolls rather than squeezing the
              // conversation to nothing.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: SingleChildScrollView(child: _buildStepPanel()),
              ),
              Expanded(child: _buildConversation()),
              if (_composerOpen) _buildComposer(),
              _buildDock(),
            ],
          ),
          if (_confirmSkipOpen) _buildConfirmSkipModal(),
          if (_confirmEndOpen) _buildConfirmEndModal(),
        ],
      ),
    );
  }

  Future<void> _reconnectGlasses() async {
    final glasses = widget.glassesService;
    if (await glasses.connectRealGlasses()) {
      widget.onShowToast('Connected to ${glasses.deviceName}');
    } else if (mounted) {
      widget.onShowToast(
        glasses.lastStatusNote ?? "Couldn't connect to your glasses.",
      );
    }
  }

  Widget _buildTopBar() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave session',
            onPressed: () => setState(() => _confirmEndOpen = true),
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipe.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                Text(
                  _formatElapsed(_elapsedSeconds),
                  style: textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: widget.glassesService,
            builder: (context, _) {
              final glasses = widget.glassesService;
              final connected = glassesReady(
                glasses,
                allowSimulated: widget.preferences.simulatedGlassesPhotos,
              );
              final connecting =
                  glasses.connectionState == GlassesConnectionState.connecting;
              return IconButton(
                tooltip: connecting
                    ? 'Connecting to your glasses…'
                    : connected
                    ? 'Take a photo with your glasses'
                    : 'Reconnect your glasses',
                onPressed: connecting
                    ? null
                    : connected
                    ? () => _triggerVisualCheck()
                    : _reconnectGlasses,
                icon: GlassesIcon(connected: connected || connecting),
              );
            },
          ),
          ListenableBuilder(
            listenable: widget.voiceController,
            builder: (context, _) {
              final muted = widget.voiceController.audioMuted;
              return IconButton(
                tooltip: muted ? 'Turn voice on' : 'Mute voice',
                onPressed: () => widget.voiceController.toggleAudioMuted(),
                icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                ),
              );
            },
          ),
          IconButton(
            tooltip: _isPaused ? 'Resume' : 'Pause',
            onPressed: () => _togglePause(),
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'type':
                  setState(() => _composerOpen = !_composerOpen);
                case 'mode':
                  _toggleListeningMode();
                case 'steps':
                  _openStepAndIngredientSheet();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'type',
                child: Text(_composerOpen ? 'Hide keyboard' : 'Type instead'),
              ),
              PopupMenuItem(
                value: 'mode',
                child: Text(
                  widget.voiceController.listeningMode ==
                          VoiceListeningMode.handsFree
                      ? 'Switch to tap to talk'
                      : 'Switch to hands-free',
                ),
              ),
              const PopupMenuItem(
                value: 'steps',
                child: Text('Steps & ingredients'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The pinned panel above the chat. Its raised background and shadow set
  /// it apart from the chat below; it flashes amber when the step changes.
  Widget _panel({required Widget child, bool highlighted = false}) {
    return Material(
      color: Colors.transparent,
      elevation: 3,
      shadowColor: CookTogetherTheme.ink.withValues(alpha: 0.25),
      child: AnimatedContainer(
        key: const ValueKey('step-panel'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          CookTogetherTheme.gutter,
          8,
          CookTogetherTheme.gutter,
          16,
        ),
        color: highlighted
            ? CookTogetherTheme.warningSoft
            : CookTogetherTheme.surface,
        child: child,
      ),
    );
  }

  Widget _buildStepHint() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.arrow_downward_rounded,
            size: 18,
            color: CookTogetherTheme.inkMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your current step is always here.',
              style: textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: _dismissStepHint, child: const Text('Got it')),
        ],
      ),
    );
  }

  /// Before step 1: the recipe and any ingredients not ticked on Get ready.
  Widget _buildOpeningPanel() {
    final textTheme = Theme.of(context).textTheme;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Before we start',
                  style: textTheme.labelMedium?.copyWith(
                    color: CookTogetherTheme.inkMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openStepAndIngredientSheet,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                label: const Text('All steps'),
              ),
            ],
          ),
          if (_isPaused) ...[_buildPausedBanner(), const SizedBox(height: 12)],
          Text(_recipe.name, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (_openingAsked.isEmpty)
            Text(
              'Everything is ticked. Say "let\'s start" or tap Start.',
              style: textTheme.bodyLarge,
            )
          else ...[
            // Tick one if it turns up after all.
            Text("You don't have", style: textTheme.titleSmall),
            for (final ingredient in _openingAsked)
              CheckRow(
                label: ingredient[0].toUpperCase() + ingredient.substring(1),
                detail: switch (widget.missingChoices[ingredient]?.use) {
                  _ when _checkedIngredients.contains(ingredient) => null,
                  final use? => 'Using $use',
                  null when widget.missingChoices.containsKey(ingredient) =>
                    'Leaving it out',
                  null => null,
                },
                checked: _checkedIngredients.contains(ingredient),
                onTap: () {
                  final before = _activeChoices.keys.toSet();
                  setState(() {
                    if (!_checkedIngredients.remove(ingredient)) {
                      _checkedIngredients.add(ingredient);
                    }
                  });
                  _followChoices(before);
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepPanel() {
    if (_opening) return _buildOpeningPanel();
    final textTheme = Theme.of(context).textTheme;
    final totalSteps = _recipe.steps.length;
    final suggestedSecs = _step.suggestedTimerSeconds;
    final suggestedLabel = _step.suggestedTimerLabel ?? _step.title;
    final showSuggestion =
        suggestedSecs != null && !_hasActiveTimerForCurrentStep;

    return _panel(
      highlighted: _stepHighlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One segment per step, filled up to the current one.
          Row(
            children: [
              for (int i = 0; i < totalSteps; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _currentStep
                          ? CookTogetherTheme.success
                          : CookTogetherTheme.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  'Step ${_currentStep + 1} of $totalSteps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: CookTogetherTheme.inkMuted,
                  ),
                ),
              ),
              const Spacer(),
              if (_currentStep > 0)
                IconButton(
                  tooltip: 'Previous step',
                  onPressed: () => _goToStep(_currentStep - 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              TextButton.icon(
                onPressed: _openStepAndIngredientSheet,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                label: const Text('All steps'),
              ),
            ],
          ),
          if (_isPaused) ...[_buildPausedBanner(), const SizedBox(height: 12)],
          if (!_stepHintSeen) _buildStepHint(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(_step.title, style: textTheme.headlineSmall),
              ),
              // A running timer is a small chip beside the title rather than
              // a panel, so the chat keeps its room (#93).
              for (final timer in _timers) ...[
                const SizedBox(width: 8),
                AnimatedOpacity(
                  key: ValueKey(timer.id),
                  opacity: _fadingTimerIds.contains(timer.id) ? 0 : 1,
                  duration: const Duration(milliseconds: 600),
                  onEnd: () {
                    if (_fadingTimerIds.contains(timer.id)) {
                      _removeTimer(timer.id);
                    }
                  },
                  child: _buildTimerChip(timer),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _step.instruction,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (_adaptedSteps.contains(_currentStep)) ...[
            const SizedBox(height: 4),
            Text('Changed for your ingredients', style: textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: CookTogetherTheme.inkMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_step.tip, style: textTheme.bodyMedium)),
            ],
          ),
          if (showSuggestion) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _startOrUpdateTimer(
                seconds: suggestedSecs,
                label: suggestedLabel,
              ),
              icon: const Icon(
                Icons.timer_outlined,
                color: CookTogetherTheme.warning,
              ),
              label: Text('Start ${_formatTimerLength(suggestedSecs)} timer'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimerLength(int seconds) {
    if (seconds < 60) return '$seconds sec';
    return '${(seconds / 60).ceil()} min';
  }

  /// The time left and a way to stop it. No pause: to wait longer, the
  /// user lets it run or asks for more time.
  Widget _buildTimerChip(CookingTimer timer) {
    final textTheme = Theme.of(context).textTheme;
    final finished = timer.isFinished;
    return Semantics(
      label: '${timer.label} timer',
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: CookTogetherTheme.warningSoft,
          borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              finished
                  ? Icons.notifications_active_rounded
                  : Icons.timer_outlined,
              size: 18,
              color: CookTogetherTheme.warning,
            ),
            const SizedBox(width: 4),
            Text(
              finished ? 'Done' : timer.formattedRemaining,
              style: textTheme.labelLarge?.copyWith(
                color: CookTogetherTheme.warning,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss timer',
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeTimer(timer.id),
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: CookTogetherTheme.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPausedBanner() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: CookTogetherTheme.warningSoft,
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Paused. Take your time.',
              style: textTheme.bodyLarge?.copyWith(
                color: CookTogetherTheme.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _togglePause(forcePause: false),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  /// The chat is grouped by step. A step's group starts with a divider
  /// ("Step 2: Chop the vegetables"), shown only for steps where something
  /// was said. Step announcements are already on the step panel, so they
  /// are not repeated as bubbles. With captions off, only the latest reply
  /// is shown.
  Widget _buildConversation() {
    final textTheme = Theme.of(context).textTheme;
    final transcript = widget.voiceController.partialTranscript;
    final thinking = _waitingForReply;
    final replies = _messages.where((m) => !m.isStepAnnouncement).toList();
    final items = widget.preferences.showCaptions
        ? replies
        : replies.isEmpty
        ? const <ChatMessage>[]
        : [replies.last];

    final children = <Widget>[];
    for (final (i, msg) in items.indexed) {
      final step = msg.stepIndex;
      final startsGroup = i == 0 || items[i - 1].stepIndex != step;
      if (startsGroup && step != null && widget.preferences.showCaptions) {
        children.add(_buildStepDivider(step));
      }
      children.add(
        msg.visionCapture != null
            ? _buildVisionCard(msg.visionCapture!, msg.text)
            : msg.sender == MessageSender.system
            ? _buildNote(msg)
            : _buildBubble(msg),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        12,
        CookTogetherTheme.gutter,
        12,
      ),
      children: [
        ...children,
        if (transcript.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('live-transcript'),
            child: _buildBubble(
              ChatMessage(
                id: 'live-transcript',
                sender: MessageSender.user,
                text: transcript,
                timestamp: DateTime.now(),
                stepIndex: _opening ? null : _currentStep,
              ),
            ),
          ),
        if (thinking)
          Padding(
            key: const ValueKey('chat-thinking'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Thinking…', style: textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        if (items.isEmpty && transcript.isEmpty && !thinking)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Ask me anything, like "how small is bite-sized?"',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _buildStepDivider(int index) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: CookTogetherTheme.line),
            borderRadius: BorderRadius.circular(CookTogetherTheme.radiusCard),
          ),
          child: Text(
            'Step ${index + 1}: ${_recipe.steps[index].title}',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  /// A note from the app, such as steps changed for a missing ingredient.
  Widget _buildNote(ChatMessage msg) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.edit_note_rounded,
            size: 20,
            color: CookTogetherTheme.inkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg.text, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.sender == MessageSender.user;
    // Quieter than the step panel: page-coloured replies, smaller text.
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: CookTogetherTheme.ink);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFFEFEADF)
              : CookTogetherTheme.background,
          border: isUser ? null : Border.all(color: CookTogetherTheme.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(msg.text, style: style),
      ),
    );
  }

  Widget _buildVisionCard(VisionCapture capture, String aiReply) {
    final textTheme = Theme.of(context).textTheme;
    final statusColor = switch (capture.status) {
      VisualCheckStatus.done => CookTogetherTheme.success,
      VisualCheckStatus.notYet => CookTogetherTheme.warning,
      VisualCheckStatus.unsure => CookTogetherTheme.inkMuted,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusCard),
        border: Border.all(color: CookTogetherTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 20, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  capture.status.badgeLabel,
                  style: textTheme.titleSmall?.copyWith(color: statusColor),
                ),
              ),
              Text('Step ${capture.stepIndex + 1}', style: textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(aiReply, style: textTheme.bodyLarge?.copyWith(fontSize: 15)),
          const SizedBox(height: 8),
          Text(
            'A camera can\'t confirm food is cooked or safe. Check it yourself too.',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        0,
        CookTogetherTheme.gutter,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: _handleUserUtterance,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Type a question or command',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: CookTogetherTheme.ink,
              foregroundColor: Colors.white,
            ),
            tooltip: 'Send',
            onPressed: () => _handleUserUtterance(_textController.text),
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDock() {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.voiceController,
      builder: (context, _) {
        final state = widget.voiceController.activityState;
        final mode = widget.voiceController.listeningMode;
        final waitingForWake = widget.voiceController.waitingForWakeWord;

        final orbColor = switch (state) {
          VoiceActivityState.listening when !waitingForWake =>
            CookTogetherTheme.success,
          VoiceActivityState.listening => const Color(0xFF55664F),
          VoiceActivityState.capturingVision ||
          VoiceActivityState.thinking => CookTogetherTheme.warning,
          VoiceActivityState.speaking => CookTogetherTheme.ink,
          VoiceActivityState.idle => const Color(0xFF55664F),
        };

        final statusLabel = _isPaused
            ? 'Paused'
            : switch (state) {
                VoiceActivityState.listening when waitingForWake =>
                  'Say "Hey Cooky" or tap the mic',
                VoiceActivityState.listening => 'Listening…',
                VoiceActivityState.capturingVision =>
                  widget.voiceController.statusHint ??
                      'Looking through your glasses…',
                VoiceActivityState.thinking => 'Thinking…',
                VoiceActivityState.speaking => 'Speaking…',
                VoiceActivityState.idle =>
                  widget.voiceController.listeningStopped
                      ? 'Tap the mic when you need me'
                      : mode == VoiceListeningMode.handsFree
                      ? (_opening
                            ? 'Say "Hey Cooky, let\'s start"'
                            : 'Say "Hey Cooky" or tap the mic')
                      : 'Tap the mic to talk',
              };

        return Container(
          padding: const EdgeInsets.fromLTRB(
            CookTogetherTheme.gutter,
            10,
            CookTogetherTheme.gutter,
            14,
          ),
          decoration: const BoxDecoration(
            color: CookTogetherTheme.surface,
            border: Border(top: BorderSide(color: CookTogetherTheme.line)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      // A tap on the disabled button says why it is off.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isPaused || _opening
                            ? () => widget.onShowToast(
                                _isPaused
                                    ? 'Resume the session first.'
                                    : 'Check works once you start step 1.',
                              )
                            : null,
                        child: SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            // Nothing to check before step 1.
                            onPressed: _isPaused || _opening
                                ? null
                                : () => _triggerVisualCheck(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                            // Shrink rather than wrap on narrow phones with
                            // large text.
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Check', maxLines: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildMicOrb(state, orbColor),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _isPaused
                              ? null
                              : _opening
                              ? () => _startCooking()
                              : _nextOrFinish,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _opening
                                        ? 'Start'
                                        : _isLastStep
                                        ? 'Finish'
                                        : 'Next',
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _isLastStep && !_opening
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMicOrb(VoiceActivityState state, Color orbColor) {
    return Semantics(
      button: true,
      label: _isPaused ? 'Resume session' : 'Talk to CookTogether',
      child: GestureDetector(
        onTap: () async {
          if (_isPaused) {
            _togglePause(forcePause: false);
            return;
          }
          final result = await widget.voiceController.tapMic();
          // Never stand in for the user with a made-up phrase: say why the
          // microphone can't be used and point to typing instead.
          if (result == MicTapResult.unavailable && mounted) {
            widget.onShowToast(
              "I can't use the microphone. Check microphone permission for "
              'CookTogether, or type below.',
            );
          }
        },
        child: AnimatedBuilder(
          animation: _orbPulseController,
          builder: (context, child) {
            final pulsing =
                (state == VoiceActivityState.listening &&
                    !widget.voiceController.waitingForWakeWord) ||
                state == VoiceActivityState.speaking;
            return Transform.scale(
              scale: pulsing ? 1.0 + (_orbPulseController.value * 0.06) : 1.0,
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: orbColor,
              boxShadow: [
                BoxShadow(
                  color: orbColor.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              switch (state) {
                VoiceActivityState.capturingVision => Icons.camera_alt_rounded,
                VoiceActivityState.speaking => Icons.graphic_eq_rounded,
                VoiceActivityState.thinking => Icons.more_horiz_rounded,
                _ => Icons.mic_rounded,
              },
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmSkipModal() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Material(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Skip this step without checking?',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Check takes a photo and tells you if it looks ready.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Check first',
                onPressed: () {
                  setState(() => _confirmSkipOpen = false);
                  _triggerVisualCheck();
                },
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() => _confirmSkipOpen = false);
                    _moveOn();
                  },
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmEndModal() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Material(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Leave this session?', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Pause it to pick up where you left off from Home. '
                'Ending it doesn\'t save your progress.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Pause and leave for now',
                onPressed: () {
                  setState(() => _confirmEndOpen = false);
                  if (!_isPaused) {
                    _togglePause(forcePause: true);
                    _pausedByLeaving = true;
                  }
                  widget.onPauseAndLeave();
                },
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: widget.onExitToHome,
                  child: const Text('End session'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => setState(() => _confirmEndOpen = false),
                  child: const Text('Stay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
