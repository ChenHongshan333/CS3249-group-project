import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/glasses/glasses_service.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's own glasses, turned off after connecting once. Reconnecting
/// works, as it does once they are back on.
class _TurnedOffGlasses extends MetaWearablesDatGlassesService {
  bool connected = false;
  int connectCalls = 0;

  @override
  bool get usingRealGlasses => true;

  @override
  GlassesConnectionState get connectionState => connected
      ? GlassesConnectionState.connectedHardware
      : GlassesConnectionState.disconnected;

  @override
  bool get isConnected => connected;

  @override
  String get deviceName => 'Ray-Ban Meta';

  @override
  int get batteryLevel => 80;

  @override
  String? get lastStatusNote => connected
      ? 'Connected to Ray-Ban Meta'
      : 'Glasses disconnected. Check they are on and nearby.';

  @override
  Future<bool> connectRealGlasses() async {
    connectCalls++;
    connected = true;
    notifyListeners();
    return true;
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    AppScreen screen, {
    GlassesService? glasses,
    bool simulatedGlasses = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'cooktogether.seen': true,
      if (simulatedGlasses)
        'cooktogether.preferences': '{"simulatedGlassesPhotos": true}',
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CookTogetherApp(
        initialScreen: screen,
        glassesService: glasses,
        assistantService: const MockAssistantService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
  }

  // #15
  testWidgets('turned-off glasses get a Reconnect action, not simulated ones', (
    tester,
  ) async {
    final glasses = _TurnedOffGlasses();
    await pumpApp(tester, AppScreen.prep, glasses: glasses);
    await scrollToEnd(tester);
    expect(find.text('Glasses disconnected'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Simulated'), findsNothing);
    expect(find.textContaining('simulated'), findsNothing);

    await tester.tap(find.text('Reconnect glasses'));
    await tester.pumpAndSettle();
    expect(glasses.connectCalls, 1);
    expect(find.text('Connected to Ray-Ban Meta'), findsWidgets);
    expect(find.text('Reconnect glasses'), findsNothing);
    expect(find.text('Battery 80%'), findsOneWidget);

    // Let the toast finish before the test ends.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('without real glasses, Home and Get ready never show the Mock '
      'Kit', (tester) async {
    await pumpApp(tester, AppScreen.home);
    expect(find.text('Glasses not connected'), findsOneWidget);
    expect(find.textContaining('Mock Kit'), findsNothing);

    await tester.tap(find.text('Choose a recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rainbow salad bowl'));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(find.text('Glasses not connected'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Connect my glasses'), findsOneWidget);
    expect(find.text('Test touchpad tap'), findsNothing);
    expect(find.textContaining('Mock Kit'), findsNothing);
  });

  testWidgets('the Developer switch shows simulated glasses as connected', (
    tester,
  ) async {
    await pumpApp(tester, AppScreen.home, simulatedGlasses: true);
    expect(find.text('Ray-Ban Meta (Mock Kit) connected'), findsOneWidget);
  });

  testWidgets('simulated glasses controls are in Profile → Developer', (
    tester,
  ) async {
    await pumpApp(tester, AppScreen.profile);
    expect(find.text('Test touchpad tap'), findsNothing);

    // Clear of the Save bar.
    await scrollToEnd(tester);
    await tester.tap(find.text('Developer'));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(find.text('Oakley Meta HSTN'), findsOneWidget);
    expect(find.text('Test touchpad tap'), findsOneWidget);

    await tester.tap(find.text('Oakley Meta HSTN'));
    await tester.pumpAndSettle();
    expect(find.text('Switched to Oakley Meta HSTN'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
