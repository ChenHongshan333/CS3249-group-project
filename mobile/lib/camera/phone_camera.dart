import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Takes a photo with the phone's own camera. Used for step checks when
/// the Meta glasses are not connected or their camera fails.
abstract class PhoneCamera {
  /// Opens the camera and returns the JPEG bytes, or null if the user
  /// closed the camera without taking a photo. Throws
  /// [PhoneCameraException] when the camera can't be used.
  Future<Uint8List?> takePhoto();
}

/// The camera could not be used. [message] is safe to show or speak.
class PhoneCameraException implements Exception {
  final String message;
  const PhoneCameraException(this.message);

  @override
  String toString() => message;
}

/// [PhoneCamera] backed by the system camera through `image_picker`.
class SystemPhoneCamera implements PhoneCamera {
  SystemPhoneCamera({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> takePhoto() async {
    try {
      // 1024 px matches what the backend shrinks photos to anyway.
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (photo == null) return null;
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) {
        throw const PhoneCameraException(
          'The phone camera sent an empty photo.',
        );
      }
      return bytes;
    } on PhoneCameraException {
      rethrow;
    } catch (_) {
      throw const PhoneCameraException(
        'The phone camera could not open. Check camera permission for CookTogether.',
      );
    }
  }
}
