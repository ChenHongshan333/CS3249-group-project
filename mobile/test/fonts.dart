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

Future<void> loadRealFonts() async {
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  final engineDir = File(Platform.resolvedExecutable).parent;
  final fontDir = '${engineDir.parent.parent.path}/material_fonts';
  await _loadFont('Roboto', [
    for (final w in ['light', 'regular', 'medium', 'bold', 'black'])
      '$fontDir/roboto-$w.ttf',
  ]);
  await _loadFont('MaterialIcons', ['$fontDir/materialicons-regular.otf']);
  await _loadFont('Noto Color Emoji', [
    'C:/Windows/Fonts/seguiemj.ttf',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
  ]);
}
