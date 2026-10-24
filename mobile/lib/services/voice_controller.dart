import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/conversation.dart';

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
  /// Automatic restarts stop after this many listens in a row end almost
  /// immediately with nothing heard. A tap on the microphone always retries.
  static const int _maxFastFailures = 3;

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _autoRestartPaused = false;
  int _fastFailures = 0;

  /// True once this listen's words were sent, so a late final result from
  /// the recognizer doesn't send them a second time.
  bool _turnDelivered = false;
  bool _isSessionActive = false;
  bool _isPaused = false;
  bool _audioMuted = false;
  bool _isAudioBusy = false;
  DateTime? _lastListenStartTime;

  Timer? _restartListenTimer;
  Timer? _ttsSafetyTimer;

  VoiceListeningMode _listeningMode = VoiceListeningMode.handsFree;
  VoiceActivityState _activityState = VoiceActivityState.idle;
  String _partialTranscript = '';
  String? _statusHint;

  void Function(String transcript)? onFinalUtterance;

  VoiceListeningMode get listeningMode => _listeningMode;
  VoiceActivityState get activityState => _activityState;
  String get partialTranscript => _partialTranscript;
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

  Future<bool> _ensureSpeechInitialized() async {
    if (_speechInitialized) return _speechAvailable;
    _speechInitialized = true;
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!_isSessionActive) return;
          // React once per listen cycle: 'done' or 'doneNoResult', never also
          // on 'notListening', which scheduled duplicate restarts.
          if (status == 'done' || status == 'doneNoResult') _onListenEnded();
        },
        // Android reports "no match" or "speech timeout" whenever the user
        // pauses. These end the listen but are not a reason to stop
        // listening for good; _onListenEnded decides whether to restart.
        onError: (_) {
          if (!_isSessionActive) return;
          _onListenEnded();
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
    return _speechAvailable;
  }

  /// Called when a listen ends, by a pause, a timeout or an error. Sends any
  /// words already heard, then restarts listening in hands-free mode.
  void _onListenEnded() {
    final heardSomething = _partialTranscript.trim().isNotEmpty;
    _deliverPartialTranscript();

    final startedAt = _lastListenStartTime;
    final elapsedMs = startedAt != null
        ? DateTime.now().difference(startedAt).inMilliseconds
        : 9999;
    if (heardSomething || elapsedMs >= 2000) {
      _fastFailures = 0;
    } else if (++_fastFailures >= _maxFastFailures) {
      // Listens keep ending at once with nothing heard (for example
      // Code=203 on the iOS Simulator). Stop restarting on our own so the
      // audio engine isn't reallocated in a loop; a mic tap still works.
      _autoRestartPaused = true;
      _restartListenTimer?.cancel();
    }

    if (_activityState == VoiceActivityState.listening) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    }

    if (_listeningMode == VoiceListeningMode.handsFree &&
        !_isPaused &&
        !_autoRestartPaused &&
        _activityState == VoiceActivityState.idle) {
      _scheduleListeningRestart();
    }
  }

  /// Sends the words heard so far as one utterance, so nothing the user
  /// said is lost when a listen ends before the recognizer's final result.
  void _deliverPartialTranscript() {
    final words = _partialTranscript.trim();
    if (words.isEmpty) return;
    _turnDelivered = true;
    _partialTranscript = '';
    _activityState = VoiceActivityState.idle;
    notifyListeners();
    onFinalUtterance?.call(words);
  }

  void _cancelTimers() {
    _restartListenTimer?.cancel();
    _restartListenTimer = null;
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
  }

  void _onTtsFinished() {
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
    if (!_isSessionActive) return;
    if (_activityState == VoiceActivityState.speaking) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
    }
    if (_listeningMode == VoiceListeningMode.handsFree &&
        !_isPaused &&
        !_autoRestartPaused) {
      _scheduleListeningRestart(delayMs: 650);
    }
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

  /// Handles a tap on the microphone: stops listening if it is listening,
  /// otherwise starts. A tap always retries, even after errors stopped the
  /// automatic restarts. It never makes up an utterance.
  Future<MicTapResult> tapMic() async {
    if (_isPaused) return MicTapResult.stopped;
    if (_activityState == VoiceActivityState.listening &&
        _speechAvailable &&
        _speech.isListening) {
      await stopListening();
      return MicTapResult.stopped;
    }
    _autoRestartPaused = false;
    _fastFailures = 0;
    if (!await _ensureSpeechInitialized()) return MicTapResult.unavailable;
    await _startListeningLoop(forceSingleTurn: true);
    return MicTapResult.listening;
  }

  Future<void> _startListeningLoop({bool forceSingleTurn = false}) async {
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

      // Show "listening" only once the recognizer is really starting.
      _partialTranscript = '';
      _turnDelivered = false;
      _activityState = VoiceActivityState.listening;
      _statusHint =
          _listeningMode == VoiceListeningMode.handsFree && !forceSingleTurn
          ? 'Listening hands-free… say a command or ask a question'
          : 'Listening… speak now';
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
    // Words from this listen were already sent when it ended early.
    if (_turnDelivered) return;
    _partialTranscript = result.recognizedWords;
    notifyListeners();
    if (result.finalResult) _deliverPartialTranscript();
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

  Future<void> speak(String text, {required bool voiceGuidanceEnabled}) async {
    _restartListenTimer?.cancel();
    _ttsSafetyTimer?.cancel();

    if (!_isSessionActive || _audioMuted || !voiceGuidanceEnabled) {
      if (_listeningMode == VoiceListeningMode.handsFree && !_isPaused) {
        await _startListeningLoop();
      } else {
        _activityState = VoiceActivityState.idle;
        notifyListeners();
      }
      return;
    }

    await stopListening();
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
    } catch (_) {
      _onTtsFinished();
    }
  }

  Future<void> shutdownSession() async {
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
