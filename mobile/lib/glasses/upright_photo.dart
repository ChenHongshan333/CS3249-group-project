import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Turns a glasses photo upright before it's shown or sent to the AI (#85).
///
/// The glasses' photos show up rotated 90° anticlockwise, and Meta's plugin
/// gives no orientation with them. A photo with an EXIF orientation is
/// turned by that; one without is turned 90° clockwise. Decoding a
/// full-size photo takes a moment, so it runs off the UI isolate.
Future<Uint8List> uprightGlassesPhoto(Uint8List jpeg) async {
  try {
    return await Isolate.run(() => uprightGlassesPhotoSync(jpeg));
  } catch (e) {
    debugPrint('Could not turn the glasses photo upright: $e');
    return jpeg;
  }
}

@visibleForTesting
Uint8List uprightGlassesPhotoSync(Uint8List jpeg) {
  // decodeJpg already applies an EXIF orientation (and drops the tag), so
  // read the tag from the original bytes first.
  final orientation = img.decodeJpgExif(jpeg)?.imageIfd.orientation;
  final image = img.decodeJpg(jpeg);
  if (image == null) return jpeg;
  // Kept in the log so the fix can be checked against a real photo.
  debugPrint(
    'Glasses photo ${image.width}x${image.height}, EXIF orientation '
    '${orientation ?? 'none'}',
  );
  final tagged = orientation != null && orientation != 1;
  // A tagged photo is upright once decoded; re-encode it so viewers that
  // ignore the tag see it upright too.
  final upright = tagged ? image : img.copyRotate(image, angle: 90);
  return img.encodeJpg(upright, quality: 90);
}
