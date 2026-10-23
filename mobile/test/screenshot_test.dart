// Renders each screen to a PNG so the UI can be reviewed without a device.
//
// Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=../build/screens flutter test test/screenshot_test.dart
//
// Fonts come from the Flutter SDK (Roboto, Material Icons). Emoji use
// Segoe UI Emoji on Windows or Noto Color Emoji on Linux when present.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String? _outDir = Platform.environment['SCREENSHOT_DIR'];

// iPhone 17 logical size, matching the web prototype frame.
const Size _phone = Size(402, 874);

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

Future<void> _loadFonts() async {
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

final List<CookingHistoryItem> _sampleHistory = [
  const CookingHistoryItem(
    id: 'h1',
    recipeId: 'salad',
    recipeName: 'Rainbow salad bowl',
    recipeIcon: '🥗',
    date: '21 Oct 2026',
    durationSeconds: 1260,
    stepsCompleted: 4,
    visualChecksCount: 2,
  ),
  const CookingHistoryItem(
    id: 'h2',
    recipeId: 'wrap',
    recipeName: 'Egg & spinach wraps',
    recipeIcon: '🌯',
    date: '18 Oct 2026',
    durationSeconds: 960,
    stepsCompleted: 4,
    visualChecksCount: 1,
  ),
];

Future<void> _capture(WidgetTester tester, String name) async {
  // Let checkbox, switch and button animations finish.
  await tester.pump(const Duration(milliseconds: 500));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screenshot-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppScreen screen, {
  bool welcome = false,
  bool withHistory = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'cooktogether.seen': !welcome,
    if (withHistory)
      'cooktogether.history': CookingHistoryItem.encodeList(_sampleHistory),
  });
  tester.view.physicalSize = _phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('screenshot-root'),
      child: CookTogetherApp(initialScreen: screen),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    if (_outDir != null) await _loadFonts();
  });

  final skip = _outDir == null;

  testWidgets('welcome', (tester) async {
    await _pumpScreen(tester, AppScreen.home, welcome: true);
    await _capture(tester, '00-welcome');
  }, skip: skip);

  for (final (index, screen) in AppScreen.values.indexed) {
    testWidgets(screen.name, (tester) async {
      await _pumpScreen(tester, screen);
      final number = '${index + 1}'.padLeft(2, '0');
      await _capture(tester, '$number-${screen.name}');
    }, skip: skip);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('prep-ready', (tester) async {
    await _pumpScreen(tester, AppScreen.prep);
    await tester.tap(find.text('Mark all'));
    await tester.tap(find.text('Lemon instead of extra oil'));
    await tester.pump();
    await _capture(tester, '03b-prep-ready');

    await tester.dragUntilVisible(
      find.text('Change'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Change'));
    await settle(tester);
    await _capture(tester, '03c-prep-glasses-sheet');
  }, skip: skip);

  testWidgets('cook-active', (tester) async {
    await _pumpScreen(tester, AppScreen.cook);
    await tester.tap(find.text('All steps'));
    await settle(tester);
    await _capture(tester, '04b-cook-steps-sheet');
    await tester.tap(find.text('Build your bowl'));
    await settle(tester);

    await tester.tap(find.textContaining('timer'));
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Type instead'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'How small is bite-sized?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    await _capture(tester, '04c-cook-active');
  }, skip: skip);

  // Large system text, as many users set it; fails on any overflow.
  for (final screen in [AppScreen.home, AppScreen.prep, AppScreen.cook]) {
    testWidgets('${screen.name}-large-text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpScreen(tester, screen);
      await _capture(tester, '09-${screen.name}-large-text');
    }, skip: skip);
  }

  // Desktop browser: the phone-width column on a white page.
  testWidgets('home-wide', (tester) async {
    await _pumpScreen(tester, AppScreen.home);
    tester.view.physicalSize = const Size(1280, 800) * 2;
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, '10-home-wide');
  }, skip: skip);

  testWidgets('steps-sheet-wide', (tester) async {
    await _pumpScreen(tester, AppScreen.cook);
    tester.view.physicalSize = const Size(1280, 800) * 2;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('All steps'));
    await settle(tester);
    await _capture(tester, '10b-steps-sheet-wide');
  }, skip: skip);

  testWidgets('history-empty', (tester) async {
    await _pumpScreen(tester, AppScreen.history, withHistory: false);
    await _capture(tester, '06b-history-empty');
  }, skip: skip);
}
