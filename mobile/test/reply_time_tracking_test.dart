import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/screens/cooking_screen.dart';
import 'package:mobile/screens/profile_screen.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/audio_route.dart';
import 'package:mobile/services/reply_time_store.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:mobile/services/whisper_transcriber.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'fake_phone_camera.dart';
import 'fake_voice_channels.dart';

class _FakeVadAudioRoute extends AudioRoute {
  void Function()? onSpeechStart;
  void Function(String wavPath)? onUtterance;
  int? nextSilenceMs;
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
  int? consumeLastVadSilenceMs() {
    final ms = nextSilenceMs;
    nextSilenceMs = null;
    return ms;
  }

  @override
  Future<bool> startVadListening({
    int silenceDurationMs = 850,
    int maxUtteranceMs = 12000,
    int preRollMs = 350,
    double? fixedFloor,
    double? noiseMultiplier,
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
  Future<String?> useBluetoothMic() async => null;

  @override
  Future<void> clear() async {
    vadActive = false;
  }
}

class _RecordingAssistant implements AssistantService {
  final List<(String, Map<String, dynamic>)> logged = [];
  AssistantResponse nextAsk = const AssistantResponse(reply: 'Cut them small.');
  AssistantResponse nextCheck = const AssistantResponse(
    reply: 'Looks chopped.',
    visualStatus: VisualCheckStatus.done,
  );
  Duration askDelay = Duration.zero;

  @override
  Future<AssistantResponse> askQuestion({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required String question,
    required List<ChatMessage> history,
    VisionCapture? visionCapture,
    List<String> acceptedSwaps = const [],
    String phase = 'cooking',
    Map<String, bool> ingredients = const {},
    Map<String, String> substitutes = const {},
    AssistantAction? pendingOffer,
  }) async {
    if (askDelay > Duration.zero) await Future<void>.delayed(askDelay);
    return nextAsk;
  }

  @override
  Future<AssistantResponse> checkStepWithVision({
    required String sessionId,
    required Recipe recipe,
    required int stepIndex,
    required VisionCapture visionCapture,
    String? userQuestion,
  }) async {
    return nextCheck.copyWithCapture(visionCapture);
  }

  @override
  Future<void> logEvent({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    logged.add((type, data));
  }

  @override
  Future<void> warmUp() async {}
}

extension on AssistantResponse {
  AssistantResponse copyWithCapture(VisionCapture capture) => AssistantResponse(
    reply: reply,
    visualStatus: visualStatus,
    visionCapture: capture.copyWith(status: visualStatus),
    offer: offer,
    action: action,
    isError: isError,
  );
}

class _TestVoiceController extends VoiceController {
  VoiceUtteranceTiming? queuedTiming;

  @override
  VoiceUtteranceTiming? consumeLastUtteranceTiming() {
    final t = queuedTiming;
    queuedTiming = null;
    return t;
  }

  @override
  Future<void> initialize({
    VoiceListeningMode initialMode = VoiceListeningMode.handsFree,
    bool initialMuted = false,
    bool startListeningImmediately = false,
  }) async {}

  @override
  Future<void> speak(
    String text, {
    required bool voiceGuidanceEnabled,
    bool? isQuestion,
  }) async {}

  @override
  Future<void> shutdownSession() async {}
}

void main() {
  final channels = FakeVoiceChannels();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channels.install();
  });

  tearDown(channels.uninstall);

  test(
    'VAD timing subtracts native silenceMs and ignores standalone wake word',
    () async {
      var now = DateTime(2026, 11, 21, 18, 0, 0);
      final audio = _FakeVadAudioRoute();
      final whisper = WhisperTranscriber(
        transcribeOverride: (path) async {
          now = now.add(const Duration(milliseconds: 350));
          if (path == '/tmp/wake.wav') return 'Hey Cooky';
          return 'next step';
        },
        audioRoute: audio,
      );
      final voice = VoiceController(
        speech: SpeechToText(),
        audioRoute: audio,
        whisperTranscriber: whisper,
        now: () => now,
      );
      final received = <(String, VoiceUtteranceTiming?)>[];
      voice.onFinalUtterance = (text) {
        received.add((text, voice.consumeLastUtteranceTiming()));
      };

      await voice.initialize(
        initialMode: VoiceListeningMode.handsFree,
        startListeningImmediately: true,
      );

      // Wake-word alone should not start a command timer.
      audio.nextSilenceMs = 450;
      audio.onUtterance?.call('/tmp/wake.wav');
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      // Actual command fires 2 seconds later; Whisper takes 350 ms; silence was 850 ms.
      now = now.add(const Duration(seconds: 2));
      final vadFiredAt = now;
      audio.nextSilenceMs = 850;
      audio.onUtterance?.call('/tmp/cmd.wav');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.$1, 'next step');
      final timing = received.single.$2!;
      expect(
        timing.speechEndedAt,
        vadFiredAt.subtract(const Duration(milliseconds: 850)),
      );
      expect(timing.sttMs, 1200);
      expect(timing.source, 'vad_whisper');
      expect(timing.silenceWindowMs, 850);

      await voice.shutdownSession();
    },
  );

  test(
    'VAD timing falls back to active silence window when native silenceMs is omitted',
    () async {
      var now = DateTime(2026, 11, 21, 18, 0, 0);
      final audio = _FakeVadAudioRoute();
      final whisper = WhisperTranscriber(
        transcribeOverride: (_) async {
          now = now.add(const Duration(milliseconds: 200));
          return 'Hey Cooky how long';
        },
        audioRoute: audio,
      );
      final voice = VoiceController(
        speech: SpeechToText(),
        audioRoute: audio,
        whisperTranscriber: whisper,
        now: () => now,
      );
      VoiceUtteranceTiming? captured;
      voice.onFinalUtterance = (_) {
        captured = voice.consumeLastUtteranceTiming();
      };

      await voice.initialize(
        initialMode: VoiceListeningMode.handsFree,
        startListeningImmediately: true,
      );
      final vadFiredAt = now;
      audio.onUtterance?.call('/tmp/combined.wav');
      await Future<void>.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(
        captured!.speechEndedAt,
        vadFiredAt.subtract(
          const Duration(milliseconds: VoiceController.kWakeWordSilenceMs),
        ),
      );
      expect(captured!.sttMs, VoiceController.kWakeWordSilenceMs + 200);

      await voice.shutdownSession();
    },
  );

  test(
    'speech_to_text fallback timestamps speechEndedAt at last speech result before _sentenceGap',
    () async {
      var now = DateTime(2026, 11, 21, 18, 0, 0);
      final audio = _FakeVadAudioRoute();
      final voice = VoiceController(
        speech: SpeechToText(),
        audioRoute: audio,
        now: () => now,
      )..useWhisper = false;
      VoiceUtteranceTiming? captured;
      voice.onFinalUtterance = (_) {
        captured = voice.consumeLastUtteranceTiming();
      };

      await voice.initialize(
        initialMode: VoiceListeningMode.handsFree,
        startListeningImmediately: true,
      );
      await channels.heard('Hey Cooky set a timer');
      final speechAt = now;
      now = now.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      expect(captured, isNotNull);
      expect(captured!.speechEndedAt, speechAt);
      expect(captured!.source, 'speech_to_text');

      await voice.shutdownSession();
    },
  );

  testWidgets(
    'CookingScreen records voice LLM and local action timings and excludes errors, mock, and typed text',
    (tester) async {
      final store = ReplyTimeStore(storageKey: 'test.cooking.replyTimes');
      final assistant = _RecordingAssistant();
      final voice = _TestVoiceController();
      final recipe = kStarterRecipes.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CookingScreen(
              recipe: recipe,
              preferences: const UserPreferences(
                serverBaseUrl: 'https://backend.test',
                voiceGuidance: false,
              ),
              glassesService: MetaWearablesDatGlassesService(),
              assistantService: assistant,
              voiceController: voice,
              initialCheckedIngredients: recipe.ingredients.toSet(),
              initialListeningMode: VoiceListeningMode.handsFree,
              onFinishCooking:
                  ({
                    required elapsedSeconds,
                    required stepsCompleted,
                    required visualChecksCount,
                  }) {},
              onExitToHome: () {},
              onPauseAndLeave: () {},
              onShowToast: (_) {},
              replyTimeStore: store,
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Voice start cooking -> step_next with ms and localAction recorded
      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 220)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call("let's start");
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 2. Voice LLM /ask question -> question logged + llmAsk recorded
      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 300)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call('How small should I cut it?');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 3. Errored /ask -> logged with error: true, excluded from store
      assistant.nextAsk = const AssistantResponse(
        reply: 'Sorry, unavailable.',
        isError: true,
      );
      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 300)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call('Can I use oil?');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 4. Local voice timer command -> localAction recorded without unsupported event type
      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 180)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call('set a 2 minute timer');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // 5. Typed text -> logged with input: text, excluded from voice medians
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Type instead'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'say that again');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      // 6. Voice finish cooking -> session_end carries full replyTimes summary
      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 150)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call('finish cooking');
      await tester.pump();

      final summary = await store.loadSummary();
      expect(summary.llmAskCount, 1);
      expect(summary.llmAskSamples.single, greaterThanOrEqualTo(300));
      expect(summary.localActionCount, 3);

      // Only existing backend EventTypes are emitted (never 'voice_action').
      expect(
        assistant.logged.map((e) => e.$1),
        isNot(contains('voice_action')),
      );

      final questionEvents = assistant.logged
          .where((e) => e.$1 == 'question')
          .toList();
      expect(questionEvents, hasLength(2));
      expect(questionEvents[0].$2['input'], 'voice');
      expect(questionEvents[0].$2['sttMs'], greaterThanOrEqualTo(300));
      expect(questionEvents[0].$2['error'], isNull);
      expect(questionEvents[1].$2['error'], isTrue);

      final typedRepeat = assistant.logged.singleWhere(
        (e) => e.$1 == 'step_repeat',
      );
      expect(typedRepeat.$2['input'], 'text');

      final sessionEnd = assistant.logged.singleWhere(
        (e) => e.$1 == 'session_end',
      );
      final sessionReplyTimes =
          sessionEnd.$2['replyTimes'] as Map<String, dynamic>;
      expect((sessionReplyTimes['llmAsk'] as Map)['count'], 1);
      expect((sessionReplyTimes['localAction'] as Map)['count'], 3);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('MockAssistantService excludes /ask from ReplyTimeStore', (
    tester,
  ) async {
    final store = ReplyTimeStore(storageKey: 'test.mock.replyTimes');
    final voice = _TestVoiceController();
    final recipe = kStarterRecipes.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CookingScreen(
            recipe: recipe,
            preferences: const UserPreferences(
              serverBaseUrl: '',
              voiceGuidance: false,
            ),
            glassesService: MetaWearablesDatGlassesService(),
            assistantService: const MockAssistantService(),
            voiceController: voice,
            initialCheckedIngredients: recipe.ingredients.toSet(),
            initialListeningMode: VoiceListeningMode.handsFree,
            onFinishCooking:
                ({
                  required elapsedSeconds,
                  required stepsCompleted,
                  required visualChecksCount,
                }) {},
            onExitToHome: () {},
            onPauseAndLeave: () {},
            onShowToast: (_) {},
            replyTimeStore: store,
          ),
        ),
      ),
    );
    await tester.pump();

    voice.onFinalUtterance?.call("let's start");
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    voice.onFinalUtterance?.call('How hot should it be?');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final summary = await store.loadSummary();
    expect(summary.localActionCount, 1);
    expect(summary.llmAskCount, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'ProfileScreen Developer section shows persisted medians, copies JSON, and resets them',
    (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final store = ReplyTimeStore(storageKey: 'test.profile.replyTimes');
      await store.recordLlmAsk(1450);
      await store.recordLocalAction(320);
      await store.recordVisualCheck(llmMs: 1200, totalMs: 4100);
      final toasts = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileScreen(
              preferences: const UserPreferences(),
              history: const [],
              onSavePreferences: (_) {},
              onOpenHistory: () {},
              onBack: () {},
              onShowToast: toasts.add,
              replyTimeStore: store,
            ),
          ),
        ),
      );
      await tester.pump();

      final listScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Developer'),
        200,
        scrollable: listScrollable,
      );
      await tester.tap(find.text('Developer'));
      await tester.pumpAndSettle();

      expect(find.text('1450 ms · 1 sample'), findsOneWidget);
      expect(find.text('320 ms · 1 sample'), findsOneWidget);
      expect(find.text('Vision LLM 1200 ms · E2E 4100 ms · 1 sample'), findsOneWidget);

      await tester.ensureVisible(find.text('Copy JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy JSON'));
      await tester.pumpAndSettle();

      expect(copiedText, isNotNull);
      final parsed = jsonDecode(copiedText!) as Map<String, dynamic>;
      expect((parsed['llmAsk'] as Map)['medianMs'], 1450);
      expect((parsed['localAction'] as Map)['medianMs'], 320);
      expect(toasts, contains('Reply times copied'));

      await tester.scrollUntilVisible(
        find.text('Reset reply times'),
        200,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(find.text('Reset reply times'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset reply times'));
      await tester.pumpAndSettle();

      expect(find.text('No samples yet'), findsNWidgets(3));
      expect((await store.loadSummary()).llmAskCount, 0);
    },
  );

  testWidgets(
    'CookingScreen records voice visual check breakdown and excludes forced checks',
    (tester) async {
      final store = ReplyTimeStore(storageKey: 'test.check.replyTimes');
      final assistant = _RecordingAssistant();
      final voice = _TestVoiceController();
      final recipe = kStarterRecipes.first;

      Future<void> pumpWithForced(String forced) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CookingScreen(
                recipe: recipe,
                preferences: UserPreferences(
                  serverBaseUrl: 'https://backend.test',
                  voiceGuidance: false,
                  forcedCheckResult: forced,
                ),
                glassesService: MetaWearablesDatGlassesService(),
                assistantService: assistant,
                voiceController: voice,
                phoneCamera: FakePhoneCamera(photo: FakePhoneCamera.samplePhoto),
                initialCheckedIngredients: recipe.ingredients.toSet(),
                initialListeningMode: VoiceListeningMode.handsFree,
                onFinishCooking:
                    ({
                      required elapsedSeconds,
                      required stepsCompleted,
                      required visualChecksCount,
                    }) {},
                onExitToHome: () {},
                onPauseAndLeave: () {},
                onShowToast: (_) {},
                replyTimeStore: store,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpWithForced('');
      voice.onFinalUtterance?.call("let's start");
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      voice.queuedTiming = VoiceUtteranceTiming(
        speechEndedAt: DateTime.now().subtract(const Duration(milliseconds: 250)),
        transcriptReadyAt: DateTime.now(),
        source: 'vad_whisper',
        silenceWindowMs: 850,
      );
      voice.onFinalUtterance?.call('check this step');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      var summary = await store.loadSummary();
      expect(summary.checkStepCount, 1);
      expect(summary.checkStepTotalMedianMs, greaterThanOrEqualTo(250));

      final checkEvent = assistant.logged.singleWhere((e) => e.$1 == 'check');
      expect(checkEvent.$2['input'], 'voice');
      expect(checkEvent.$2['llmMs'], isNotNull);
      expect(checkEvent.$2['captureMs'], isNotNull);

      // Forced check should still log forced: true, but not increment ReplyTimeStore.
      await pumpWithForced('done');
      voice.onFinalUtterance?.call("let's start");
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      voice.onFinalUtterance?.call('check this step');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      summary = await store.loadSummary();
      expect(summary.checkStepCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
