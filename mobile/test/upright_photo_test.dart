import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/glasses/upright_photo.dart';

void main() {
  // A wide photo: red on the left half, blue on the right.
  img.Image wideRedBlue() {
    final image = img.Image(width: 40, height: 20);
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 40; x++) {
        image.setPixelRgb(x, y, x < 20 ? 255 : 0, 0, x < 20 ? 0 : 255);
      }
    }
    return image;
  }

  test('a photo without an orientation is turned 90° clockwise', () {
    final out = img.decodeJpg(
      uprightGlassesPhotoSync(img.encodeJpg(wideRedBlue())),
    )!;
    expect(out.width, 20);
    expect(out.height, 40);
    // Clockwise: the left (red) half ends up on top.
    expect(out.getPixel(10, 5).r, greaterThan(200));
    expect(out.getPixel(10, 35).b, greaterThan(200));
  });

  test('a photo with an EXIF orientation is turned by that instead', () {
    final image = wideRedBlue();
    image.exif.imageIfd.orientation = 3; // upside down
    final out = img.decodeJpg(uprightGlassesPhotoSync(img.encodeJpg(image)))!;
    expect(out.width, 40);
    expect(out.height, 20);
    // Turned 180°: red is now on the right.
    expect(out.getPixel(35, 10).r, greaterThan(200));
  });

  test('bytes that are not a JPEG come back unchanged', () async {
    final bytes = img.encodePng(wideRedBlue());
    expect(await uprightGlassesPhoto(bytes), equals(bytes));
  });
}
