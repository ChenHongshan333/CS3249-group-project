// Loads Roboto and Material Icons from the Flutter SDK, so text in tests is
// measured with real glyph widths rather than the square test font. Emoji use
// Segoe UI Emoji on Windows or Noto Color Emoji on Linux when present.
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
  }
  await loader.load();
}

/// The file in [dir] called [name], ignoring case: the SDK names them
/// "roboto-regular.ttf" on some machines and "Roboto-Regular.ttf" on others,
/// and Linux file names are case-sensitive.
String _inDir(String dir, String name) {
  final folder = Directory(dir);
  if (!folder.existsSync()) return '$dir/$name';
  for (final entry in folder.listSync()) {
    final base = entry.uri.pathSegments.last;
    if (base.toLowerCase() == name) return entry.path;
  }
  return '$dir/$name';
}

Future<void> loadRealFonts() async {
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  final engineDir = File(Platform.resolvedExecutable).parent;
  final fontDir = '${engineDir.parent.parent.path}/material_fonts';
  // Without Roboto, tests would quietly measure with the square test font.
  final regular = _inDir(fontDir, 'roboto-regular.ttf');
  if (!File(regular).existsSync()) {
    throw StateError('Roboto not found in $fontDir.');
  }
  await _loadFont('Roboto', [
    for (final w in ['light', 'regular', 'medium', 'bold', 'black'])
      _inDir(fontDir, 'roboto-$w.ttf'),
  ]);
  await _loadFont('MaterialIcons', [
    _inDir(fontDir, 'materialicons-regular.otf'),
  ]);
  await _loadFont('Noto Color Emoji', [
    'C:/Windows/Fonts/seguiemj.ttf',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
  ]);
}
