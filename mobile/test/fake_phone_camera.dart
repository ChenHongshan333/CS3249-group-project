import 'dart:typed_data';

import 'package:mobile/camera/phone_camera.dart';

/// A phone camera for tests: returns [photo] (null means the user closed
/// the camera), or throws [error], and counts how often it was opened.
class FakePhoneCamera implements PhoneCamera {
  FakePhoneCamera({this.photo, this.error});

  /// A few bytes are enough; the demo assistant doesn't decode them.
  static final Uint8List samplePhoto = Uint8List.fromList(
    List<int>.generate(300, (i) => i % 256),
  );

  final Uint8List? photo;
  final PhoneCameraException? error;
  int opened = 0;

  @override
  Future<Uint8List?> takePhoto() async {
    opened++;
    if (error != null) throw error!;
    return photo;
  }
}
