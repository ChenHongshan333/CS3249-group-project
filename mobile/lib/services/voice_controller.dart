import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/conversation.dart';
import 'audio_route.dart';
import 'whisper_transcriber.dart';

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

/// Whether speech can be recorded through the glasses' mic.
const bool kGlassesMicEnabled = true;

/// Manages on-device Speech-to-Text (`speech_to_text`) and Text-to-Speech (`flutter_tts`)
/// for the Cooking screen, supporting both Hands-Free Wake-Word Listening ("Hey Cooky")
/// and Tap-to-Speak with strict turn-taking.
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

  /// How long CookTogether stays awake waiting for a command after hearing
  /// "Hey Cooky" on its own before returning to wake-word standby.
  static const Duration _awakeWindow = Duration(seconds: 8);

  /// Matches the "Hey Cooky" wake phrase and common STT / Whisper phonetic
  /// spellings on iOS and Android ("Hey Cookie", "Hey Kooky", "Hey Cook",
  /// "Hi Cooky", "Okay Cooky", "Hey Cody", "A cookie", "Hey CookTogether").
  static final RegExp wakeWordPattern = RegExp(
    r'(?:^|\b)(?:(?:hey|hi|hay|okay|ok|yo|hello)[,!.?;:\s-]*'
    r'(?:cooky|cookie|cookies|kooky|cooki|cuki|kuki|kuky|cook\s*along|cook\s*together|cook(?:ie|y|ing|er)?|'
    r'cody|corey|courtney|kelly|corgi|coffee|cutie|copy|quickie|googley|'
    r'pookie|pooky|bookie|rookie|tookie|wookie|lucky|chucky|gookie|hookie)'
    r'|^(?:(?:a|the|he|oh|ay|eh)[,!.?;:\s]+)?(?:cooky|cookie|cookies|kooky|cooki|cuki|kuki|kuky|cook\s*along|cook\s*together))\b[,!.?;:\s-]*',
    caseSensitive: false,
  );

  /// Silence duration while in standby waiting for "Hey Cooky" (450 ms).
  /// Shorter than active command listening so the wake phrase is recognized
  /// ~400 ms faster without an awkward pause.
  static const int kWakeWordSilenceMs = 450;

  /// Silence duration while actively listening to questions or commands (850 ms),
  /// giving the user time to pause mid-sentence while cooking.
  static const int kActiveListeningSilenceMs = 850;

  /// Tests pass their own [speech], [tts], [whisperTranscriber], or
  /// [audioRoute]; the app uses the default plugins.
  VoiceController({
    SpeechToText? speech,
    FlutterTts? tts,
    WhisperTranscriber? whisperTranscriber,
    AudioRoute? audioRoute,
  }) : _speech = speech ?? SpeechToText(),
       _tts = tts ?? FlutterTts(),
       _whisper = whisperTranscriber ?? WhisperTranscriber(),
       _audioRoute = audioRoute ?? const AudioRoute();

  final SpeechToText _speech;
  final FlutterTts _tts;
  final WhisperTranscriber _whisper;
  final AudioRoute _audioRoute;

  String? _ttsVoiceName;
  String? _ttsVoiceLocale;
  double _ttsPitch = 1.0;
  double _ttsSpeechRate = 0.48;

  String? get ttsVoiceName => _ttsVoiceName;
  String? get ttsVoiceLocale => _ttsVoiceLocale;
  double get ttsPitch => _ttsPitch;
  double get ttsSpeechRate => _ttsSpeechRate;

  /// Uses `whisper_kit` (`WhisperTranscriber`, defaulting to `base.en`) with
  /// native 16 kHz PCM VAD when available, falling back to `SpeechToText` while
  /// the model is downloading or in test environments.
  bool useWhisper = true;

  /// True while the native 16 kHz VAD engine is actively recording for Whisper.
  bool _vadListening = false;
  bool get isUsingWhisper => _vadListening;

  Timer? _expectingSpeechTimer;

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

  /// Requires the "Hey Cooky" wake word in hands-free mode before speech is
  /// transcribed and sent. Tapping the mic or answering a direct question
  /// wakes listening immediately without the wake word.
  bool requireWakeWord = true;

  /// True once "Hey Cooky" (or a mic tap / direct question) has activated
  /// the current listening turn.
  bool _isAwake = false;
  Timer? _awakeTimeoutTimer;

  /// True while stopping a previous TTS utterance before starting a new one,
  /// so the asynchronous iOS cancel callback doesn't end the new speech.
  bool _ignoringTtsCancel = false;

  /// Android often reports both an error and "done" for one listen; only
  /// the first counts, so one failed listen isn't counted twice.
  bool _listenEndHandled = true;
  bool _isSessionActive = false;
  bool _isPaused = false;
  bool _audioMuted = false;
  bool _isAudioBusy = false;
  /// Invalidates results still being transcribed when a recording is replaced.
  int _listeningGeneration = 0;
  bool _micTapInProgress = false;
  Completer<void>? _listeningStartDone;
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

  /// True while hands-free listening is in standby waiting for "Hey Cooky".
  bool get waitingForWakeWord =>
      _activityState == VoiceActivityState.listening &&
      _listeningMode == VoiceListeningMode.handsFree &&
      requireWakeWord &&
      !_isAwake;

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

  /// Downloads the Whisper model (`ggml-base.en.bin`) on app startup
  /// if it is not already stored on disk.
  void prepareWhisperOnAppStartup() {
    if (useWhisper) {
      unawaited(_whisper.ensureModelDownloaded());
    }
  }

  /// Applies user-selected voice preferences to the TTS engine.
  Future<void> configureVoice({
    String? voiceName,
    String? voiceLocale,
    double? pitch,
    double? rate,
  }) async {
    _ttsVoiceName = voiceName;
    _ttsVoiceLocale = voiceLocale;
    if (pitch != null) _ttsPitch = pitch;
    if (rate != null) _ttsSpeechRate = rate;

    try {
      if (_ttsVoiceLocale != null && _ttsVoiceLocale!.isNotEmpty) {
        await _tts.setLanguage(_ttsVoiceLocale!);
      } else {
        await _tts.setLanguage('en-US');
      }
      await _tts.setSpeechRate(_ttsSpeechRate);
      await _tts.setPitch(_ttsPitch);
      if (_ttsVoiceName != null && _ttsVoiceName!.isNotEmpty) {
        await _tts.setVoice({
          'name': _ttsVoiceName!,
          'locale': _ttsVoiceLocale ?? 'en-US',
        });
      }
    } catch (_) {
      // Ignore in test or unsupported environments.
    }
  }

  /// Returns the list of available TTS voices from the platform, filtered to
  /// English voices by default. Gives up after a few seconds, so a platform
  /// that never answers (or a test) doesn't leave Profile loading forever.
  Future<List<Map<String, String>>> getAvailableVoices({
    String languagePrefix = 'en',
  }) async {
    try {
      final dynamic raw = await _tts.getVoices.timeout(
        const Duration(seconds: 3),
      );
      if (raw is! List) return [];
      final result = <Map<String, String>>[];
      final seen = <String>{};
      for (final item in raw) {
        if (item is Map) {
          final name = item['name']?.toString() ?? '';
          final locale = item['locale']?.toString() ?? '';
          if (name.isNotEmpty &&
              locale.toLowerCase().startsWith(languagePrefix.toLowerCase())) {
            if (!seen.add(name)) continue;
            result.add({'name': name, 'locale': locale});
          }
        }
      }
      result.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Speaks a short test sample using the provided voice settings.
  Future<void> previewVoice({
    required String voiceName,
    String voiceLocale = 'en-US',
    double pitch = 1.0,
    double rate = 0.48,
    String sampleText = "Hi, I'm Cooky. Let's make something delicious!",
  }) async {
    try {
      _ignoringTtsCancel = true;
      try {
        await _tts.stop();
      } finally {
        _ignoringTtsCancel = false;
      }
      if (voiceLocale.isNotEmpty) {
        await _tts.setLanguage(voiceLocale);
      }
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      if (voiceName.isNotEmpty) {
        await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
      }
      await _tts.speak(sampleText);
    } catch (_) {}
  }

  /// Preloads `ggml-base.en.bin` into native RAM so it is ready before the first
  /// utterance is transcribed.
  void preloadWhisperModel() {
    if (useWhisper) {
      unawaited(_whisper.preloadModel());
    }
  }

  Future<void> initialize({
    VoiceListeningMode initialMode = VoiceListeningMode.handsFree,
    bool initialMuted = false,
    bool startListeningImmediately = false,
  }) async {
    _cancelTimers();
    _listeningGeneration++;
    _clearSentence();
    _partialTranscript = '';
    _listeningMode = initialMode;
    _audioMuted = initialMuted;
    _isSessionActive = true;
    _isPaused = false;
    _autoRestartPaused = false;
    _fastFailures = 0;
    _isAudioBusy = false;
    _isAwake = false;
    _vadListening = false;
    _ignoringTtsCancel = false;
    _keepGlassesMic = false;
    _audioRoute.setVadCallbacks(
      onSpeechStart: _onVadSpeechStart,
      onUtterance: _onVadUtterance,
    );
    if (useWhisper) {
      unawaited(_whisper.preloadModel());
    }
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
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          if (_bluetoothMic == null)
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } catch (_) {
      // Ignore on non-iOS or test environments.
    }

    try {
      if (_ttsVoiceLocale != null && _ttsVoiceLocale!.isNotEmpty) {
        await _tts.setLanguage(_ttsVoiceLocale!);
      } else {
        await _tts.setLanguage('en-US');
      }
      await _tts.setSpeechRate(_ttsSpeechRate);
      await _tts.setPitch(_ttsPitch);
      if (_ttsVoiceName != null && _ttsVoiceName!.isNotEmpty) {
        await _tts.setVoice({
          'name': _ttsVoiceName!,
          'locale': _ttsVoiceLocale ?? 'en-US',
        });
      }
      _tts.setCompletionHandler(_onTtsFinished);
      _tts.setCancelHandler(() {
        if (_ignoringTtsCancel) return;
        _onTtsFinished();
      });
      _tts.setErrorHandler((_) {
        if (_ignoringTtsCancel) return;
        _onTtsFinished();
      });
      _tts.setProgressHandler((_, _, _, _) {
        if (_activityState == VoiceActivityState.speaking) {
          _extendTtsSafetyTimer();
        }
      });
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
            _onListenEnded();
          }
        },
        // Android reports "no match" or "speech timeout" whenever the user
        // pauses. These end the listen but are not a reason to stop
        // listening for good; _onListenEnded decides whether to restart.
        onError: (_) {
          if (!_isSessionActive) return;
          _onListenEnded();
        },
        // Otherwise the plugin starts Bluetooth voice recognition on every
        // listen, which puts the glasses in call mode by itself (#40).
        options: [SpeechToText.androidNoBluetooth],
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

    if (_isAwake && (_awakeTimeoutTimer?.isActive ?? false)) {
      // Heard "Hey Cooky" before a pause: keep listening for the command.
      _startListeningLoop(forceSingleTurn: true, expectSpeech: false);
      return;
    }
    _isAwake = false;

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
    _sendSentence();
  }

  void _sendSentence() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    final words = [
      _sentence,
      _partialTranscript.trim(),
    ].where((w) => w.isNotEmpty).join(' ');
    // Ignore the rest of the current listen only if its words were sent.
    if (_partialTranscript.trim().isNotEmpty) _turnDelivered = true;
    _sentence = '';
    _partialTranscript = '';
    _isAwake = false;
    if (words.isEmpty) return;
    stopListening();
    notifyListeners();
    onFinalUtterance?.call(words);
    if (_isSessionActive &&
        !_isPaused &&
        !_autoRestartPaused &&
        _listeningMode == VoiceListeningMode.handsFree &&
        _activityState == VoiceActivityState.idle) {
      _scheduleListeningRestart(delayMs: 100);
    }
  }

  void _scheduleAwakeTimeout() {
    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = Timer(_awakeWindow, () {
      if (!_isSessionActive || _isPaused) return;
      if (_partialTranscript.trim().isEmpty && _sentence.isEmpty) {
        _isAwake = false;
        _expectingSpeech = false;
        if (_activityState == VoiceActivityState.listening) {
          _statusHint = _withMicName('Say "Hey Cooky" or tap the mic');
        }
        if (_vadListening) {
          unawaited(_audioRoute.startVadListening(
            silenceDurationMs: kWakeWordSilenceMs,
          ));
        }
        notifyListeners();
      }
    });
  }

  void _extendTtsSafetyTimer() {
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = Timer(const Duration(seconds: 15), _onTtsFinished);
  }

  String _withMicName(String base) =>
      _bluetoothMic != null ? '$base (through $_bluetoothMic)' : base;

  void _clearSentence() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    _sentence = '';
    _isAwake = false;
  }

  void _cancelTimers() {
    _sentenceGapTimer?.cancel();
    _sentenceGapTimer = null;
    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    _expectingSpeechTimer?.cancel();
    _expectingSpeechTimer = null;
    _restartListenTimer?.cancel();
    _restartListenTimer = null;
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
  }

  void _onTtsFinished() {
    // Photo preparation owns the microphone until the photo can be taken.
    if (_preparingPhoto) return;
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
    if (!_isSessionActive) return;
    if (_activityState == VoiceActivityState.speaking) {
      _activityState = VoiceActivityState.idle;
      notifyListeners();
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
      _scheduleListeningRestart(delayMs: 60);
    }
  }

  /// Listens automatically for an answer only in hands-free mode.
  void listenForAnswer() => _listenForAnswer();

  void _listenForAnswer() {
    _awaitingAnswer = false;
    if (_listeningMode == VoiceListeningMode.tapToSpeak) {
      setActivityState(VoiceActivityState.idle, hint: 'Tap the mic to talk');
      return;
    }
    _autoRestartPaused = false;
    _fastFailures = 0;
    _restartListenTimer?.cancel();
    _restartListenTimer = Timer(const Duration(milliseconds: 30), () {
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
    } else if (mode == VoiceListeningMode.tapToSpeak) {
      _clearSentence();
      await stopListening(discard: true);
    }
    notifyListeners();
  }

  Future<void> toggleAudioMuted() async {
    _audioMuted = !_audioMuted;
    if (_audioMuted) {
      _photoPreparationId++;
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

  /// A tap starts a fresh turn, discarding any audio or words from before
  /// it. Completed utterances are sent automatically after speech ends.
  Future<MicTapResult> tapMic() async {
    if (_preparingPhoto) return MicTapResult.stopped;
    if (_isPaused) return MicTapResult.stopped;
    if (_micTapInProgress) return MicTapResult.stopped;
    _micTapInProgress = true;
    try {
      _awaitingAnswer = false;
      _clearSentence();
      await stopListening(discard: true);
      // Let any previous asynchronous recorder startup finish before retrying.
      await _listeningStartDone?.future;
      if (_activityState == VoiceActivityState.speaking) {
        await _stopSpeaking();
      }
      _autoRestartPaused = false;
      _fastFailures = 0;
      await _startListeningLoop(forceSingleTurn: true);
      return _activityState == VoiceActivityState.listening
          ? MicTapResult.listening
          : MicTapResult.unavailable;
    } finally {
      _micTapInProgress = false;
    }
  }

  Future<void> _stopSpeaking() async {
    _ttsSafetyTimer?.cancel();
    _ttsSafetyTimer = null;
    // The user is about to talk, so don't also listen for an answer.
    _awaitingAnswer = false;
    _activityState = VoiceActivityState.idle;
    _ignoringTtsCancel = true;
    try {
      await _tts.stop();
    } catch (_) {
    } finally {
      _ignoringTtsCancel = false;
    }
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
    final generation = ++_listeningGeneration;
    final startDone = Completer<void>();
    _listeningStartDone = startDone;
    try {
      final keepAwake =
          forceSingleTurn ||
          _sentence.isNotEmpty ||
          (_isAwake && (_awakeTimeoutTimer?.isActive ?? false));

      if (useWhisper && await _whisper.checkLocalModelReady()) {
        if (generation != _listeningGeneration) return;
        if (_keepGlassesMic) {
          await _reopenGlassesMic();
          if (generation != _listeningGeneration ||
              !_isSessionActive || _isPaused) return;
        }
        _isAwake =
            !requireWakeWord ||
            _listeningMode != VoiceListeningMode.handsFree ||
            keepAwake;
        final silenceMs = (_listeningMode == VoiceListeningMode.handsFree &&
                requireWakeWord &&
                !_isAwake &&
                _sentence.isEmpty)
            ? kWakeWordSilenceMs
            : kActiveListeningSilenceMs;
        final vadStarted = await _audioRoute.startVadListening(
          silenceDurationMs: silenceMs,
        );
        if (generation != _listeningGeneration ||
            !_isSessionActive || _isPaused) {
          if (vadStarted) await _audioRoute.stopVadListening(flush: false);
          return;
        }
        if (vadStarted && _isSessionActive && !_isPaused) {
          _vadListening = true;
          _speechAvailable = true;
          _partialTranscript = '';
          _turnDelivered = false;
          _isAwake =
              !requireWakeWord ||
              _listeningMode != VoiceListeningMode.handsFree ||
              keepAwake;
          _expectingSpeech = expectSpeech && forceSingleTurn && _sentence.isEmpty;
          _listenEndHandled = false;
          _activityState = VoiceActivityState.listening;
          _statusHint = _withMicName(
            waitingForWakeWord
                ? 'Say "Hey Cooky" or tap the mic'
                : _listeningMode == VoiceListeningMode.handsFree &&
                      !forceSingleTurn
                ? 'Listening hands-free… say a command or ask a question'
                : 'Listening… speak now',
          );
          _lastListenStartTime = DateTime.now();
          if (_expectingSpeech) {
            _scheduleExpectingSpeechTimeout();
          } else {
            _expectingSpeechTimer?.cancel();
            _expectingSpeechTimer = null;
          }
          notifyListeners();
          return;
        }
      }

      final ready = await _ensureSpeechInitialized();
      if (generation != _listeningGeneration) return;
      if (!ready || !_isSessionActive || _isPaused) {
        _activityState = VoiceActivityState.idle;
        notifyListeners();
        return;
      }
      if (_speech.isListening) return;
      // The recognizer keeps the mic it starts with.
      if (_keepGlassesMic) {
        await _reopenGlassesMic();
        if (generation != _listeningGeneration ||
            !_isSessionActive || _isPaused) return;
      }

      // Show "listening" only once the recognizer is really starting.
      _partialTranscript = '';
      _turnDelivered = false;
      _isAwake =
          !requireWakeWord ||
          _listeningMode != VoiceListeningMode.handsFree ||
          keepAwake;
      // Not when continuing a sentence: words were already heard.
      _expectingSpeech = expectSpeech && forceSingleTurn && _sentence.isEmpty;
      _listenEndHandled = false;
      _activityState = VoiceActivityState.listening;
      _statusHint = _withMicName(
        waitingForWakeWord
            ? 'Say "Hey Cooky" or tap the mic'
            : _listeningMode == VoiceListeningMode.handsFree && !forceSingleTurn
            ? 'Listening hands-free… say a command or ask a question'
            : 'Listening… speak now',
      );
      notifyListeners();

      _lastListenStartTime = DateTime.now();
      await _speech.listen(
        onResult: (result) {
          if (generation == _listeningGeneration) _onSpeechResult(result);
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
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
      startDone.complete();
      _listeningStartDone = null;
    }
  }

  void _scheduleExpectingSpeechTimeout([
    Duration duration = const Duration(seconds: 8),
  ]) {
    _expectingSpeechTimer?.cancel();
    _expectingSpeechTimer = Timer(duration, () {
      _expectingSpeechTimer = null;
      if (!_isSessionActive || _isPaused || !_vadListening || !_expectingSpeech) {
        return;
      }
      _vadListening = false;
      unawaited(_audioRoute.stopVadListening(flush: false));
      _onListenEnded();
    });
  }

  void _onVadSpeechStart() {
    if (!_isSessionActive || _isPaused || !_vadListening) return;
    if (_expectingSpeech && (_expectingSpeechTimer?.isActive ?? false)) {
      _scheduleExpectingSpeechTimeout(const Duration(seconds: 14));
    }
    if (_isAwake && (_awakeTimeoutTimer?.isActive ?? false)) {
      _scheduleAwakeTimeout();
    }
  }

  Future<void> _onVadUtterance(String wavPath) async {
    final generation = _listeningGeneration;
    if (!_isSessionActive || _isPaused || !_vadListening) {
      unawaited(_whisper.transcribeFile(wavPath));
      return;
    }
    final text = await _whisper.transcribeFile(wavPath);
    if (generation != _listeningGeneration ||
        !_isSessionActive || _isPaused || !_vadListening) return;
    if (text == null || text.trim().isEmpty) return;
    _onWhisperRecognizedWords(text.trim());
  }

  void _onWhisperRecognizedWords(String rawWords) {
    if (rawWords.isEmpty) return;

    var commandWords = rawWords;
    if (_listeningMode == VoiceListeningMode.handsFree && requireWakeWord) {
      final match = wakeWordPattern.firstMatch(rawWords);
      if (match != null) {
        if (!_isAwake) {
          _isAwake = true;
          _statusHint = _withMicName('Listening… speak now');
          if (_vadListening) {
            unawaited(_audioRoute.startVadListening(
              silenceDurationMs: kActiveListeningSilenceMs,
            ));
          }
        }
        commandWords = rawWords.substring(match.end).trim();
      } else if (!_isAwake) {
        // Still waiting for "Hey Cooky": ignore background speech/noise.
        return;
      }
    }

    if (commandWords.isEmpty) {
      // Heard "Hey Cooky" alone so far; stay awake waiting for the command.
      _scheduleAwakeTimeout();
      notifyListeners();
      return;
    }

    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    _expectingSpeechTimer?.cancel();
    _expectingSpeechTimer = null;
    _expectingSpeech = false;
    _askedAgain = false;
    _fastFailures = 0;
    _sentence = _sentence.isEmpty ? commandWords : '$_sentence $commandWords';
    _partialTranscript = '';
    _sendSentence();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    // Words from this listen were already kept when it ended early.
    if (_turnDelivered) return;
    final rawWords = result.recognizedWords.trim();
    if (rawWords.isEmpty) return;

    var commandWords = rawWords;
    if (_listeningMode == VoiceListeningMode.handsFree && requireWakeWord) {
      final match = wakeWordPattern.firstMatch(rawWords);
      if (match != null) {
        if (!_isAwake) {
          _isAwake = true;
          _statusHint = _withMicName('Listening… speak now');
          if (_vadListening) {
            unawaited(_audioRoute.startVadListening(
              silenceDurationMs: kActiveListeningSilenceMs,
            ));
          }
        }
        commandWords = rawWords.substring(match.end).trim();
      } else if (!_isAwake) {
        // Still waiting for "Hey Cooky": ignore background speech/noise.
        return;
      }
    }

    if (commandWords.isEmpty) {
      // Heard "Hey Cooky" alone so far; stay awake waiting for the command.
      _scheduleAwakeTimeout();
      notifyListeners();
      return;
    }

    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    final changed = commandWords != _partialTranscript.trim();
    _partialTranscript = commandWords;
    if (changed) {
      _sentenceGapTimer?.cancel();
      _sentenceGapTimer = Timer(_sentenceGap, _finishSentence);
    }
    notifyListeners();
    if (result.finalResult) _keepHeardWords();
  }

  Future<void> stopListening({bool discard = false}) async {
    _listeningGeneration++;
    _turnDelivered = true;
    _restartListenTimer?.cancel();
    _expectingSpeechTimer?.cancel();
    _expectingSpeechTimer = null;
    _listenEndHandled = true;
    final wasVadListening = _vadListening;
    _vadListening = false;
    if (_activityState == VoiceActivityState.listening) {
      _activityState = VoiceActivityState.idle;
    }
    _partialTranscript = '';
    notifyListeners();
    if (wasVadListening) {
      try {
        await _audioRoute.stopVadListening(flush: false);
      } catch (_) {}
    }
    try {
      if (_speechAvailable && (_speech.isListening || discard)) {
        if (discard) {
          await _speech.cancel();
        } else {
          await _speech.stop();
        }
      }
    } catch (_) {}
  }

  /// Waits for the spoken "hold still" prompt before allowing a glasses photo.
  /// Normal replies don't await speech completion, so they can't be used here.
  Future<bool> prepareForPhoto({required bool voiceGuidanceEnabled}) async {
    if (!_isSessionActive || _isPaused || _preparingPhoto) return false;
    _preparingPhoto = true;
    final preparationId = ++_photoPreparationId;
    _awaitingAnswer = false;
    _cancelTimers();
    _clearSentence();
    _turnDelivered = true;
    try {
      await stopListening();
      setActivityState(
        VoiceActivityState.capturingVision,
        hint: 'Look at your food and hold still…',
      );
      await _tts.stop();
      if (!_audioMuted && voiceGuidanceEnabled) {
        await _tts.awaitSpeakCompletion(true);
        final result = await _tts
            .speak('Look at your food and hold still.')
            .timeout(const Duration(seconds: 15));
        if (result != 1) return false;
      } else {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      // Release the Bluetooth HFP mic link before the glasses open their
      // camera stream so call mode never blocks photo capture (#40).
      if (_keepGlassesMic) await _audioRoute.clear();
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

  Future<void> speak(
    String text, {
    required bool voiceGuidanceEnabled,
    bool? isQuestion,
  }) async {
    if (_preparingPhoto) _photoPreparationId++;
    _restartListenTimer?.cancel();
    _ttsSafetyTimer?.cancel();
    _awakeTimeoutTimer?.cancel();
    _awakeTimeoutTimer = null;
    _isAwake = false;
    _awaitingAnswer = isQuestion ?? text.contains('?');

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
      _ignoringTtsCancel = true;
      try {
        await _tts.stop();
      } finally {
        _ignoringTtsCancel = false;
      }
      final result = await _tts.speak(text);
      if (result == null) {
        // In widget tests where no native MethodChannel is registered, finish immediately.
        _onTtsFinished();
        return;
      }
      // Generous fallback timeout based on utterance length (also extended on
      // word progress) so Bluetooth TTS is never cut off mid-sentence, while
      // still recovering if the OS drops the completion callback.
      final timeoutMs = (text.length * 150 + 6000).clamp(15000, 90000);
      _ttsSafetyTimer = Timer(
        Duration(milliseconds: timeoutMs),
        _onTtsFinished,
      );
    } catch (_) {
      _onTtsFinished();
    }
  }

  Future<void> shutdownSession() async {
    _listeningGeneration++;
    _photoPreparationId++;
    _vadListening = false;
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
