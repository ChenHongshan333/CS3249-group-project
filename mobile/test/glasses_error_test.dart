import 'package:flutter_test/flutter_test.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';
import 'package:mobile/glasses/glasses_service.dart';

void main() {
  // Meta's own text once told a tester to use an "App connections page"
  // they couldn't find in Meta AI.
  const metaText = 'Go to the App Connections page in Meta AI to update.';

  test('no glasses error shows Meta\'s own message', () {
    for (final reason in StreamErrorCase.values) {
      final message = explainGlassesError(
        StreamError(reason: reason, message: metaText),
      );
      expect(message, isNot(contains('App Connections')), reason: '$reason');
      expect(message, isNotEmpty);
    }
    for (final reason in DeviceSessionErrorCase.values) {
      final message = explainGlassesError(
        DeviceSessionError(reason: reason, message: metaText),
      );
      expect(message, isNot(contains('App Connections')), reason: '$reason');
    }
  });

  test('a missing camera permission says how to allow it', () {
    expect(
      explainGlassesError(
        const StreamError(
          reason: StreamErrorCase.permissionDenied,
          message: metaText,
        ),
      ),
      contains('camera access'),
    );
  });

  test('a glasses app update says to install it in Meta AI', () {
    expect(
      explainGlassesError(
        const DeviceSessionError(
          reason: DeviceSessionErrorCase.datAppOnTheGlassesUpdateRequired,
          message: metaText,
        ),
      ),
      allOf(contains('update'), contains('Meta AI')),
    );
  });

  test('folded glasses say to unfold them', () {
    expect(
      explainGlassesError(
        const StreamError(
          reason: StreamErrorCase.hingesClosed,
          message: metaText,
        ),
      ),
      'Unfold your glasses to take a photo.',
    );
  });
}
