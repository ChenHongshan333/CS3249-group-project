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
}
