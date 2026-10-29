import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'fake_voice_channels.dart';

// #40: the glasses drop their mic link by themselves, so it is opened
// again before each listen and each spoken reply.
void main() {
  final channels = FakeVoiceChannels();
  setUp(channels.install);
  tearDown(channels.uninstall);

  int micRequests() =>
      channels.audioRouteCalls.where((c) => c == 'useBluetoothMic').length;

  Future<void> finish(WidgetTester tester, VoiceController voice) async {
    await voice.shutdownSession();
    // Let the plugin's own listen timeout run out.
    await tester.pump(const Duration(seconds: 31));
  }

  testWidgets('opens the glasses mic again before speaking and listening', (
    tester,
  ) async {
    channels.headset = 'Ray-Ban Meta';
    final voice = VoiceController(speech: SpeechToText.withMethodChannel());
    await voice.initialize(initialMode: VoiceListeningMode.tapToSpeak);
    expect(voice.bluetoothMic, 'Ray-Ban Meta');
    expect(micRequests(), 1);

    await voice.speak('Step 1: Rinse the greens.', voiceGuidanceEnabled: true);
    expect(micRequests(), 2);

    await channels.ttsDone();
    await voice.tapMic();
    expect(micRequests(), 3);
    expect(channels.speechCalls, contains('listen'));
    await finish(tester, voice);
  });

  testWidgets('uses the phone mic for a turn when the link stays down', (
    tester,
  ) async {
    channels.headset = 'Ray-Ban Meta';
    final voice = VoiceController(speech: SpeechToText.withMethodChannel());
    await voice.initialize(initialMode: VoiceListeningMode.tapToSpeak);

    channels.headset = null;
    await voice.tapMic();
    expect(voice.bluetoothMic, isNull);
    await voice.stopListening();

    // It keeps trying on later turns.
    channels.headset = 'Ray-Ban Meta';
    await voice.tapMic();
    expect(voice.bluetoothMic, 'Ray-Ban Meta');
    await finish(tester, voice);
  });

  testWidgets('without a headset it asks only once', (tester) async {
    final voice = VoiceController(speech: SpeechToText.withMethodChannel());
    await voice.initialize(initialMode: VoiceListeningMode.tapToSpeak);
    await voice.speak('Step 1: Rinse the greens.', voiceGuidanceEnabled: true);
    await channels.ttsDone();
    await voice.tapMic();

    expect(micRequests(), 1);
    expect(voice.bluetoothMic, isNull);
    await finish(tester, voice);
  });

  testWidgets('phone mic only never asks for the glasses mic', (tester) async {
    channels.headset = 'Ray-Ban Meta';
    final voice = VoiceController(speech: SpeechToText.withMethodChannel())
      ..useGlassesMic = false;
    await voice.initialize(initialMode: VoiceListeningMode.tapToSpeak);
    await voice.tapMic();

    expect(micRequests(), 0);
    expect(channels.audioRouteCalls, contains('clear'));
    expect(voice.bluetoothMic, isNull);
    await finish(tester, voice);
  });
}
