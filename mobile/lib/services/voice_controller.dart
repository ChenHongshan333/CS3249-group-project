import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/conversation.dart';
import 'audio_route.dart';

/// What happened when the user tapped the microphone.
enum MicTapResult {
  /// The app is now listening.
  listening,

  /// The app stopped listening, or the tap did nothing (session paused).
  stopped,

  /// Speech recognition can't be used on this device, for example because
  /// microphone permission was denied.
  unavailable,
}

/// Manages on-device Speech-to-Text (`speech_to_text`) and Text-to-Speech (`flutter_tts`)
/// for the Cooking screen, supporting both Hands-Free Continuous Listening and Tap-to-Speak.
class VoiceController extends ChangeNotifier {
  /// Listens that end almost at once with nothing heard (kitchen noise,
  /// Android's quick "no match") are retried at once at first, then after
  /// a growing wait from this many in a row, and automatic restarts stop
  /// after [_maxFastFailures]. A tap on the microphone always retries.
  static const int _backOffAfter = 3;
  static const int _maxFastFailures = 6;

  /// Android ends a listen at the first short pause. Words heard before a
  /// pause are kept and listening restarts at once; the sentence is only
  /// sent after this much silence, so a pause doesn't cut it in two.
  static const Duration _sentenceGap = Duration(milliseconds: 1500);

  /// Tests pass their own [speech] and [tts]; the app uses the plugins'.
  VoiceController({SpeechToText? speech, FlutterTts? tts})
    : _speech = speech ?? SpeechToText(),
      _tts = tts ?? FlutterTts();

  final SpeechToText _speech;
  final FlutterTts _tts;
  final AudioRoute _audioRoute = const AudioRoute();

  /// Name of the Bluetooth headset (the glasses) speech is recorded from, or
  /// null when the phone's own mic is used.
  String? _bluetoothMic;
  String? get bluetoothMic => _bluetoothMic;

  /// Records through the glasses' mic when they are connected. Off in
  /// Profile → Developer to use the phone's mic only.
  bool useGlassesMic = true;

  /// True once the glasses' mic was in use this session. The glasses drop
  /// it by themselves (#40), so it is opened again before each turn.
  bool _keepGlassesMic = false;

  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _autoRestartPaused = false;
  int _fastFailures = 0;

  /// True once this listen's words were sent, so a late final result from
  /// the recognizer doesn't send them a second time.
  bool _turnDelivered = false;

  /// Words heard in earlier listens of the sentence the user is still saying.
  String _sentence = '';
  Timer? _sentenceGapTimer;

  /// True while CookTogether is asking the user something, so it listens
  /// for the answer as soon as it finishes speaking, in either mode.
  bool _awaitingAnswer = false;

  /// True for a listen the user is expecting to be heard in: after a mic
  /// tap or a question. If it hears nothing, CookTogether asks once more.
  bool _expectingSpeech = false;
  bool _askedAgain = false;

  /// Saying "hold on" (or "wait", "stop"…) while CookTogether speaks cuts
  /// it off, like a mic tap. Off in Profile when the phone beeps whenever
  /// it starts listening.
  bool interruptByVoice = true;

  /// True while listening for "hold on" during speech. That listen only
  /// reacts to short stop phrases, never to what CookTogether is saying.
  bool _interruptListening = false;
  String _speakingText = '';
  DateTime? _interruptListenStart;

  static final _stopPhrase = RegExp(
    r"^(?:hold on|hang on|wait|stop|pause|one (?:moment|sec(?:ond)?)|"
    r"quiet|be quiet|shush|stop (?:talking|speaking))\b",
  );

  /// Android often reports both an error and "done" for one listen; only
  /// the first counts, so one failed listen isn't counted twice.
  bool _listenEndHandled = true;
  bool _isSessionActive = false;
  bool _isPaused = false;
  bool _audioMuted = false;
  bool _isAudioBusy = false;
  bool _preparingPhoto = false;
  int _photoPreparationId = 0;
  DateTime? _lastListenStartTime;

  Timer? _restartListenTimer;
  Timer? _ttsSafetyTimer;

  VoiceListeningMode _listeningMode = VoiceListeningMode.handsFree;
  VoiceActivityState _activityState = VoiceActivityState.idle;
  String _partialTranscript = '';
  String? _statusHint;

  void Function(String transcript)? onFinalUtterance;

  /// A listen the user expected to be heard in heard nothing. Called once;
  /// the next time, listening stops instead.
  VoidCallback? onNothingHeard;

  /// Listening stopped and won't restart on its own; the user has to tap
  /// the mic.
  VoidCallback? onListeningStopped;

  /// True when hands-free listening gave up after repeated failures.
  bool get listeningStopped =>
      _autoRestartPaused && _listeningMode == VoiceListeningMode.handsFree;

  VoiceListeningMode get listeningMode => _listeningMode;
  VoiceActivityState get activityState => _activityState;

  /// Everything heard of the current sentence, across pauses.
  String get partialTranscript => [
    _sentence,
    _partialTranscript.trim(),
  ].where((w) => w.isNotEmpty).join(' ');
  bool get audioMuted => _audioMuted;
  bool get speechAvailable => _speechAvailable;
  String? get statusHint => _statusHint;

  Future<void> initialize({
    VoiceListeningMode initialMode = VoiceListeningMode.handsFree,
    bool initialMuted = false,
    bool startListeningImmediately = false,
  }) async {
    _cancelTimers();
    _listeningMode = initialMode;
    _audioMuted = initialMuted;
    _isSessionActive = true;
    _isPaused = false;
    _autoRestartPaused = false;
    _fastFailures = 0;
    _isAudioBusy = false;
    _keepGlassesMic = false;
    if (useGlassesMic) {
      await _routeToBluetoothMic();
      _keepGlassesMic = _bluetoothMic != null;
    } else {
      _bluetoothMic = null;
      await _audioRoute.clear();
    }

    try {
      await _tts.setSharedInstance(true);
      await _tts.autoStopSharedSession(false);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        const [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } catch (_) {
      // Ignore on non-iOS or test environments.
    }

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      _tts.setCompletionHandler(_onTtsFinished);
      _tts.setCancelHandler(_onTtsFinished);
      _tts.setErrorHandler((_) => _onTtsFinished());
    } catch (_) {
      // Ignore in test environments without native TTS plugin channel.
    }

    if (startListeningImmediately &&
        _listeningMode == VoiceListeningMode.handsFree) {
      await _startListeningLoop();
    } else {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    }
  }

  /// Records through the glasses' Bluetooth mic when they are connected, so
  /// the user doesn't have to talk to the phone. The link must be up before
  /// listening starts: the recognizer keeps the mic it started with.
  Future<void> _routeToBluetoothMic() async {
    _bluetoothMic = await _audioRoute.useBluetoothMic();
    notifyListeners();
  }

  /// Waits for the glasses' mic to come back if it dropped, so the user's
  /// first words and the start of a reply aren't lost. Uses the phone's mic
  /// for this turn when it doesn't come back in time.
  Future<void> _reopenGlassesMic() async {
    if (!_keepGlassesMic) return;
    final mic = await _audioRoute.useBluetoothMic();
    if (mic == _bluetoothMic) return;
    _bluetoothMic = mic;
    notifyListeners();
  }

  Future<bool> _ensureSpeechInitialized() async {
    if (_speechInitialized) return _speechAvailable;
    _speechInitialized = true;
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!_isSessionActive) return;
          // React once per listen cycle: 'done' or 'doneNoResult', never also
          // on 'notListening', which scheduled duplicate restarts.
          if (status == 'done' || status == 'doneNoResult') {
            _interruptListening ? _onInterruptListenEnded() : _onListenEnded();
          }
        },
        // Android reports "no match" or "speech timeout" whenever the user
        // pauses. These end the listen but are not a reason to stop
        // listening for good; _onListenEnded decides whether to restart.
        onError: (_) {
          if (!_isSessionActive) return;
          _interruptListening ? _onInterruptListenEnded() : _onListenEnded();
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
    return _speechAvailable;
  }

  /// Called when a listen ends, by a pause, a timeout or an error. Keeps any
  /// words already heard and listens again so the sentence can continue;
  /// otherwise restarts listening in hands-free mode.
  void _onListenEnded() {
    if (_listenEndHandled) return;
    _listenEndHandled = true;
    // Words kept from a final result earlier in this listen count too.
    final heardSomething =
        _partialTranscript.trim().isNotEmpty || _turnDelivered;
    _keepHeardWords();
    final expectedSpeech = _expectingSpeech;
    _expectingSpeech = false;
    if (heardSomething) _askedAgain = false;

    final startedAt = _lastListenStartTime;
    final elapsedMs = startedAt != null
        ? DateTime.now().difference(startedAt).inMilliseconds
        : 9999;
    var gaveUp = false;
    if (heardSomething || elapsedMs >= 2000) {
      _fastFailures = 0;
    } else if (++_fastFailures >= _maxFastFailures &&
        _listeningMode == VoiceListeningMode.handsFree) {
      // Listens keep ending at once with nothing heard (for example
      // Code=203 on the iOS Simulator). Stop restarting on our own so the
      // audio engine isn't reallocated in a loop; a mic tap still works.
      _autoRestartPaused = true;
      _restartListenTimer?.cancel();
      gaveUp = true;
    }

    if (_activityState == VoiceActivityState.listening) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    }
    if (_isPaused || !_isSessionActive) return;

    if (_sentence.isNotEmpty) {
      // Mid-sentence: listen again straight away for the rest of it.
      _startListeningLoop(forceSingleTurn: true);
      return;
    }

    if (expectedSpeech && !heardSomething) {
      if (!_askedAgain) {
        // Ask once more ("Sorry, I didn't catch that…"); the question
        // makes CookTogether listen again when it finishes speaking.
        _askedAgain = true;
        onNothingHeard?.call();
        return;
      }
      _askedAgain = false;
      if (_listeningMode == VoiceListeningMode.tapToSpeak) {
        onListeningStopped?.call();
        return;
      }
    }

    if (gaveUp) {
      onListeningStopped?.call();
      return;
    }
    if (_listeningMode == VoiceListeningMode.handsFree &&
        !_autoRestartPaused &&
        _activityState == VoiceActivityState.idle) {
      _scheduleListeningRestart(delayMs: _restartDelayMs);
    }
  }

  /// 0.8 s normally; after repeated quick failures 2, 4, then 8 s.
  int get _restartDelayMs => _fastFailures < _backOffAfter
      ? 800
      : 2000 << (_fastFailures - _backOffAfter);

  /// Adds the words of the listen that just ended to the sentence, so
  /// nothing is lost, and waits [_sentenceGap] for more before sending it.
  void _keepHeardWords() {
    final words = _partialTranscript.trim();
    if (words.isEmpty) return;
    _turnDelivered = true;
    _partialTranscript = '';
    _sentence = _sentence.isEmpty ? words : '$_sentence $words';
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = Timer(_sentenceGap, _finishSentence);
    notifyListeners();
  }

  /// Sends the sentence once the user has been quiet for [_sentenceGap].
  void _finishSentence() {
    if (_speech.isListening && _partialTranscript.trim().isNotEmpty) {
      // Still talking; wait for the next pause.
      _sentenceGapTimer = Timer(_sentenceGap, _finishSentence);
      return;
    }
    _sendSentence();
  }

  void _sendSentence() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    final words = [
      _sentence,
      _partialTranscript.trim(),
    ].where((w) => w.isNotEmpty).join(' ');
    // Ignore the rest of the current listen only if its words were sent.
    if (_partialTranscript.trim().isNotEmpty) _turnDelivered = true;
    _sentence = '';
    _partialTranscript = '';
    if (words.isEmpty) return;
    if (_listeningMode == VoiceListeningMode.tapToSpeak) {
      stopListening();
    }
    notifyListeners();
    onFinalUtterance?.call(words);
  }

  void _clearSentence() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    _sentence = '';
  }

  void _cancelTimers() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    _restartListenTimer?.cancel();
    _restartListenTimer = null;
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
  }

  void _onTtsFinished() {
    // The countdown owns the microphone until the photo can be taken.
    if (_preparingPhoto) return;
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
    if (!_isSessionActive) return;
    if (_activityState == VoiceActivityState.speaking) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    }
    if (_interruptListening) {
      // The usual listen can only start once this one has stopped.
      _stopInterruptListen().whenComplete(_afterSpeech);
      return;
    }
    _afterSpeech();
  }

  void _afterSpeech() {
    if (!_isSessionActive) return;
    if (_awaitingAnswer && !_isPaused) {
      _listenForAnswer();
      return;
    }
    if (_listeningMode == VoiceListeningMode.handsFree &&
        !_isPaused &&
        !_autoRestartPaused) {
      _scheduleListeningRestart(delayMs: 650);
    }
  }

  /// Listens once for the answer to a question CookTogether just asked,
  /// without needing a tap, even in tap-to-speak mode or after errors
  /// paused automatic restarts.
  void _listenForAnswer() {
    _awaitingAnswer = false;
    _autoRestartPaused = false;
    _fastFailures = 0;
    _restartListenTimer?.cancel();
    _restartListenTimer = Timer(const Duration(milliseconds: 100), () {
      if (_isSessionActive &&
          !_isPaused &&
          _activityState == VoiceActivityState.idle) {
        _startListeningLoop(forceSingleTurn: true);
      }
    });
  }

  void _scheduleListeningRestart({int delayMs = 800}) {
    _restartListenTimer?.cancel();
    _restartListenTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_isSessionActive &&
          !_isPaused &&
          !_autoRestartPaused &&
          _listeningMode == VoiceListeningMode.handsFree &&
          _activityState == VoiceActivityState.idle) {
        _startListeningLoop();
      }
    });
  }

  void setActivityState(VoiceActivityState state, {String? hint}) {
    _restartListenTimer?.cancel();
    _activityState = state;
    if (hint != null) _statusHint = hint;
    notifyListeners();
  }

  Future<void> setListeningMode(VoiceListeningMode mode) async {
    if (_listeningMode == mode) return;
    _listeningMode = mode;
    _restartListenTimer?.cancel();
    if (mode == VoiceListeningMode.handsFree && !_isPaused) {
      await _startListeningLoop();
    } else if (mode == VoiceListeningMode.tapToSpeak &&
        _activityState == VoiceActivityState.listening) {
      await stopListening();
    }
    notifyListeners();
  }

  Future<void> toggleAudioMuted() async {
    _audioMuted = !_audioMuted;
    if (_audioMuted) {
      _photoPreparationId++;
      await _stopInterruptListen();
      _ttsSafetyTimer?.cancel();
      try {
        await _tts.stop();
      } catch (_) {}
      if (_activityState == VoiceActivityState.speaking) {
        _activityState = VoiceActivityState.idle;
      }
    }
    notifyListeners();
  }

  Future<void> setAudioMuted(bool muted) async {
    if (_audioMuted == muted) return;
    await toggleAudioMuted();
  }

  Future<void> setSessionPaused(bool paused) async {
    if (paused) {
      _photoPreparationId++;
      _clearSentence();
      await _stopInterruptListen();
    }
    _isPaused = paused;
    _restartListenTimer?.cancel();
    _ttsSafetyTimer?.cancel();
    if (paused) {
      await stopListening();
      try {
        await _tts.stop();
      } catch (_) {}
      _activityState = VoiceActivityState.idle;
    } else if (_listeningMode == VoiceListeningMode.handsFree) {
      await _startListeningLoop();
    }
    notifyListeners();
  }

  /// Handles a tap on the microphone: starts listening, or in tap-to-speak
  /// mode stops it and sends what was heard. A tap while CookTogether is
  /// speaking cuts it off and listens; the words stay on screen. A tap
  /// always retries, even after errors stopped the automatic restarts. It
  /// never makes up an utterance.
  Future<MicTapResult> tapMic() async {
    if (_preparingPhoto) return MicTapResult.stopped;
    if (_isPaused) return MicTapResult.stopped;
    if (_activityState == VoiceActivityState.speaking) {
      await _stopInterruptListen();
      await _stopSpeaking();
    }
    if (_activityState == VoiceActivityState.listening &&
        _speechAvailable &&
        _speech.isListening) {
      // Hands-free is already listening: a tap means "listen to me", so
      // keep going rather than cutting off what the user is saying.
      if (_listeningMode == VoiceListeningMode.handsFree) {
        return MicTapResult.listening;
      }
      _keepHeardWords();
      await stopListening();
      _sendSentence();
      return MicTapResult.stopped;
    }
    _autoRestartPaused = false;
    _fastFailures = 0;
    if (!await _ensureSpeechInitialized()) return MicTapResult.unavailable;
    await _startListeningLoop(forceSingleTurn: true);
    return MicTapResult.listening;
  }

  /// Listens during speech for "hold on". What the phone hears of its own
  /// voice is ignored: only a short stop phrase that CookTogether isn't
  /// saying counts.
  Future<void> _startInterruptListen() async {
    if (_interruptListening ||
        _isPaused ||
        _activityState != VoiceActivityState.speaking ||
        !await _ensureSpeechInitialized() ||
        _speech.isListening ||
        _activityState != VoiceActivityState.speaking) {
      return;
    }
    _interruptListening = true;
    _interruptListenStart = DateTime.now();
    try {
      await _speech.listen(
        onResult: _onInterruptResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          listenMode: ListenMode.confirmation,
          cancelOnError: false,
        ),
      );
    } catch (_) {
      _interruptListening = false;
    }
  }

  void _onInterruptResult(SpeechRecognitionResult result) {
    if (!_interruptListening) return;
    final words = result.recognizedWords.toLowerCase().trim();
    final phrase = _stopPhrase.firstMatch(words)?[0];
    if (phrase == null ||
        words.split(RegExp(r'\s+')).length > 4 ||
        _speakingText.contains(phrase)) {
      return;
    }
    _interruptBySpeech();
  }

  /// "Hold on": stop talking and listen, as a mic tap does. The user may
  /// just want a moment, so silence after it doesn't ask again.
  Future<void> _interruptBySpeech() async {
    await _stopInterruptListen();
    await _stopSpeaking();
    _autoRestartPaused = false;
    _fastFailures = 0;
    await _startListeningLoop(forceSingleTurn: true, expectSpeech: false);
  }

  /// The listen for "hold on" ended on its own; listen again while
  /// CookTogether is still speaking, unless it ended at once.
  void _onInterruptListenEnded() {
    _interruptListening = false;
    final startedAt = _interruptListenStart;
    final lasted = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    if (_activityState == VoiceActivityState.speaking &&
        lasted >= const Duration(seconds: 1)) {
      _startInterruptListen();
    }
  }

  Future<void> _stopInterruptListen() async {
    if (!_interruptListening) return;
    _interruptListening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> _stopSpeaking() async {
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
    // The user is about to talk, so don't also listen for an answer.
    _awaitingAnswer = false;
    _activityState = VoiceActivityState.idle;
    try {
      await _tts.stop();
    } catch (_) {}
    // Stopping fires the TTS cancel handler, which may schedule a restart.
    _restartListenTimer?.cancel();
  }

  Future<void> _startListeningLoop({
    bool forceSingleTurn = false,
    bool expectSpeech = true,
  }) async {
    if (_preparingPhoto) return;
    if (!_isSessionActive || _isPaused || _isAudioBusy) return;
    if (_activityState == VoiceActivityState.speaking ||
        _activityState == VoiceActivityState.capturingVision ||
        _activityState == VoiceActivityState.thinking) {
      return;
    }

    _restartListenTimer?.cancel();
    if (_autoRestartPaused && !forceSingleTurn) return;

    _isAudioBusy = true;
    try {
      final ready = await _ensureSpeechInitialized();
      if (!ready || !_isSessionActive || _isPaused) {
        _activityState = VoiceActivityState.idle;
        notifyListeners();
        return;
      }
      if (_speech.isListening) return;
      // The recognizer keeps the mic it starts with.
      if (_keepGlassesMic) {
        await _reopenGlassesMic();
        if (!_isSessionActive || _isPaused) return;
      }

      // Show "listening" only once the recognizer is really starting.
      _partialTranscript = '';
      _turnDelivered = false;
      // Not when continuing a sentence: words were already heard.
      _expectingSpeech = expectSpeech && forceSingleTurn && _sentence.isEmpty;
      _listenEndHandled = false;
      _activityState = VoiceActivityState.listening;
      _statusHint =
          _listeningMode == VoiceListeningMode.handsFree && !forceSingleTurn
          ? 'Listening hands-free… say a command or ask a question'
          : 'Listening… speak now';
      if (_bluetoothMic != null) {
        _statusHint = '$_statusHint (through $_bluetoothMic)';
      }
      notifyListeners();

      _lastListenStartTime = DateTime.now();
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          // Free-form sentences rather than short search phrases.
          listenMode: ListenMode.dictation,
          // Keep the words heard so far when Android reports "no match" or
          // a timeout; _onListenEnded sends them.
          cancelOnError: false,
        ),
      );
    } catch (_) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    } finally {
      _isAudioBusy = false;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    // Words from this listen were already kept when it ended early.
    if (_turnDelivered) return;
    _partialTranscript = result.recognizedWords;
    // The user is speaking again, so the sentence isn't finished yet.
    if (_partialTranscript.trim().isNotEmpty) _sentenceGapTimer?.cancel();
    notifyListeners();
    if (result.finalResult) _keepHeardWords();
  }

  Future<void> stopListening() async {
    _restartListenTimer?.cancel();
    try {
      if (_speechAvailable && _speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
    if (_activityState == VoiceActivityState.listening) {
      _activityState = VoiceActivityState.idle;
    }
    _partialTranscript = '';
    notifyListeners();
  }

  /// Waits for the whole countdown before allowing a glasses photo. Normal
  /// replies don't await speech completion, so they can't be used here.
  Future<bool> prepareForPhoto({required bool voiceGuidanceEnabled}) async {
    if (!_isSessionActive || _isPaused || _preparingPhoto) return false;
    _preparingPhoto = true;
    final preparationId = ++_photoPreparationId;
    _awaitingAnswer = false;
    _cancelTimers();
    _clearSentence();
    _turnDelivered = true;
    try {
      await _stopInterruptListen();
      await stopListening();
      setActivityState(
        VoiceActivityState.capturingVision,
        hint: 'Look at your food and hold still… 3, 2, 1',
      );
      await _tts.stop();
      if (!_audioMuted && voiceGuidanceEnabled) {
        await _tts.awaitSpeakCompletion(true);
        final result = await _tts
            .speak('Look at your food and hold still. 3, 2, 1.')
            .timeout(const Duration(seconds: 15));
        if (result != 1) return false;
      } else {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return preparationId == _photoPreparationId &&
          _isSessionActive &&
          !_isPaused;
    } on MissingPluginException {
      // Web/tests without TTS still get time to aim, with the hint visible.
      await Future<void>.delayed(const Duration(seconds: 3));
      return preparationId == _photoPreparationId &&
          _isSessionActive &&
          !_isPaused;
    } catch (_) {
      return false;
    } finally {
      try {
        await _tts.awaitSpeakCompletion(false);
      } catch (_) {}
      _preparingPhoto = false;
    }
  }

  Future<void> playPhotoShutter() async {
    if (!_audioMuted) await _audioRoute.playShutter();
  }

  Future<void> speak(String text, {required bool voiceGuidanceEnabled}) async {
    if (_preparingPhoto) _photoPreparationId++;
    _restartListenTimer?.cancel();
    _ttsSafetyTimer?.cancel();
    _awaitingAnswer = text.contains('?');

    if (!_isSessionActive || _audioMuted || !voiceGuidanceEnabled) {
      if (_awaitingAnswer && !_isPaused) {
        _listenForAnswer();
      } else if (_listeningMode == VoiceListeningMode.handsFree && !_isPaused) {
        await _startListeningLoop();
      } else {
        _activityState = VoiceActivityState.idle;
        notifyListeners();
      }
      return;
    }

    await stopListening();
    if (_keepGlassesMic) await _reopenGlassesMic();
    _activityState = VoiceActivityState.speaking;
    _statusHint = 'CookTogether is speaking…';
    notifyListeners();

    try {
      await _tts.stop();
      final result = await _tts.speak(text);
      if (result == null) {
        // In widget tests where no native MethodChannel is registered, finish immediately.
        _onTtsFinished();
        return;
      }
      // Safety fallback timeout based on utterance length so TTS is never cut off at 900ms,
      // while ensuring the state still recovers if the OS drops the completion callback.
      final timeoutMs = (text.length * 80).clamp(4000, 15000);
      _ttsSafetyTimer = Timer(
        Duration(milliseconds: timeoutMs),
        _onTtsFinished,
      );
      _speakingText = text.toLowerCase();
      if (interruptByVoice) await _startInterruptListen();
    } catch (_) {
      _onTtsFinished();
    }
  }

  Future<void> shutdownSession() async {
    _photoPreparationId++;
    _interruptListening = false;
    _bluetoothMic = null;
    _keepGlassesMic = false;
    _audioRoute.clear();
    _clearSentence();
    _isSessionActive = false;
    _cancelTimers();
    try {
      if (_speechAvailable && _speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    _activityState = VoiceActivityState.idle;
    _partialTranscript = '';
  }
}
