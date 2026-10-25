import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:whisper_kit/whisper_bindings_generated.dart';
import 'package:whisper_kit/whisper_kit.dart';

import 'audio_route.dart';

/// On-device Speech-to-Text transcriber backed by `whisper_kit` (`whisper.cpp`)
/// using the lightweight `WhisperModel.tiny` model.
class WhisperTranscriber {
  WhisperTranscriber({
    this.model = WhisperModel.tiny,
    this.transcribeOverride,
    AudioRoute? audioRoute,
  }) : _audioRoute = audioRoute ?? const AudioRoute();

  final WhisperModel model;
  final Future<String?> Function(String wavPath)? transcribeOverride;
  final AudioRoute _audioRoute;

  String? _modelPath;
  bool _isDownloaded = false;
  bool _isLoadedInMemory = false;
  Future<bool>? _downloadFuture;
  Future<bool>? _loadFuture;
  Future<void> _serialQueue = Future<void>.value();

  /// True once the Whisper model is present on disk (or a test override is set).
  bool get isReady => transcribeOverride != null || _isDownloaded;

  /// True once `ggml-tiny.bin` has been loaded into the native C++ context.
  bool get isLoadedInMemory =>
      transcribeOverride != null || _isLoadedInMemory;

  /// Matches bracketed or parenthesized non-speech tags emitted by Whisper on
  /// silence or kitchen background noise (`[BLANK_AUDIO]`, `(music)`, etc.).
  static final RegExp _nonSpeechTagPattern = RegExp(
    r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*',
    caseSensitive: false,
  );

  /// Common single-phrase hallucinations Whisper produces on pure silence or
  /// steady fan/sizzle noise.
  static final RegExp _hallucinationPattern = RegExp(
    r'^(?:you|thank you\.?|thanks for watching!?\.?|subtitles by .*|'
    r'bye\.?|okay\.?|\.+)$',
    caseSensitive: false,
  );

  /// Checks whether the Whisper model is already downloaded on disk without
  /// blocking. If not yet ready, kicks off download + preload in the background.
  Future<bool> checkLocalModelReady() async {
    if (transcribeOverride != null) {
      _isDownloaded = true;
      _isLoadedInMemory = true;
      return true;
    }
    if (_isDownloaded) {
      if (!_isLoadedInMemory) {
        unawaited(preloadModel());
      }
      return true;
    }
    if (kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      return false;
    }
    final modelDir = await _audioRoute.getWhisperModelDir();
    if (modelDir != null && modelDir.isNotEmpty) {
      final path = model.getPath(modelDir);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
        _modelPath = path;
        _isDownloaded = true;
        if (!_isLoadedInMemory) {
          unawaited(preloadModel());
        }
        return true;
      }
    }
    unawaited(preloadModel());
    return _isDownloaded;
  }

  /// Downloads `ggml-tiny.bin` on app startup if it is not already stored on
  /// disk so it is ready before the user starts a recipe.
  Future<bool> ensureModelDownloaded() async {
    if (transcribeOverride != null) {
      _isDownloaded = true;
      return true;
    }
    if (_isDownloaded && _modelPath != null) return true;
    if (kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      return false;
    }
    if (_downloadFuture != null) return _downloadFuture!;
    _downloadFuture = _downloadIfMissing();
    try {
      return await _downloadFuture!;
    } finally {
      _downloadFuture = null;
    }
  }

  /// Loads `ggml-tiny.bin` into native RAM when a recipe starts so the model
  /// is already initialized before the user speaks for the first time.
  Future<bool> preloadModel() async {
    if (transcribeOverride != null) {
      _isDownloaded = true;
      _isLoadedInMemory = true;
      return true;
    }
    if (_isLoadedInMemory) return true;
    if (!await ensureModelDownloaded() || _modelPath == null) {
      return false;
    }
    if (_loadFuture != null) return _loadFuture!;
    final completer = Completer<bool>();
    _loadFuture = completer.future;
    _serialQueue = _serialQueue.whenComplete(() async {
      try {
        if (_isLoadedInMemory) {
          completer.complete(true);
          return;
        }
        final result = await _invokeNativeRequest(<String, dynamic>{
          '@type': 'initModel',
          'model': _modelPath!,
        });
        final type = result['@type'] as String?;
        final message = result['message'] as String?;
        _isLoadedInMemory =
            type == 'modelLoaded' || message == 'method not found';
        completer.complete(_isLoadedInMemory);
      } catch (_) {
        completer.complete(false);
      } finally {
        _loadFuture = null;
      }
    });
    return completer.future;
  }

  /// Ensures `ggml-tiny.bin` is both downloaded and loaded into memory.
  Future<bool> ensureModelReady() => preloadModel();

  Future<bool> _downloadIfMissing() async {
    try {
      final modelDir = await _audioRoute.getWhisperModelDir();
      if (modelDir == null || modelDir.isEmpty) {
        return false;
      }
      final targetPath = model.getPath(modelDir);
      final targetFile = File(targetPath);
      if (targetFile.existsSync() && targetFile.lengthSync() > 1024 * 1024) {
        _modelPath = targetPath;
        _isDownloaded = true;
        return true;
      }

      await Directory(modelDir).create(recursive: true);
      final uri = Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model.modelName}.bin',
      );
      final client = HttpClient();
      RandomAccessFile? raf;
      File? tempFile;
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) {
          return false;
        }
        final tempPath = '$targetPath.part';
        tempFile = File(tempPath);
        raf = tempFile.openSync(mode: FileMode.write);
        await for (final chunk in response) {
          raf.writeFromSync(chunk);
        }
        await raf.close();
        raf = null;

        if (!tempFile.existsSync() || tempFile.lengthSync() <= 1024 * 1024) {
          return false;
        }
        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        tempFile.renameSync(targetPath);
        tempFile = null;
        _modelPath = targetPath;
        _isDownloaded = true;
        return true;
      } finally {
        try {
          await raf?.close();
        } catch (_) {}
        try {
          client.close(force: true);
        } catch (_) {}
        if (tempFile != null && tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {
      return false;
    }
  }

  /// Transcribes a 16 kHz mono 16-bit PCM `.wav` file using `whisper_kit` and
  /// removes temporary non-speech markers.
  Future<String?> transcribeFile(
    String wavPath, {
    bool deleteAfter = true,
  }) async {
    final override = transcribeOverride;
    if (override != null) {
      return override(wavPath);
    }
    if (!await ensureModelDownloaded() || _modelPath == null) {
      if (deleteAfter) _deleteSilently(wavPath);
      return null;
    }

    final completer = Completer<String?>();
    _serialQueue = _serialQueue.whenComplete(() async {
      try {
        final result = await _invokeNativeRequest(<String, dynamic>{
          '@type': 'getTextFromWavFile',
          'audio': wavPath,
          'model': _modelPath!,
          'is_translate': false,
          'threads': 4,
          'is_verbose': false,
          'language': 'en',
          'is_special_tokens': false,
          'is_no_timestamps': true,
          'n_processors': 1,
          'split_on_word': false,
          'speed_up': false,
          'diarize': false,
        });
        _isLoadedInMemory = true;
        final rawText = (result['text'] as String?) ?? '';
        final cleaned = cleanWhisperTranscript(rawText);
        if (!kReleaseMode) {
          debugPrint('Whisper: "$cleaned"');
        }
        completer.complete(cleaned);
      } catch (_) {
        completer.complete(null);
      } finally {
        if (deleteAfter) _deleteSilently(wavPath);
      }
    });
    return completer.future;
  }

  static Future<Map<String, dynamic>> _invokeNativeRequest(
    Map<String, dynamic> payload,
  ) {
    final jsonString = json.encode(payload);
    return Isolate.run(() => _performNativeRequestSync(jsonString));
  }

  static Map<String, dynamic> _performNativeRequestSync(String jsonString) {
    final DynamicLibrary lib;
    if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libwhisper.so');
    } else if (Platform.isIOS) {
      try {
        DynamicLibrary.open('whisper_kit.framework/whisper_kit');
      } catch (_) {}
      lib = DynamicLibrary.process();
    } else {
      lib = DynamicLibrary.process();
    }

    final stdlib = DynamicLibrary.process();
    final nativeMalloc = stdlib.lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');
    final nativeFree = stdlib.lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');

    final units = utf8.encode(jsonString);
    final reqPtr = nativeMalloc(units.length + 1);
    reqPtr.asTypedList(units.length + 1)
      ..setAll(0, units)
      ..[units.length] = 0;

    final bindings = WhisperFlutterBindings(lib);
    Pointer<Char> resPtr = nullptr;
    try {
      resPtr = bindings.request(reqPtr.cast<Char>());
      if (resPtr == nullptr) {
        return const <String, dynamic>{'@type': 'error'};
      }
      final resBytes = resPtr.cast<Uint8>();
      var length = 0;
      while (resBytes[length] != 0) {
        length++;
      }
      final responseStr = utf8.decode(
        resBytes.asTypedList(length),
        allowMalformed: true,
      );
      final decoded = json.decode(responseStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const <String, dynamic>{'@type': 'error'};
    } finally {
      nativeFree(reqPtr);
      if (resPtr != nullptr) {
        try {
          bindings.whisper_kit_free(resPtr);
        } catch (_) {}
      }
    }
  }

  /// Strips Whisper non-speech tags (`[BLANK_AUDIO]`, `(music)`, etc.) and
  /// returns cleaned text, or an empty string if nothing spoken remains.
  static String cleanWhisperTranscript(String raw) {
    final stripped = raw
        .replaceAll(_nonSpeechTagPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stripped.isEmpty) return '';
    if (_hallucinationPattern.hasMatch(stripped)) return '';
    return stripped;
  }

  void _deleteSilently(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
