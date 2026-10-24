import 'dart:async';

import 'package:flutter/services.dart';

/// Chooses which microphone speech is recorded from. Backed by native code
/// in `android/app/src/main/kotlin/.../MainActivity.kt`; on other platforms,
/// the web build and tests, routing does nothing and shutter feedback falls
/// back to a system click.
class AudioRoute {
  const AudioRoute();

  static const MethodChannel _channel = MethodChannel(
    'cooktogether/audio_route',
  );

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
