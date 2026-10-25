import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/services/voice_controller.dart';
import 'package:mobile/services/voice_intent_parser.dart';

import 'fake_voice_channels.dart';

void main() {
  final channels = FakeVoiceChannels();
  const tts = MethodChannel('flutter_tts');
  setUp(channels.install);
  tearDown(channels.uninstall);

  test('help uses a photo while ordinary cooking questions stay conversational', () {
    expect(VoiceIntentParser.parse('help').requiresVision, isTrue);
    expect(VoiceIntentParser.parse('Can you help me?').requiresVision, isTrue);
    expect(VoiceIntentParser.parse('How much salt do I need?').requiresVision, isFalse);
  });

  testWidgets('shutter feedback plays only when audio is unmuted', (tester) async {
    const audio = MethodChannel('cooktogether/audio_route');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, (call) async {
          calls.add(call.method);
          return null;
        });
    final voice = VoiceController();
    await voice.initialize();
    await voice.playPhotoShutter();
    expect(calls.where((call) => call == 'playShutter'), hasLength(1));
    await voice.setAudioMuted(true);
    await voice.playPhotoShutter();
    expect(calls.where((call) => call == 'playShutter'), hasLength(1));
    await voice.shutdownSession();
  });

  testWidgets('photo preparation waits for spoken countdown completion', (tester) async {
    final voice = VoiceController();
    await voice.initialize();
    final completedSpeech = Completer<int>();
    final spoken = <String>[];
    var awaitCompletion = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tts, (call) async {
          if (call.method == 'awaitSpeakCompletion') {
            awaitCompletion = call.arguments as bool;
          }
          if (call.method == 'speak') {
            spoken.add(call.arguments as String);
            if (awaitCompletion) return completedSpeech.future;
          }
          return 1;
        });
    bool? ready;
    final preparation = voice.prepareForPhoto(voiceGuidanceEnabled: true)
        .then((value) => ready = value);
    await tester.pump();
    expect(spoken, ['Look at your food and hold still.']);
    expect(ready, isNull);
    expect(voice.activityState, VoiceActivityState.capturingVision);
    await channels.ttsDone();
    await tester.pump(const Duration(seconds: 1));
    expect(channels.speechCalls, isNot(contains('listen')));
    completedSpeech.complete(1);
    await tester.pump();
    await preparation;
    expect(ready, isTrue);
    await voice.shutdownSession();
  });

  testWidgets('muted countdown waits three seconds and pause cancels it', (tester) async {
    final voice = VoiceController();
    await voice.initialize(initialMuted: true);
    bool? ready;
    final preparation = voice.prepareForPhoto(voiceGuidanceEnabled: true)
        .then((value) => ready = value);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(ready, isNull);
    expect(channels.spoken, isEmpty);
    await voice.setSessionPaused(true);
    await tester.pump(const Duration(seconds: 1));
    await preparation;
    expect(ready, isFalse);
    await voice.shutdownSession();
  });
}
