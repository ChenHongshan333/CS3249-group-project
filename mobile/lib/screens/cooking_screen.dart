import 'dart:async';

import 'package:flutter/material.dart';

import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';
import '../models/user_preferences.dart';
import '../services/assistant_service.dart';
import '../services/voice_controller.dart';
import '../services/voice_intent_parser.dart';
import '../theme/app_theme.dart';
import 'step_ingredient_sheet.dart';

/// Refined Voice-First & Meta Glasses Conversational Cooking Workspace.
///
/// Layout hierarchy:
/// 1. Top Header & Smart Contextual Timers strip
/// 2. Pinned Glanceable Step Card (tap to open [StepIngredientSheet]) +
///    Compact Meta Glasses POV Pill (expands when capturing a frame)
/// 3. Rich Conversational Stream in the center with inline Vision Assessment Cards
/// 4. Prominent Voice Orb & minimal Hands-Free dock at the bottom
class CookingScreen extends StatefulWidget {
  final Recipe recipe;
  final UserPreferences preferences;
  final GlassesService glassesService;
  final AssistantService assistantService;
  final VoiceController voiceController;
  final Set<String> initialCheckedIngredients;
  final VoiceListeningMode initialListeningMode;
  final void Function({
    required int elapsedSeconds,
    required int stepsCompleted,
    required int visualChecksCount,
  }) onFinishCooking;
  final VoidCallback onExitToHome;
  final ValueChanged<String> onShowToast;

  const CookingScreen({
    super.key,
    required this.recipe,
    required this.preferences,
    required this.glassesService,
    required this.assistantService,
    required this.voiceController,
    required this.initialCheckedIngredients,
    required this.initialListeningMode,
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
  bool _glassesPreviewExpanded = false;

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

    // Ensure Meta glasses Mock Device Kit is ready
    if (!widget.glassesService.isConnected) {
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
              widget.onShowToast('Timer finished: ${t.label} — check your food!');
              _appendAiMessage(
                'Your ${t.label.toLowerCase()} timer just finished! Take a look or say "check this step" so we can inspect it together.',
              );
            }
          }
        }
      });
    });

    // Initial welcome + Step 1 announcement
    final openingText =
        'Let\'s make ${widget.recipe.name.toLowerCase()}! Step 1: ${_step.instruction}';
    _messages.add(
      ChatMessage(
        id: 'init-0',
        sender: MessageSender.ai,
        text: openingText,
        timestamp: DateTime.now(),
        isStepAnnouncement: true,
        stepIndex: 0,
      ),
    );
    _initializeVoiceAndAnnounce(openingText);
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

  void _goToStep(int targetStep, {bool fromVoice = false}) {
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
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
      announcement,
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

  Future<void> _triggerVisualCheck({String? userQuestion}) async {
    if (_isPaused) {
      widget.onShowToast('Resume the session first.');
      return;
    }
    final promptText = userQuestion ?? 'Check this step through my glasses';
    if (userQuestion == null) {
      _appendUserMessage('Check this step 🕶️');
    }

    setState(() {
      _glassesPreviewExpanded = true;
    });
    widget.voiceController.setActivityState(
      VoiceActivityState.capturingVision,
      hint: 'Capturing POV snapshot from Meta glasses…',
    );

    final startTime = DateTime.now();
    final capture = await widget.glassesService.captureFrame(
      recipe: widget.recipe,
      stepIndex: _currentStep,
      userPrompt: promptText,
    );

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
    setState(() {
      _visualChecksCount++;
      _glassesPreviewExpanded = false;
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
        widget.voiceController.setActivityState(
          VoiceActivityState.thinking,
          hint: 'Thinking…',
        );
        final startTime = DateTime.now();
        final response = await widget.assistantService.askQuestion(
          sessionId: _sessionId,
          recipe: widget.recipe,
          stepIndex: _currentStep,
          question: text,
          history: _messages,
        );
        if (!mounted) return;
        _appendAiMessage(response.reply);
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        widget.assistantService.logEvent(
          sessionId: _sessionId,
          type: 'question',
          data: {
            'step': _currentStep,
            'question': text,
            'reply': response.reply,
            'ms': elapsedMs,
          },
        );
        return;
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
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.76,
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(),
            _buildSmartTimerStrip(),
            _buildPinnedGlanceableStepCard(),
            if (_isPaused) _buildPausedBanner(),
            Expanded(child: _buildConversationalStream()),
            _buildBottomVoiceOrbDock(),
          ],
        ),
        if (_confirmEndOpen) _buildConfirmEndModal(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: CookTogetherTheme.cream,
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => setState(() => _confirmEndOpen = true),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CookTogetherTheme.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: CookTogetherTheme.border),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 19,
                color: CookTogetherTheme.ink,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOW COOKING · STEP ${_currentStep + 1}/${widget.recipe.steps.length}',
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: CookTogetherTheme.warmOrange,
                    letterSpacing: 1.3,
                  ),
                ),
                Text(
                  widget.recipe.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: CookTogetherTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CookTogetherTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: CookTogetherTheme.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatElapsed(_elapsedSeconds),
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: CookTogetherTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartTimerStrip() {
    final suggestedSecs = _step.suggestedTimerSeconds;
    final suggestedLabel = _step.suggestedTimerLabel ?? _step.title;
    final showSuggestion =
        suggestedSecs != null && !_hasActiveTimerForCurrentStep;

    if (_timers.isEmpty && !showSuggestion) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          for (final timer in _timers)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: timer.isFinished
                    ? CookTogetherTheme.toneRedBg
                    : const Color(0xFFFFF0D6),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: timer.isFinished
                      ? CookTogetherTheme.terracottaRed
                      : const Color(0xFFE7BD7C),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    timer.isFinished
                        ? Icons.notifications_active_rounded
                        : Icons.timer_rounded,
                    size: 17,
                    color: timer.isFinished
                        ? CookTogetherTheme.terracottaRed
                        : const Color(0xFFA66822),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.label,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: CookTogetherTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: timer.progress,
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(alpha: 0.6),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              timer.isFinished
                                  ? CookTogetherTheme.terracottaRed
                                  : CookTogetherTheme.warmOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    timer.isFinished ? 'DONE' : timer.formattedRemaining,
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 15,
                      color: timer.isFinished
                          ? CookTogetherTheme.terracottaRed
                          : const Color(0xFFA66822),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!timer.isFinished)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: timer.isRunning ? 'Pause timer' : 'Resume timer',
                      onPressed: () {
                        setState(() {
                          final idx = _timers.indexWhere(
                            (item) => item.id == timer.id,
                          );
                          if (idx >= 0) {
                            _timers[idx] = timer.copyWith(
                              isRunning: !timer.isRunning,
                            );
                          }
                        });
                      },
                      icon: Icon(
                        timer.isRunning
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 20,
                        color: const Color(0xFFA66822),
                      ),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss timer',
                    onPressed: () {
                      setState(() {
                        _timers.removeWhere((item) => item.id == timer.id);
                      });
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: CookTogetherTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          if (showSuggestion)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _startOrUpdateTimer(
                seconds: suggestedSecs,
                label: suggestedLabel,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surfaceWarm,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9DFCC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: CookTogetherTheme.warmOrange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Suggested timer: $suggestedLabel (${(suggestedSecs / 60).ceil()} min)',
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFA4773A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CookTogetherTheme.toneOrangeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Start timer',
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: CookTogetherTheme.warmOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPinnedGlanceableStepCard() {
    final totalSteps = widget.recipe.steps.length;
    final progress = (_currentStep + 1) / totalSteps;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListenableBuilder(
        listenable: widget.glassesService,
        builder: (context, _) {
          final isCapturing = widget.glassesService.isCapturing;
          final showExpandedPov = _glassesPreviewExpanded || isCapturing;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CookTogetherTheme.surfaceWarm,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE9DFCC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D28332A),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Step progress + Meta Glasses POV pill + Expandable Steps button
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CookTogetherTheme.toneGreenBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'STEP ${_currentStep + 1} OF $totalSteps',
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: CookTogetherTheme.deepHerbGreen,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Compact Meta Glasses POV Pill
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _glassesPreviewExpanded =
                                  !_glassesPreviewExpanded;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF28332A),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: isCapturing
                                        ? CookTogetherTheme.warmOrange
                                        : CookTogetherTheme.herbGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    isCapturing
                                        ? 'SNAP IN PROGRESS…'
                                        : 'META GLASSES POV',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CookTogetherTheme.bodyStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: _openStepAndIngredientSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: CookTogetherTheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: CookTogetherTheme.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.format_list_bulleted_rounded,
                              size: 14,
                              color: CookTogetherTheme.ink,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Steps & Items',
                              style: CookTogetherTheme.bodyStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: CookTogetherTheme.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE5E9DD),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      CookTogetherTheme.herbGreen,
                    ),
                  ),
                ),
                if (showExpandedPov) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF2B392D),
                          Color(0xFF425744),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.recipe.icon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.glassesService.deviceName} · ${widget.glassesService.batteryLevel}%',
                                style: CookTogetherTheme.bodyStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFB5E49C),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _step.visionSceneDescription,
                                style: CookTogetherTheme.bodyStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: isCapturing
                              ? null
                              : () => _triggerVisualCheck(),
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: Text(
                            'Snap',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _step.title,
                            style: CookTogetherTheme.headingStyle(fontSize: 20),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _step.instruction,
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: CookTogetherTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFEEE6D7)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 15,
                        color: CookTogetherTheme.warmOrange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _step.tip,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 11,
                            color: const Color(0xFFA4773A),
                          ),
                        ),
                      ),
                      if (_currentStep > 0)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _goToStep(_currentStep - 1),
                          child: Text(
                            'Prev',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: CookTogetherTheme.muted,
                            ),
                          ),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          if (_currentStep == widget.recipe.steps.length - 1) {
                            _completeSession();
                          } else {
                            _goToStep(_currentStep + 1);
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentStep == widget.recipe.steps.length - 1
                                  ? 'Finish'
                                  : 'Next step',
                              style: CookTogetherTheme.bodyStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: CookTogetherTheme.deepHerbGreen,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: CookTogetherTheme.deepHerbGreen,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPausedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2DC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_filled_rounded,
            size: 19,
            color: Color(0xFFAE732D),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Session paused — take your time. Say "resume" or tap Resume below.',
              style: CookTogetherTheme.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFAE732D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationalStream() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg.sender == MessageSender.user;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (msg.visionCapture != null)
                _buildInlineVisionCard(msg.visionCapture!, msg.text)
              else
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFFF7E9DC)
                        : const Color(0xFFEEF4E7),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(15),
                      topRight: const Radius.circular(15),
                      bottomLeft: Radius.circular(isUser ? 15 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUser
                                ? Icons.record_voice_over_rounded
                                : Icons.auto_awesome_rounded,
                            size: 12,
                            color: isUser
                                ? const Color(0xFF815830)
                                : CookTogetherTheme.deepHerbGreen,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isUser ? 'YOU' : 'COOKTOGETHER AI',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isUser
                                  ? const Color(0xFF815830)
                                  : CookTogetherTheme.deepHerbGreen,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.text,
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 13,
                          color: isUser
                              ? const Color(0xFF6B4623)
                              : const Color(0xFF364B2E),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineVisionCard(VisionCapture capture, String aiReply) {
    final statusColor = switch (capture.status) {
      VisualCheckStatus.done => CookTogetherTheme.herbGreen,
      VisualCheckStatus.notYet => CookTogetherTheme.warmOrange,
      VisualCheckStatus.unsure => const Color(0xFFB98D22),
    };
    final statusBg = switch (capture.status) {
      VisualCheckStatus.done => CookTogetherTheme.toneGreenBg,
      VisualCheckStatus.notYet => CookTogetherTheme.toneOrangeBg,
      VisualCheckStatus.unsure => CookTogetherTheme.toneYellowBg,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6D4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28332A),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_rounded,
                        size: 12,
                        color: Color(0xFFB5E49C),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          capture.deviceName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  capture.status.badgeLabel.toUpperCase(),
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Captured POV Frame / Scene Preview
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: CookTogetherTheme.toneBackground(capture.recipeTone),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  capture.recipeIcon,
                  style: const TextStyle(fontSize: 34),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CAPTURED GLASSES VIEW · STEP ${capture.stepIndex + 1}',
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: CookTogetherTheme.warmOrange,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        capture.sceneDescription,
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CookTogetherTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            aiReply,
            style: CookTogetherTheme.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CookTogetherTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Visual reference only: a camera cannot guarantee food safety or doneness—check manually before moving on.',
            style: CookTogetherTheme.bodyStyle(
              fontSize: 10,
              color: CookTogetherTheme.muted,
            ),
          ),
          if (capture.status == VisualCheckStatus.done) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CookTogetherTheme.herbGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                onPressed: _isPaused
                    ? null
                    : () {
                        if (_currentStep == widget.recipe.steps.length - 1) {
                          _completeSession();
                        } else {
                          _goToStep(_currentStep + 1);
                        }
                      },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                label: Text(
                  _currentStep == widget.recipe.steps.length - 1
                      ? 'Looks good — finish cooking'
                      : 'Looks good — continue to Step ${_currentStep + 2}',
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomVoiceOrbDock() {
    return ListenableBuilder(
      listenable: widget.voiceController,
      builder: (context, _) {
        final state = widget.voiceController.activityState;
        final mode = widget.voiceController.listeningMode;
        final partial = widget.voiceController.partialTranscript;
        final isMuted = widget.voiceController.audioMuted;

        final orbColor = switch (state) {
          VoiceActivityState.listening => CookTogetherTheme.herbGreen,
          VoiceActivityState.capturingVision => CookTogetherTheme.warmOrange,
          VoiceActivityState.thinking => CookTogetherTheme.warmOrange,
          VoiceActivityState.speaking => CookTogetherTheme.terracottaRed,
          VoiceActivityState.idle => const Color(0xFF5D7553),
        };

        final statusLabel = partial.isNotEmpty
            ? '“$partial…”'
            : switch (state) {
                VoiceActivityState.listening =>
                  mode == VoiceListeningMode.handsFree
                      ? 'Hands-free mic active · Say "next step", "set a timer", or "does this look right?"'
                      : 'Listening… ask your question or give a command',
                VoiceActivityState.capturingVision =>
                  'Looking through your Meta glasses…',
                VoiceActivityState.thinking =>
                  'CookTogether is thinking…',
                VoiceActivityState.speaking =>
                  'CookTogether is speaking…',
                VoiceActivityState.idle =>
                  mode == VoiceListeningMode.handsFree
                      ? 'Hands-free mode ready · Tap orb or speak'
                      : 'Tap the voice orb to speak',
              };

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: const BoxDecoration(
            color: CookTogetherTheme.surface,
            border: Border(top: BorderSide(color: CookTogetherTheme.border)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1228332A),
                blurRadius: 18,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Voice status & Hands-Free / Tap-to-Speak mode switch
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: partial.isNotEmpty
                              ? CookTogetherTheme.ink
                              : CookTogetherTheme.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final nextMode = mode == VoiceListeningMode.handsFree
                            ? VoiceListeningMode.tapToSpeak
                            : VoiceListeningMode.handsFree;
                        widget.voiceController.setListeningMode(nextMode);
                        widget.onShowToast(
                          nextMode == VoiceListeningMode.handsFree
                              ? 'Hands-free continuous listening enabled'
                              : 'Switched to Tap-to-Speak mode',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: mode == VoiceListeningMode.handsFree
                              ? CookTogetherTheme.toneGreenBg
                              : const Color(0xFFF1F1E8),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              mode == VoiceListeningMode.handsFree
                                  ? Icons.hearing_rounded
                                  : Icons.touch_app_rounded,
                              size: 12,
                              color: mode == VoiceListeningMode.handsFree
                                  ? CookTogetherTheme.deepHerbGreen
                                  : CookTogetherTheme.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              mode == VoiceListeningMode.handsFree
                                  ? 'Hands-Free'
                                  : 'Tap-to-Speak',
                              style: CookTogetherTheme.bodyStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: mode == VoiceListeningMode.handsFree
                                    ? CookTogetherTheme.deepHerbGreen
                                    : CookTogetherTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Dock row with 4 utility controls + central Animated Voice Orb
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _DockActionButton(
                      icon: Icons.visibility_outlined,
                      label: 'Check Step',
                      activeColor: CookTogetherTheme.deepHerbGreen,
                      onTap: _isPaused ? null : () => _triggerVisualCheck(),
                    ),
                    _DockActionButton(
                      icon: isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      label: isMuted ? 'Muted' : 'Audio',
                      isOff: isMuted,
                      onTap: () => widget.voiceController.toggleAudioMuted(),
                    ),
                    // Prominent Voice Orb
                    GestureDetector(
                      onTap: () {
                        if (_isPaused) {
                          _togglePause(forcePause: false);
                          return;
                        }
                        if (widget.voiceController.speechAvailable) {
                          widget.voiceController.toggleTapToSpeak();
                        } else {
                          // When running on simulator/test without hardware mic,
                          // trigger a realistic voice query or open the input bar
                          _handleUserUtterance(
                            'Does this look chopped small enough?',
                          );
                        }
                      },
                      child: AnimatedBuilder(
                        animation: _orbPulseController,
                        builder: (context, child) {
                          final scale = state == VoiceActivityState.listening ||
                                  state == VoiceActivityState.speaking
                              ? 1.0 + (_orbPulseController.value * 0.08)
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    orbColor.withValues(alpha: 0.92),
                                    orbColor,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: orbColor.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                switch (state) {
                                  VoiceActivityState.capturingVision =>
                                    Icons.camera_enhance_rounded,
                                  VoiceActivityState.speaking =>
                                    Icons.graphic_eq_rounded,
                                  VoiceActivityState.thinking =>
                                    Icons.auto_awesome_rounded,
                                  _ => Icons.mic_rounded,
                                },
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _DockActionButton(
                      icon: _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: _isPaused ? 'Resume' : 'Pause',
                      isWarning: _isPaused,
                      onTap: () => _togglePause(),
                    ),
                    _DockActionButton(
                      icon: _composerOpen
                          ? Icons.keyboard_hide_rounded
                          : Icons.keyboard_alt_outlined,
                      label: _composerOpen ? 'Hide' : 'Type',
                      onTap: () =>
                          setState(() => _composerOpen = !_composerOpen),
                    ),
                  ],
                ),
                if (_composerOpen) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F8F3),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: CookTogetherTheme.border),
                          ),
                          child: TextField(
                            controller: _textController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _handleUserUtterance,
                            style: CookTogetherTheme.bodyStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText:
                                  'Say or type a command ("next step", "does this look right?")…',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: CookTogetherTheme.terracottaRed,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          tooltip: 'Send question',
                          onPressed: () =>
                              _handleUserUtterance(_textController.text),
                          icon: const Icon(Icons.send_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfirmEndModal() {
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(26),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: CookTogetherTheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: CookTogetherTheme.toneRedBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.pause_rounded,
                color: CookTogetherTheme.terracottaRed,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Leave this cooking session?',
              textAlign: TextAlign.center,
              style: CookTogetherTheme.headingStyle(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Your current step will not be marked complete. You can stay and pause instead.',
              textAlign: TextAlign.center,
              style: CookTogetherTheme.bodyStyle(
                fontSize: 12,
                color: CookTogetherTheme.muted,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CookTogetherTheme.terracottaRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: widget.onExitToHome,
                child: Text(
                  'End session',
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _confirmEndOpen = false);
                _togglePause(forcePause: true);
              },
              child: Text(
                'Stay and pause',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: CookTogetherTheme.deepHerbGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOff;
  final bool isWarning;
  final Color? activeColor;
  final VoidCallback? onTap;

  const _DockActionButton({
    required this.icon,
    required this.label,
    this.isOff = false,
    this.isWarning = false,
    this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isOff
        ? const Color(0xFFFBE9E5)
        : isWarning
        ? const Color(0xFFFFF0D9)
        : const Color(0xFFEFF2E9);
    final fgColor = isOff
        ? CookTogetherTheme.terracottaRed
        : isWarning
        ? const Color(0xFFA76B22)
        : (activeColor ?? const Color(0xFF536C4B));

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 58,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: fgColor),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CookTogetherTheme.bodyStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: fgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
