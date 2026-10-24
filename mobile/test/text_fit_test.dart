import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fonts.dart';

/// Real glasses that have just dropped their connection.
class _DisconnectedGlasses extends MetaWearablesDatGlassesService {
  @override
  bool get usingRealGlasses => true;

  @override
  GlassesConnectionState get connectionState =>
      GlassesConnectionState.disconnected;

  @override
  String? get lastStatusNote =>
      'Glasses disconnected. Check they are on and nearby.';
}

/// Fails if any text on screen is cut off with an ellipsis.
void expectNoCutOffText(WidgetTester tester) {
  final cutOff = tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .where((p) => p.didExceedMaxLines)
      .map((p) => p.text.toPlainText())
      .toList();
  expect(cutOff, isEmpty, reason: 'Text cut off: $cutOff');
}

void main() {
  // Real glyph widths: the default test font draws every letter as a square.
  setUpAll(loadRealFonts);

  // A narrow Android phone (360 dp wide) with large system text, like the
  // OPPO CPH2697 in #26.
  Future<void> pumpNarrow(
    WidgetTester tester,
    AppScreen screen, {
    GlassesService? glasses,
  }) async {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      CookTogetherApp(
        initialScreen: screen,
        glassesService: glasses,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the Check button label stays on one line', (tester) async {
    await pumpNarrow(tester, AppScreen.cook);

    final style = Theme.of(tester.element(find.text('Check'))).textTheme;
    final oneLine = 1.3 * style.labelLarge!.fontSize! * 1.5;
    expect(tester.getSize(find.text('Check')).height, lessThan(oneLine));
    expectNoCutOffText(tester);

    // Let the cooking screen's timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a long glasses status wraps instead of being cut off', (
    tester,
  ) async {
    await pumpNarrow(tester, AppScreen.prep, glasses: _DisconnectedGlasses());
    // Scroll to the end, so Change is clear of the bottom bar.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reconnect'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(
      find.text('Glasses disconnected. Check they are on and nearby.'),
      findsOneWidget,
    );
    expectNoCutOffText(tester);
  });
}
