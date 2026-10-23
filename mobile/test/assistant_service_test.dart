import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/conversation.dart';
import 'package:mobile/models/recipe.dart';
import 'package:mobile/models/user_preferences.dart';
import 'package:mobile/services/assistant_service.dart';

final _recipe = kStarterRecipes.first;

final _capture = VisionCapture(
  id: 'snap',
  recipeId: _recipe.id,
  stepIndex: 0,
  source: 'glasses',
  deviceName: 'Test glasses',
  sceneDescription: 'A bowl',
  recipeIcon: _recipe.icon,
  recipeTone: _recipe.tone,
  base64Jpeg: 'AAAA',
  capturedAt: DateTime(2026),
);

HttpAssistantService _service(
  Future<http.Response> Function(http.Request) handler, {
  String url = 'https://backend.test',
}) => HttpAssistantService(
  baseUrlProvider: () => url,
  client: MockClient(handler),
);

Future<AssistantResponse> _ask(AssistantService s) => s.askQuestion(
  sessionId: 's',
  recipe: _recipe,
  stepIndex: 0,
  question: 'How small?',
  history: const [],
);

Future<AssistantResponse> _check(AssistantService s) => s.checkStepWithVision(
  sessionId: 's',
  recipe: _recipe,
  stepIndex: 0,
  visionCapture: _capture,
);

void main() {
  test('the deployed backend is the default', () {
    expect(const UserPreferences().serverBaseUrl, kDefaultBackendUrl);
    expect(UserPreferences.decode('{}').serverBaseUrl, kDefaultBackendUrl);
    // Clearing the URL is how you choose demo answers, and it sticks.
    expect(
      UserPreferences.decode('{"serverBaseUrl": ""}').serverBaseUrl,
      isEmpty,
    );
  });

  test('no URL means demo answers, not an error', () async {
    final s = _service((_) async => fail('no request expected'), url: '');
    final reply = await _ask(s);
    expect(reply.isError, isFalse);
    expect(reply.reply, isNotEmpty);
  });

  test('a backend reply is passed through', () async {
    final s = _service(
      (_) async => http.Response(
        jsonEncode({
          'reply': 'About one centimetre.',
          'offer': {'type': 'start_timer', 'seconds': 60, 'label': 'Toss'},
        }),
        200,
      ),
    );
    final reply = await _ask(s);
    expect(reply.reply, 'About one centimetre.');
    expect(reply.offer?.seconds, 60);
    expect(reply.isError, isFalse);
  });

  test(
    'a backend error is said out loud, not replaced by a demo answer',
    () async {
      final s = _service(
        (_) async =>
            http.Response('{"error": "the assistant is unavailable"}', 502),
      );
      final reply = await _ask(s);
      expect(reply.isError, isTrue);
      expect(reply.reply, HttpAssistantService.unreachableReply);
    },
  );

  test('a timeout says the assistant was too slow', () async {
    final s = _service((_) async => throw TimeoutException('slow'));
    final reply = await _ask(s);
    expect(reply.isError, isTrue);
    expect(reply.reply, HttpAssistantService.tooSlowReply);
  });

  test('no connection at all is reported too', () async {
    final s = _service((_) async => throw http.ClientException('offline'));
    expect((await _ask(s)).reply, HttpAssistantService.unreachableReply);
  });

  test('a failed photo check gives no verdict', () async {
    final s = _service((_) async => http.Response('{"error": "x"}', 500));
    final result = await _check(s);
    expect(result.isError, isTrue);
    expect(result.visualStatus, isNull);
    expect(result.visionCapture, isNull);
  });

  test('warmUp calls /health, and does nothing without a URL', () async {
    final paths = <String>[];
    await _service((r) async {
      paths.add(r.url.path);
      return http.Response('{"ok": true}', 200);
    }).warmUp();
    expect(paths, ['/health']);

    await _service((_) async => fail('no request expected'), url: '').warmUp();
  });

  test('warmUp never throws', () async {
    await _service((_) async => throw http.ClientException('offline')).warmUp();
  });
}
