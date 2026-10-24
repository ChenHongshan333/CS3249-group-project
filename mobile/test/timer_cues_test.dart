import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:mobile/services/cue_sounds.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the sounds played instead of playing them.
class _FakeCueSounds implements CueSounds {
  final List<Cue> played = [];

  @override
  Future<void> play(Cue cue) async => played.add(cue);
}

const _tts = MethodChannel('flutter_tts');

void main() {
  late _FakeCueSounds sounds;
  late List<String> spoken;

  setUp(() {
    SharedPreferences.setMockInitialValues({'cooktogether.seen': true});
    sounds = _FakeCueSounds();
    spoken = [];
    // Hear what CookTogether says.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_tts, (call) async {
          if (call.method == 'speak') spoken.add(call.arguments as String);
          return 1;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_tts, null);
  });

  Future<void> say(WidgetTester tester, String text) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Type instead'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> openStepOne(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CookTogetherApp(
        showInitialWelcome: false,
        initialScreen: AppScreen.cook,
        assistantService: const MockAssistantService(),
        cueSounds: sounds,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Advances the clock one second at a time, like the cooking screen's.
  Future<void> wait(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  }

  // #21
  testWidgets('a voice timer plays a start sound and reminds halfway and '
      'at 1 minute', (tester) async {
    await openStepOne(tester);
    await say(tester, 'set a timer for 4 minutes');
    expect(sounds.played, [Cue.timerStart]);
    expect(find.byTooltip('Dismiss timer'), findsOneWidget);

    spoken.clear();
    await wait(tester, 120);
    expect(
      spoken.where((s) => s.startsWith('Halfway there: 2 minutes left')),
      hasLength(1),
    );
    await wait(tester, 60);
    expect(spoken.where((s) => s.startsWith('1 minute left')), hasLength(1));
    await finish(tester);
  });

  testWidgets('a short timer has no reminders; it dings, says so, and fades '
      'out', (tester) async {
    await openStepOne(tester);
    await say(tester, 'set a timer for 1 minute');
    spoken.clear();

    await wait(tester, 60);
    expect(sounds.played, [Cue.timerStart, Cue.timerDone]);
    expect(spoken.where((s) => s.contains('left on your')), isEmpty);
    expect(find.text('Done'), findsOneWidget);

    // The announcement comes after the ding.
    await wait(tester, 1);
    expect(spoken.last, contains('timer just finished'));

    // Gone without a tap.
    await wait(tester, 8);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Dismiss timer'), findsNothing);
    await finish(tester);
  });
}
