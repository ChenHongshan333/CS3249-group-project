import 'dart:async';

import 'package:flutter/services.dart';

/// Chooses which microphone speech is recorded from and manages native 16 kHz
/// mono PCM Voice Activity Detection (VAD) audio capture for Whisper. Backed by
/// native code in `ios/Runner/AppDelegate.swift` and
/// `android/app/src/main/kotlin/.../MainActivity.kt`; on other platforms, the
/// web build and tests, routing does nothing and shutter feedback falls back to
/// a system click.
class AudioRoute {
  const AudioRoute();

  static const MethodChannel _channel = MethodChannel(
    'cooktogether/audio_route',
  );

  static void Function()? _onVadSpeechStart;
  static void Function(String wavPath)? _onVadUtterance;
  static bool _handlerRegistered = false;

  /// Registers callbacks invoked by the native 16 kHz VAD recorder when voice
  /// activity starts and when a complete utterance `.wav` file is ready.
  void setVadCallbacks({
    void Function()? onSpeechStart,
    void Function(String wavPath)? onUtterance,
  }) {
    _onVadSpeechStart = onSpeechStart;
    _onVadUtterance = onUtterance;
    if (!_handlerRegistered) {
      _handlerRegistered = true;
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onVadSpeechStart':
        _onVadSpeechStart?.call();
        return null;
      case 'onVadUtterance':
        final args = call.arguments;
        if (args is Map) {
          final path = args['path'] as String?;
          if (path != null && path.isNotEmpty) {
            _onVadUtterance?.call(path);
          }
        } else if (args is String && args.isNotEmpty) {
          _onVadUtterance?.call(args);
        }
        return null;
      default:
        return null;
    }
  }

  /// Dynamically updates the native energy-based VAD thresholds live during
  /// an ongoing or idle recording session.
  Future<void> setVadThresholds({
    required double fixedFloor,
    required double noiseMultiplier,
  }) async {
    try {
      await _channel.invokeMethod<void>('setVadThresholds', <String, dynamic>{
        'fixedFloor': fixedFloor,
        'noiseMultiplier': noiseMultiplier,
      });
    } on PlatformException {
      // Platform channels not ready or unimplemented on stub platforms.
    } on MissingPluginException {
      // Platform channels not supported in unit tests without mocks.
    }
  }

  /// Starts continuous 16 kHz mono PCM recording with a pre-roll ring buffer
  /// and energy-based Voice Activity Detection (VAD). Emits `onVadSpeechStart`
  /// when speech begins and `onVadUtterance` with a `.wav` file path after
  /// [silenceDurationMs] of silence following speech.
  Future<bool> startVadListening({
    int silenceDurationMs = 850,
    int maxUtteranceMs = 12000,
    int preRollMs = 350,
    double? fixedFloor,
    double? noiseMultiplier,
  }) async {
    try {
      final args = <String, dynamic>{
        'silenceDurationMs': silenceDurationMs,
        'maxUtteranceMs': maxUtteranceMs,
        'preRollMs': preRollMs,
      };
      if (fixedFloor != null) args['fixedFloor'] = fixedFloor;
      if (noiseMultiplier != null) args['noiseMultiplier'] = noiseMultiplier;
      final started = await _channel
          .invokeMethod<bool>('startVadListening', args)
          .timeout(const Duration(seconds: 4));
      return started ?? false;
    } on TimeoutException {
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Stops native VAD recording. When [flush] is true and the user was in the
  /// middle of speaking, writes the partial speech to a `.wav` file and returns
  /// its path.
  Future<String?> stopVadListening({bool flush = false}) async {
    try {
      return await _channel
          .invokeMethod<String>('stopVadListening', <String, dynamic>{
            'flush': flush,
          })
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Records through a connected Bluetooth headset's mic, such as the
  /// glasses. Returns the headset's name, or null when the phone's own mic
  /// stays in use.
  Future<String?> useBluetoothMic() async {
    try {
      // The native side gives up after 3 s; this guards against no reply.
      return await _channel
          .invokeMethod<String>('useBluetoothMic')
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Confirms a successful photo with the native shutter, or a system click
  /// on platforms without the Android audio channel.
  Future<void> playShutter() async {
    try {
      await _channel.invokeMethod<void>('playShutter');
    } on MissingPluginException {
      try {
        await SystemSound.play(SystemSoundType.click);
      } on MissingPluginException {
        // No system audio in this environment.
      } on PlatformException {
        // Sound feedback is best effort.
      }
    } on PlatformException {
      // A missing sound must not discard an otherwise successful photo.
    }
  }

  /// Returns the local directory where on-device Whisper models
  /// (`ggml-base.en.bin`) are stored.
  Future<String?> getWhisperModelDir() async {
    try {
      return await _channel
          .invokeMethod<String>('getWhisperModelDir')
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Goes back to the phone's normal audio routing.
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Not available on this platform.
    } on PlatformException {
      // Routing is reset by the system when the app closes anyway.
    }
  }
}
