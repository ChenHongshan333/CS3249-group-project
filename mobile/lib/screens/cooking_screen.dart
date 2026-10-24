import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../camera/phone_camera.dart';
import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';
import '../models/user_preferences.dart';
import '../services/assistant_service.dart';
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
  final Set<String> initialCheckedIngredients;
  final VoiceListeningMode initialListeningMode;
  final Set<String> acceptedSwapIds;
  final void Function({
    required int elapsedSeconds,
    required int stepsCompleted,
    required int visualChecksCount,
  })
  onFinishCooking;
  final VoidCallback onExitToHome;
  final ValueChanged<String> onShowToast;

  const CookingScreen({
    super.key,
    required this.recipe,
    required this.preferences,
    required this.glassesService,
    required this.assistantService,
    required this.voiceController,
    this.phoneCamera,
    required this.initialCheckedIngredients,
    required this.initialListeningMode,
    this.acceptedSwapIds = const {},
    required this.onFinishCooking,
    required this.onExitToHome,
    required this.onShowToast,
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

  // The short chat before step 1 (docs/api.md, "The opening conversation").
  bool _opening = true;
  int _openingTurns = 0;
  final DateTime _openingStartedAt = DateTime.now();
  late final List<String> _openingAsked;

  // An offer from the last reply, such as "Would you like a timer?". It is
  // sent back once with the next question so "please" can accept it.
  AssistantAction? _pendingOffer;

  late Set<String> _checkedIngredients;
  final List<ChatMessage> _messages = [];
  final List<CookingTimer> _timers = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _clockTimer;
  late final AnimationController _orbPulseController;

  RecipeStep get _step => widget.recipe.steps[_currentStep];

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

    // Fall back to the Mock Device Kit, unless the user chose real glasses
    // (those reconnect on their own).
    if (!widget.glassesService.isConnected &&
        !widget.glassesService.usingRealGlasses) {
      widget.glassesService.initializeAndPairMockDevice();
    }

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused) return;
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
            if (nextRemaining == 0) {
              widget.onShowToast(
                'Timer finished: ${t.label} — check your food!',
              );
              _appendAiMessage(
                'Your ${t.label.toLowerCase()} timer just finished! Take a look or say "check this step" so we can inspect it together.',
              );
            }
          }
        }
      });
    });

    // A fixed first line, so every participant hears the same opening.
    _openingAsked = widget.recipe.ingredients
        .where((i) => !_checkedIngredients.contains(i))
        .toList();
    final openingText = _openingLine();
    _messages.add(
      ChatMessage(
        id: 'init-0',
        sender: MessageSender.ai,
        text: openingText,
        timestamp: DateTime.now(),
      ),
    );
    _initializeVoiceAndAnnounce(openingText);
  }

  String _openingLine() {
    final name = widget.recipe.name;
    final missing = _openingAsked;
    if (missing.isEmpty) {
      return "Today we're making $name, right? You've got everything, "
          "so say 'let's start' when you're ready.";
    }
    final listed = missing.length == 1
        ? missing.first
        : '${missing.sublist(0, missing.length - 1).join(', ')} and ${missing.last}';
    return "Today we're making $name, right? Have you got the $listed?";
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
        'missing': widget.recipe.ingredients
            .where((i) => !_checkedIngredients.contains(i))
            .toList(),
      },
    );
  }

  void _startCooking({String? lead}) {
    if (!_opening) return;
    _goToStep(0, lead: lead);
  }

  Future<void> _initializeVoiceAndAnnounce(String openingText) async {
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
      data: {'recipeId': widget.recipe.id, 'condition': 'glasses_cui'},
    );
    for (final swap in widget.recipe.swaps) {
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
  void dispose() {
    _clockTimer?.cancel();
    _orbPulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    widget.voiceController.onFinalUtterance = null;
    widget.voiceController.shutdownSession();
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

  void _appendUserMessage(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'usr-${DateTime.now().microsecondsSinceEpoch}',
          sender: MessageSender.user,
          text: text,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();
  }

  void _appendAiMessage(
    String text, {
    VisionCapture? visionCapture,
    bool isStepAnnouncement = false,
    int? stepIndex,
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
          stepIndex: stepIndex,
        ),
      );
    });
    _scrollToBottom();
    widget.voiceController.speak(
      text,
      voiceGuidanceEnabled: widget.preferences.voiceGuidance,
    );
  }

  void _startOrUpdateTimer({required int seconds, required String label}) {
    setState(() {
      final existingIdx = _timers.indexWhere((t) => t.label == label);
      final timer = CookingTimer(
        id: 'tmr-${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        totalSeconds: seconds,
        remainingSeconds: seconds,
        isRunning: true,
      );
      if (existingIdx >= 0) {
        _timers[existingIdx] = timer;
      } else {
        _timers.add(timer);
      }
    });
    final mins = (seconds / 60).ceil();
    widget.onShowToast('$label started ($mins min)');
  }

  void _goToStep(int targetStep, {bool fromVoice = false, String? lead}) {
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
    _endOpening();
    _pendingOffer = null;
    if (targetStep >= widget.recipe.steps.length) {
      _completeSession();
      return;
    }
    final clamped = targetStep.clamp(0, widget.recipe.steps.length - 1);
    setState(() {
      _currentStep = clamped;
    });
    final nextStepObj = widget.recipe.steps[clamped];
    final announcement =
        'Step ${clamped + 1}: ${nextStepObj.title}. ${nextStepObj.instruction}';
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
      stepsCompleted: widget.recipe.steps.length,
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
      widget.voiceController.setActivityState(
        VoiceActivityState.capturingVision,
        hint: 'Taking a photo with your glasses…',
      );
      try {
        return await glasses.captureFrame(
          recipe: widget.recipe,
          stepIndex: _currentStep,
          userPrompt: promptText,
        );
      } on GlassesCaptureException catch (e) {
        if (mounted) {
          _appendAiMessage(
            '${e.message} Let\'s use your phone camera instead.',
          );
        }
      }
    }
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
    final step = widget.recipe.steps[_currentStep];
    return VisionCapture(
      id: 'phone-${DateTime.now().millisecondsSinceEpoch}',
      recipeId: widget.recipe.id,
      stepIndex: _currentStep,
      source: 'phone',
      deviceName: 'Phone camera',
      sceneDescription: step.visionSceneDescription,
      recipeIcon: widget.recipe.icon,
      recipeTone: widget.recipe.tone,
      jpegBytes: bytes,
      base64Jpeg: base64Encode(bytes),
      capturedAt: DateTime.now(),
      userQuestion: promptText,
    );
  }

  Future<void> _triggerVisualCheck({String? userQuestion}) async {
    if (_opening) {
      _appendAiMessage("Let's start the first step, then I can take a look.");
      return;
    }
    // A photo check changes the subject; a later "sure" isn't an answer
    // to an offer made before it.
    _pendingOffer = null;
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
    final promptText = userQuestion ?? 'Check this step through my glasses';
    if (userQuestion == null) {
      _appendUserMessage('Check this step 🕶️');
    }

    final startTime = DateTime.now();
    final capture = await _takeStepPhoto(promptText);
    if (capture == null) {
      widget.voiceController.setActivityState(VoiceActivityState.idle);
      return;
    }

    widget.voiceController.setActivityState(
      VoiceActivityState.thinking,
      hint: 'Analyzing visual view with CookTogether AI…',
    );

    final response = await widget.assistantService.checkStepWithVision(
      sessionId: _sessionId,
      recipe: widget.recipe,
      stepIndex: _currentStep,
      visionCapture: capture,
      userQuestion: userQuestion,
    );

    if (!mounted) return;
    if (response.isError) {
      _appendAiMessage(response.reply);
      return;
    }
    setState(() => _visualChecksCount++);

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
      },
    );
  }

  Future<void> _handleUserUtterance(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    _appendUserMessage(text);
    _textController.clear();

    final intent = VoiceIntentParser.parse(
      text,
      defaultStepTimerSeconds: _step.suggestedTimerSeconds,
      defaultStepTimerLabel: _step.suggestedTimerLabel ?? _step.title,
    );

    if (_opening && !_worksInOpening.contains(intent.type)) {
      final lower = text.toLowerCase();
      if (intent.type == VoiceIntentType.nextStep ||
          RegExp(
            r"^(let'?s (start|go|cook)|start( cooking)?|i'?m ready|ready)[.!?]*$",
          ).hasMatch(lower)) {
        _startCooking();
      } else {
        await _askAssistant(text);
      }
      return;
    }

    // A command the app handles itself replaces any open offer.
    if (intent.type != VoiceIntentType.generalQuestion) _pendingOffer = null;

    switch (intent.type) {
      case VoiceIntentType.nextStep:
        if (_currentStep == widget.recipe.steps.length - 1) {
          _completeSession();
        } else {
          _goToStep(_currentStep + 1, fromVoice: true);
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
        _startOrUpdateTimer(seconds: seconds, label: label);
        final mins = (seconds / 60).ceil();
        _appendAiMessage(
          'I set a $mins-minute timer for ${label.toLowerCase()}. Keep going—I will let you know when it finishes.',
        );
        return;

      case VoiceIntentType.pauseTimer:
        if (_timers.isEmpty) {
          _appendAiMessage('There is no active timer running right now.');
        } else {
          setState(() {
            for (int i = 0; i < _timers.length; i++) {
              _timers[i] = _timers[i].copyWith(isRunning: false);
            }
          });
          _appendAiMessage('I paused your timer.');
        }
        return;

      case VoiceIntentType.cancelTimer:
        setState(() => _timers.clear());
        _appendAiMessage('I cleared your kitchen timer.');
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
    widget.voiceController.setActivityState(
      VoiceActivityState.thinking,
      hint: 'Thinking…',
    );
    final offer = _pendingOffer;
    _pendingOffer = null;
    final startTime = DateTime.now();
    final response = await widget.assistantService.askQuestion(
      sessionId: _sessionId,
      recipe: widget.recipe,
      stepIndex: _currentStep,
      question: text,
      history: _messages,
      acceptedSwaps: widget.acceptedSwapIds.toList(),
      phase: _opening ? 'opening' : 'cooking',
      ingredients: {
        for (final i in widget.recipe.ingredients)
          i: _checkedIngredients.contains(i),
      },
      pendingOffer: offer,
    );
    if (!mounted) return;
    if (_opening) _openingTurns++;
    // After an error the question was never answered, so the offer stands.
    _pendingOffer = response.isError ? offer : response.offer;

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
    if (!leadsIn) _appendAiMessage(response.reply);
    if (action != null) {
      _runAction(action, lead: leadsIn ? response.reply : null);
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
  void _runAction(AssistantAction action, {String? lead}) {
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
      case 'tick_ingredient' when _opening:
        final names = {...action.names, ?action.name};
        setState(
          () => _checkedIngredients.addAll(
            names.where(widget.recipe.ingredients.contains),
          ),
        );
      default:
        // Doesn't fit the current phase; the backend should not send it.
        if (lead != null) _appendAiMessage(lead);
    }
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
          recipe: widget.recipe,
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

  bool get _hasActiveTimerForCurrentStep {
    final label = _step.suggestedTimerLabel ?? _step.title;
    return _timers.any((t) => t.label == label);
  }

  bool get _isLastStep => _currentStep == widget.recipe.steps.length - 1;

  void _nextOrFinish() {
    if (_isLastStep) {
      _completeSession();
    } else {
      _goToStep(_currentStep + 1);
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
    // The back gesture asks before leaving, like the close button; with the
    // question open, back answers "stay".
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _confirmEndOpen = !_confirmEndOpen);
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
          if (_confirmEndOpen) _buildConfirmEndModal(),
        ],
      ),
    );
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
                  widget.recipe.name,
                  maxLines: 1,
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

  /// Before step 1: the recipe and any ingredients not ticked on Get ready.
  Widget _buildOpeningPanel() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        8,
        CookTogetherTheme.gutter,
        16,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CookTogetherTheme.line)),
      ),
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
          Text(widget.recipe.name, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (_openingAsked.isEmpty)
            Text(
              'Everything is ticked. Say "let\'s start" or tap Start.',
              style: textTheme.bodyLarge,
            )
          else ...[
            Text('Still to check', style: textTheme.titleSmall),
            for (final ingredient in _openingAsked)
              CheckRow(
                label: ingredient[0].toUpperCase() + ingredient.substring(1),
                checked: _checkedIngredients.contains(ingredient),
                onTap: () => setState(() {
                  if (!_checkedIngredients.remove(ingredient)) {
                    _checkedIngredients.add(ingredient);
                  }
                }),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepPanel() {
    if (_opening) return _buildOpeningPanel();
    final textTheme = Theme.of(context).textTheme;
    final totalSteps = widget.recipe.steps.length;
    final suggestedSecs = _step.suggestedTimerSeconds;
    final suggestedLabel = _step.suggestedTimerLabel ?? _step.title;
    final showSuggestion =
        suggestedSecs != null && !_hasActiveTimerForCurrentStep;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        8,
        CookTogetherTheme.gutter,
        16,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CookTogetherTheme.line)),
      ),
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
              Expanded(
                child: Text(
                  'Step ${_currentStep + 1} of $totalSteps',
                  style: textTheme.labelMedium?.copyWith(
                    color: CookTogetherTheme.inkMuted,
                  ),
                ),
              ),
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
          Text(_step.title, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            _step.instruction,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
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
          for (final timer in _timers) ...[
            const SizedBox(height: 12),
            _buildTimerRow(timer),
          ],
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

  Widget _buildTimerRow(CookingTimer timer) {
    final textTheme = Theme.of(context).textTheme;
    final finished = timer.isFinished;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: CookTogetherTheme.warningSoft,
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
      ),
      child: Row(
        children: [
          Icon(
            finished
                ? Icons.notifications_active_rounded
                : Icons.timer_outlined,
            color: CookTogetherTheme.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              timer.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyLarge,
            ),
          ),
          Text(
            finished ? 'Done' : timer.formattedRemaining,
            style: textTheme.headlineSmall?.copyWith(
              color: CookTogetherTheme.warning,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!finished)
            IconButton(
              tooltip: timer.isRunning ? 'Pause timer' : 'Resume timer',
              onPressed: () => setState(() {
                final idx = _timers.indexWhere((t) => t.id == timer.id);
                if (idx >= 0) {
                  _timers[idx] = timer.copyWith(isRunning: !timer.isRunning);
                }
              }),
              icon: Icon(
                timer.isRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          IconButton(
            tooltip: 'Dismiss timer',
            onPressed: () =>
                setState(() => _timers.removeWhere((t) => t.id == timer.id)),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
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

  /// Step announcements are already on the step panel, so they show as a
  /// small marker instead of a repeated bubble. With captions off, only the
  /// latest reply is shown.
  Widget _buildConversation() {
    final textTheme = Theme.of(context).textTheme;
    var items = _messages;
    if (!widget.preferences.showCaptions) {
      final replies = _messages.where((m) => !m.isStepAnnouncement);
      items = replies.isEmpty ? const [] : [replies.last];
    }
    final hasReplies = items.any((m) => !m.isStepAnnouncement);
    // A step marker only earns its place when replies follow it.
    bool repliesAfter(int i) =>
        items.skip(i + 1).takeWhile((m) => !m.isStepAnnouncement).isNotEmpty;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        12,
        CookTogetherTheme.gutter,
        12,
      ),
      children: [
        for (final (i, msg) in items.indexed)
          if (msg.isStepAnnouncement)
            if (repliesAfter(i)) _buildStepMarker(msg) else const SizedBox()
          else if (msg.visionCapture != null)
            _buildVisionCard(msg.visionCapture!, msg.text)
          else
            _buildBubble(msg),
        if (!hasReplies)
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

  Widget _buildStepMarker(ChatMessage msg) {
    final index = msg.stepIndex ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Step ${index + 1} · ${widget.recipe.steps[index].title}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.sender == MessageSender.user;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFEFEADF) : CookTogetherTheme.surface,
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
        final partial = widget.voiceController.partialTranscript;

        final orbColor = switch (state) {
          VoiceActivityState.listening => CookTogetherTheme.success,
          VoiceActivityState.capturingVision ||
          VoiceActivityState.thinking => CookTogetherTheme.warning,
          VoiceActivityState.speaking => CookTogetherTheme.ink,
          VoiceActivityState.idle => const Color(0xFF55664F),
        };

        final statusLabel = partial.isNotEmpty
            ? '"$partial…"'
            : _isPaused
            ? 'Paused'
            : switch (state) {
                VoiceActivityState.listening => 'Listening…',
                VoiceActivityState.capturingVision =>
                  'Looking through your glasses…',
                VoiceActivityState.thinking => 'Thinking…',
                VoiceActivityState.speaking => 'Speaking…',
                VoiceActivityState.idle =>
                  mode == VoiceListeningMode.handsFree
                      ? (_opening
                            ? 'Say "let\'s start" or ask a question'
                            : 'Say "next step" or ask a question')
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: partial.isNotEmpty ? CookTogetherTheme.ink : null,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          // Nothing to check before step 1.
                          onPressed: _isPaused || _opening
                              ? null
                              : () => _triggerVisualCheck(),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Check'),
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
                                child: Text(
                                  _opening
                                      ? 'Start'
                                      : _isLastStep
                                      ? 'Finish'
                                      : 'Next',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
        onTap: () {
          if (_isPaused) {
            _togglePause(forcePause: false);
            return;
          }
          if (widget.voiceController.speechAvailable) {
            widget.voiceController.toggleTapToSpeak();
          } else {
            // Simulator, web, or tests without a mic: send a sample question
            // so the conversation flow can still be demonstrated.
            _handleUserUtterance(
              _opening
                  ? "Let's start."
                  : 'Does this look chopped small enough?',
            );
          }
        },
        child: AnimatedBuilder(
          animation: _orbPulseController,
          builder: (context, child) {
            final pulsing =
                state == VoiceActivityState.listening ||
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
                'Your progress on this recipe won\'t be saved.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Leave', onPressed: widget.onExitToHome),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() => _confirmEndOpen = false);
                    _togglePause(forcePause: true);
                  },
                  child: const Text('Stay and pause'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
