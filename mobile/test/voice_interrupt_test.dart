import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'fake_voice_channels.dart';

void main() {
  final channels = FakeVoiceChannels();
  setUp(channels.install);
  tearDown(channels.uninstall);

  // #28
  for (final mode in VoiceListeningMode.values) {
    testWidgets(
      'tapping the mic while speaking stops and listens (${mode.name})',
      (tester) async {
        final voice = VoiceController(speech: SpeechToText.withMethodChannel());
        await voice.initialize(initialMode: mode);
        await voice.speak(
          'Step 1: Wash & prepare. Rinse the greens.',
          voiceGuidanceEnabled: true,
        );
        expect(voice.activityState, VoiceActivityState.speaking);

        final result = await voice.tapMic();
        await channels.speechStatus('listening');

        expect(result, MicTapResult.listening);
        expect(channels.ttsCalls.last, 'stop');
        expect(channels.speechCalls, contains('listen'));
        expect(voice.activityState, VoiceActivityState.listening);

        // A late "done" from the phone doesn't start speaking or listening
        // over the user.
        await channels.ttsDone();
        expect(voice.activityState, VoiceActivityState.listening);

        await voice.shutdownSession();
        // Let the plugin's own listen timeout run out.
        await tester.pump(const Duration(seconds: 31));
      },
    );
  }

  group('saying "hold on" while speaking', () {
    int listens() => channels.speechCalls.where((c) => c == 'listen').length;

    Future<VoiceController> speaking(
      String text, {
      bool interrupt = true,
    }) async {
      final voice = VoiceController(speech: SpeechToText.withMethodChannel())
        ..interruptByVoice = interrupt;
      await voice.initialize(initialMode: VoiceListeningMode.tapToSpeak);
      await voice.speak(text, voiceGuidanceEnabled: true);
      await channels.speechStatus('listening');
      return voice;
    }

    Future<void> finish(WidgetTester tester, VoiceController voice) async {
      await voice.shutdownSession();
      await tester.pump(const Duration(seconds: 31));
    }

    testWidgets('stops the speech and listens', (tester) async {
      final voice = await speaking('Step 1: Wash & prepare. Rinse the greens.');
      // It listens for "hold on" while it speaks.
      expect(listens(), 1);
      expect(voice.activityState, VoiceActivityState.speaking);

      await channels.heard('hold on');
      await tester.pump();

      expect(channels.ttsCalls.last, 'stop');
      expect(listens(), 2);
      expect(voice.activityState, VoiceActivityState.listening);
      await finish(tester, voice);
    });

    testWidgets("ignores its own voice, such as 'wait' in the step", (
      tester,
    ) async {
      final voice = await speaking('Wait for the water to boil.');
      await channels.heard('wait for the water');
      await tester.pump();

      expect(channels.ttsCalls.last, 'speak');
      expect(voice.activityState, VoiceActivityState.speaking);
      // "Hold on" isn't in the step, so it still works.
      await channels.heard('hold on');
      await tester.pump();
      expect(channels.ttsCalls.last, 'stop');
      await finish(tester, voice);
    });

    testWidgets('ignores longer speech that only starts with a stop word', (
      tester,
    ) async {
      final voice = await speaking('Rinse the greens.');
      await channels.heard('stop the car at the next corner please');
      await tester.pump();
      expect(voice.activityState, VoiceActivityState.speaking);
      await finish(tester, voice);
    });

    testWidgets('after speaking, the listen for "hold on" ends first', (
      tester,
    ) async {
      final voice = await speaking('Would you like a timer?');
      await channels.ttsDone();
      await tester.pump(const Duration(milliseconds: 200));

      // Stopped, then listened for the answer.
      expect(channels.speechCalls.where((c) => c == 'stop'), isNotEmpty);
      expect(listens(), 2);
      await finish(tester, voice);
    });

    testWidgets('can be turned off', (tester) async {
      final voice = await speaking('Rinse the greens.', interrupt: false);
      expect(listens(), 0);
      await finish(tester, voice);
    });
  });
}
