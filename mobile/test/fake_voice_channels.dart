import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the speech recognition and text-to-speech plugins, so
/// tests can see what the app asked for and play back what the phone says.
class FakeVoiceChannels {
  static const _speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
  static const _tts = MethodChannel('flutter_tts');
  static const _audioRoute = MethodChannel('cooktogether/audio_route');

  /// Method names the app called on each plugin, in order.
  final List<String> speechCalls = [];
  final List<String> ttsCalls = [];
  final List<String> audioRouteCalls = [];

  /// The Bluetooth headset whose mic the app gets, or null for the phone's
  /// own mic. Change it to drop the link or bring it back.
  String? headset;

  /// What was passed to `speak`.
  final List<String> spoken = [];

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    speechCalls.clear();
    ttsCalls.clear();
    audioRouteCalls.clear();
    spoken.clear();
    _messenger.setMockMethodCallHandler(_speech, (call) async {
      speechCalls.add(call.method);
      return switch (call.method) {
        'locales' => <dynamic>[],
        _ => true,
      };
    });
    _messenger.setMockMethodCallHandler(_tts, (call) async {
      ttsCalls.add(call.method);
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    // By default no Bluetooth headset: the phone's own mic stays in use.
    headset = null;
    _messenger.setMockMethodCallHandler(_audioRoute, (call) async {
      audioRouteCalls.add(call.method);
      return call.method == 'useBluetoothMic' ? headset : null;
    });
  }

  void uninstall() {
    for (final channel in [_speech, _tts, _audioRoute]) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
  }

  Future<void> _fromPhone(MethodChannel channel, String method, Object? args) {
    return _messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  /// The recognizer reports a status: "listening", "notListening", "done"
  /// or "doneNoResult".
  Future<void> speechStatus(String status) =>
      _fromPhone(_speech, 'notifyStatus', status);

  /// The recognizer heard [words] so far.
  Future<void> heard(String words, {bool isFinal = false}) => _fromPhone(
    _speech,
    'textRecognition',
    jsonEncode({
      'alternates': [
        {'recognizedWords': words, 'confidence': 0.9},
      ],
      'resultType': isFinal ? 2 : 0,
    }),
  );

  /// The recognizer gave up, as Android does with "no match".
  Future<void> speechError(String message) => _fromPhone(
    _speech,
    'notifyError',
    jsonEncode({'errorMsg': message, 'permanent': false}),
  );

  /// The phone finished saying the last utterance.
  Future<void> ttsDone() => _fromPhone(_tts, 'speak.onComplete', null);
}
