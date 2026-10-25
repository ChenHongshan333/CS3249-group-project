import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/services/audio_route.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:mobile/services/whisper_transcriber.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'fake_voice_channels.dart';

class _FakeVadAudioRoute extends AudioRoute {
  void Function()? onSpeechStart;
  void Function(String wavPath)? onUtterance;
  bool vadActive = false;

  @override
  void setVadCallbacks({
    void Function()? onSpeechStart,
    void Function(String wavPath)? onUtterance,
  }) {
    this.onSpeechStart = onSpeechStart;
    this.onUtterance = onUtterance;
  }

  @override
  Future<bool> startVadListening({
    int silenceDurationMs = 1000,
    int maxUtteranceMs = 12000,
    int preRollMs = 600,
  }) async {
    vadActive = true;
    return true;
  }

  @override
  Future<String?> stopVadListening({bool flush = false}) async {
    vadActive = false;
    return null;
  }

  @override
  Future<String?> useBluetoothMic() async => 'Ray-Ban Meta';

  @override
  Future<void> clear() async {
    vadActive = false;
  }
}

void main() {
  final channels = FakeVoiceChannels();
  setUp(channels.install);
  tearDown(channels.uninstall);

  late VoiceController voice;
  late int nothingHeard;
  late int stopped;

  Future<void> start(VoiceListeningMode mode, {bool listenNow = false}) async {
    nothingHeard = 0;
    stopped = 0;
    voice = VoiceController(speech: SpeechToText.withMethodChannel())
      // Only the listens these tests are about; "hold on" has its own.
      ..interruptByVoice = false
      ..onNothingHeard = (() => nothingHeard++)
      ..onListeningStopped = (() => stopped++);
    await voice.initialize(
      initialMode: mode,
      startListeningImmediately: listenNow,
    );
  }

  int listens() => channels.speechCalls.where((c) => c == 'listen').length;

  /// One listen that ends with nothing heard, the way Android reports it:
  /// an error and then "done".
  Future<void> hearNothing(WidgetTester tester) async {
    await channels.speechStatus('listening');
    await channels.speechError('error_no_match');
    await channels.speechStatus('doneNoResult');
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await voice.shutdownSession();
    // Let the plugin's own listen timeout run out.
    await tester.pump(const Duration(seconds: 31));
  }

  // #14
  testWidgets('after a mic tap that hears nothing, it asks again once', (
    tester,
  ) async {
    await start(VoiceListeningMode.tapToSpeak);
    await voice.tapMic();
    await hearNothing(tester);
    expect(nothingHeard, 1);
    expect(stopped, 0);

    // The app asks "…Could you say it again?" and listens when it's done.
    await voice.speak(
      "Sorry, I didn't catch that. Could you say it again?",
      voiceGuidanceEnabled: true,
    );
    await channels.ttsDone();
    await tester.pump(const Duration(milliseconds: 200));
    expect(listens(), 2);

    // Nothing again: listening stops, with a hint instead of a second ask.
    await hearNothing(tester);
    expect(nothingHeard, 1);
    expect(stopped, 1);
    await finish(tester);
  });

  testWidgets('words heard after a mic tap are sent, with no ask again', (
    tester,
  ) async {
    await start(VoiceListeningMode.tapToSpeak);
    final sent = <String>[];
    voice.onFinalUtterance = sent.add;
    await voice.tapMic();
    await channels.speechStatus('listening');
    await channels.heard('how small should I cut it', isFinal: true);
    await channels.speechStatus('done');
    await tester.pump(const Duration(seconds: 2));

    expect(sent, ['how small should I cut it']);
    expect(nothingHeard, 0);
    expect(stopped, 0);
    await finish(tester);
  });

  testWidgets('hands-free backs off after quick failures, then says so', (
    tester,
  ) async {
    await start(VoiceListeningMode.handsFree, listenNow: true);
    expect(listens(), 1);

    // Each failed listen counts once, though Android reports it twice.
    // 0.8 s between the first retries, then 2, 4 and 8 s.
    for (final wait in [800, 800, 2000, 4000, 8000]) {
      await hearNothing(tester);
      final before = listens();
      await tester.pump(Duration(milliseconds: wait - 100));
      expect(listens(), before, reason: 'waits about $wait ms');
      await tester.pump(const Duration(milliseconds: 200));
      expect(listens(), before + 1);
    }
    expect(stopped, 0);

    // The sixth quick failure in a row stops listening.
    await hearNothing(tester);
    expect(stopped, 1);
    expect(voice.listeningStopped, isTrue);
    await tester.pump(const Duration(seconds: 20));
    expect(listens(), 6);
    // Continuous listening never asks "could you say it again?".
    expect(nothingHeard, 0);

    // A tap starts listening again.
    await voice.tapMic();
    expect(listens(), 7);
    expect(voice.listeningStopped, isFalse);
    await finish(tester);
  });

  testWidgets('hands-free ignores speech until "Hey Cooky" is said', (
    tester,
  ) async {
    await start(VoiceListeningMode.handsFree, listenNow: true);
    final sent = <String>[];
    voice.onFinalUtterance = sent.add;

    await channels.speechStatus('listening');
    expect(voice.waitingForWakeWord, isTrue);

    // Background speech without the wake word is ignored.
    await channels.heard('pass me the salt please');
    await tester.pump(const Duration(seconds: 2));
    expect(sent, isEmpty);
    expect(voice.partialTranscript, isEmpty);

    // Saying "Hey Cooky" (or iOS STT's "Hey cookie") wakes it and strips the prefix.
    await channels.heard('Hey cookie, how small should I cut it');
    await tester.pump();
    expect(voice.waitingForWakeWord, isFalse);
    expect(voice.partialTranscript, 'how small should I cut it');

    await tester.pump(const Duration(seconds: 2));
    expect(sent, ['how small should I cut it']);
    await finish(tester);
  });

  testWidgets('saying "Hey Cooky" then pausing keeps listening for the command', (
    tester,
  ) async {
    await start(VoiceListeningMode.handsFree, listenNow: true);
    final sent = <String>[];
    voice.onFinalUtterance = sent.add;

    await channels.speechStatus('listening');
    await channels.heard('Hey Cooky');
    await tester.pump();
    expect(voice.waitingForWakeWord, isFalse);
    expect(voice.partialTranscript, isEmpty);

    // Even if the recognizer ends that listen during the pause, it stays awake.
    await channels.speechStatus('done');
    await tester.pump();
    expect(voice.waitingForWakeWord, isFalse);

    await channels.speechStatus('listening');
    await channels.heard('next step');
    await tester.pump(const Duration(seconds: 2));
    expect(sent, ['next step']);
    await finish(tester);
  });

  testWidgets('Whisper + VAD pipeline transcribes "Hey Cooky" and commands', (
    tester,
  ) async {
    final fakeAudioRoute = _FakeVadAudioRoute();
    final transcripts = <String, String>{
      '/tmp/noise.wav': WhisperTranscriber.cleanWhisperTranscript(
        '[BLANK_AUDIO] (music)',
      ),
      '/tmp/chatter.wav': 'Pass me the olive oil',
      '/tmp/wake_only.wav': 'Hey Cooky.',
      '/tmp/command.wav': 'How thin should I slice the garlic?',
      '/tmp/combined.wav': 'Hey Cody, next step please.',
    };
    final whisper = WhisperTranscriber(
      transcribeOverride: (path) async => transcripts[path],
    );

    voice = VoiceController(
      speech: SpeechToText.withMethodChannel(),
      whisperTranscriber: whisper,
      audioRoute: fakeAudioRoute,
    )..interruptByVoice = false;

    final sent = <String>[];
    voice.onFinalUtterance = sent.add;

    await voice.initialize(
      initialMode: VoiceListeningMode.handsFree,
      startListeningImmediately: true,
    );
    expect(voice.isUsingWhisper, isTrue);
    expect(voice.waitingForWakeWord, isTrue);
    expect(voice.bluetoothMic, 'Ray-Ban Meta');

    // 1. Blank audio / background noise and non-wake-word chatter are ignored.
    fakeAudioRoute.onUtterance?.call('/tmp/noise.wav');
    await tester.pump();
    fakeAudioRoute.onUtterance?.call('/tmp/chatter.wav');
    await tester.pump();
    expect(sent, isEmpty);
    expect(voice.waitingForWakeWord, isTrue);

    // 2. Saying "Hey Cooky" alone wakes it up and waits for the command.
    fakeAudioRoute.onUtterance?.call('/tmp/wake_only.wav');
    await tester.pump();
    expect(voice.waitingForWakeWord, isFalse);
    expect(sent, isEmpty);

    // 3. The follow-up utterance is transcribed by Whisper and sent immediately.
    fakeAudioRoute.onUtterance?.call('/tmp/command.wav');
    await tester.pump();
    expect(sent, ['How thin should I slice the garlic?']);

    // Wait for hands-free listening to restart in wake-word standby.
    await tester.pump(const Duration(milliseconds: 700));
    expect(voice.waitingForWakeWord, isTrue);

    // 4. Phonetic variant ("Hey Cody, next step please.") in a single breath works.
    fakeAudioRoute.onUtterance?.call('/tmp/combined.wav');
    await tester.pump();
    expect(sent, [
      'How thin should I slice the garlic?',
      'next step please.',
    ]);

    expect(whisper.isReady, isTrue);
    expect(whisper.isLoadedInMemory, isTrue);
    expect(VoiceController.wakeWordPattern.hasMatch('Hey Pookie'), isTrue);
    expect(VoiceController.wakeWordPattern.hasMatch('Hey-Cooky'), isTrue);

    await finish(tester);
  });
}
