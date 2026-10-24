import 'package:audioplayers/audioplayers.dart';

/// Short sounds that mark events, so the cook notices them without looking.
enum Cue {
  timerStart('sounds/timer_start.wav'),
  timerDone('sounds/timer_done.wav');

  final String asset;
  const Cue(this.asset);
}

/// Plays [Cue]s. Never throws: a missing sound must not break cooking.
abstract class CueSounds {
  Future<void> play(Cue cue);
}

/// [CueSounds] backed by `audioplayers`.
class AudioCueSounds implements CueSounds {
  AudioPlayer? _player;

  // Play alongside speech: no audio focus on Android, so TTS and listening
  // carry on, and on iOS the same session settings as the TTS.
  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
        AVAudioSessionOptions.allowBluetoothA2DP,
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );

  @override
  Future<void> play(Cue cue) async {
    try {
      // Created on first use, inside the try: without the native plugin
      // (web without audio, tests) creating the player fails.
      final player = _player ??= AudioPlayer();
      await player.setAudioContext(_context);
      await player.stop();
      await player.play(AssetSource(cue.asset));
    } catch (_) {}
  }
}
