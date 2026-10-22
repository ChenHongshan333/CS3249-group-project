import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/conversation.dart';

/// Manages on-device Speech-to-Text (`speech_to_text`) and Text-to-Speech (`flutter_tts`)
/// for the Cooking screen, supporting both Hands-Free Continuous Listening and Tap-to-Speak.
class VoiceController extends ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _autoListenBlockedByError = false;
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
  bool get speechAvailable => _speechAvailable && !_autoListenBlockedByError;
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
    _autoListenBlockedByError = false;
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
    if (_speechInitialized) {
      return _speechAvailable && !_autoListenBlockedByError;
    }
    _speechInitialized = true;
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!_isSessionActive) return;
          if (status == 'doneNoResult') {
            final startedAt = _lastListenStartTime;
            final elapsedMs = startedAt != null
                ? DateTime.now().difference(startedAt).inMilliseconds
                : 9999;
            if (elapsedMs < 2000) {
              _autoListenBlockedByError = true;
              _restartListenTimer?.cancel();
            }
            return;
          }
          // Only react once per listen cycle on 'done' (never on both 'notListening' and 'done',
          // which previously scheduled duplicate concurrent AVAudioEngine restarts).
          if (status == 'done') {
            final startedAt = _lastListenStartTime;
            final elapsedMs = startedAt != null
                ? DateTime.now().difference(startedAt).inMilliseconds
                : 9999;
            if (elapsedMs < 2000 && _partialTranscript.trim().isEmpty) {
              // Because pauseFor is 3000ms, finishing in <2000ms with an empty transcript
              // indicates the native recognizer failed immediately (e.g. Code=203 on iOS Simulator).
              // Block automatic background restarts so AVAudioEngine is never reallocated in a loop.
              _autoListenBlockedByError = true;
              _restartListenTimer?.cancel();
            }

            if (_activityState == VoiceActivityState.listening) {
              _activityState = VoiceActivityState.idle;
              notifyListeners();
            }

            if (_listeningMode == VoiceListeningMode.handsFree &&
                !_isPaused &&
                !_autoListenBlockedByError &&
                _activityState == VoiceActivityState.idle) {
              _scheduleListeningRestart();
            }
          }
        },
        onError: (_) {
          if (!_isSessionActive) return;
          // Stop automatic background restarts when the speech engine reports an error
          // (common on iOS Simulator) to prevent an AVAudioEngine retry storm.
          _autoListenBlockedByError = true;
          _restartListenTimer?.cancel();
          if (_activityState == VoiceActivityState.listening) {
            _activityState = VoiceActivityState.idle;
            notifyListeners();
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
    return _speechAvailable && !_autoListenBlockedByError;
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
        !_autoListenBlockedByError) {
      _scheduleListeningRestart(delayMs: 650);
    }
  }

  void _scheduleListeningRestart({int delayMs = 800}) {
    _restartListenTimer?.cancel();
    _restartListenTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_isSessionActive &&
          !_isPaused &&
          !_autoListenBlockedByError &&
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

  Future<void> toggleTapToSpeak() async {
    if (_isPaused) return;
    if (_activityState == VoiceActivityState.listening &&
        _speechAvailable &&
        _speech.isListening) {
      await stopListening();
    } else {
      await _startListeningLoop(forceSingleTurn: true);
    }
  }

  Future<void> _startListeningLoop({bool forceSingleTurn = false}) async {
    if (!_isSessionActive || _isPaused || _isAudioBusy) return;
    if (_activityState == VoiceActivityState.speaking ||
        _activityState == VoiceActivityState.capturingVision ||
        _activityState == VoiceActivityState.thinking) {
      return;
    }

    _restartListenTimer?.cancel();
    _partialTranscript = '';
    _activityState = VoiceActivityState.listening;
    _statusHint =
        _listeningMode == VoiceListeningMode.handsFree && !forceSingleTurn
        ? 'Listening hands-free… say a command or ask a question'
        : 'Listening… speak now';
    notifyListeners();

    if (_autoListenBlockedByError) {
      return;
    }

    _isAudioBusy = true;
    try {
      final ready = await _ensureSpeechInitialized();
      if (!ready || !_isSessionActive || _isPaused) {
        return;
      }
      if (_speech.isListening) {
        return;
      }
      _lastListenStartTime = DateTime.now();
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
        ),
      );
    } catch (_) {
      _autoListenBlockedByError = true;
    } finally {
      _isAudioBusy = false;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _partialTranscript = result.recognizedWords;
    notifyListeners();

    if (result.finalResult && _partialTranscript.trim().isNotEmpty) {
      final finalWords = _partialTranscript.trim();
      _partialTranscript = '';
      _activityState = VoiceActivityState.idle;
      notifyListeners();
      onFinalUtterance?.call(finalWords);
    }
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
      _ttsSafetyTimer = Timer(Duration(milliseconds: timeoutMs), _onTtsFinished);
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
