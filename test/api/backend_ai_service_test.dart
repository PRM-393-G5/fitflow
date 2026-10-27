import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/api/api_client.dart';
import 'package:prm/data/api/token_store.dart';
import 'package:prm/data/openai_service.dart';

void main() {
  late HttpServer server;
  late Uri baseUrl;
  int nextStatus = 200;
  Object nextBody = <String, dynamic>{};
  Map<String, dynamic>? lastPayload;
  String? lastPath;
  String? lastAuthorization;
  late MemoryTokenStore tokens;

  OpenAiService service_() => OpenAiService(
    api: ApiClient(baseUrl: baseUrl, tokens: tokens),
  );

  setUp(() async {
    OpenAiService.debugConfiguredOverride = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}/api/');
    tokens = MemoryTokenStore(
      const ApiTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
    );
    server.listen((HttpRequest req) async {
      lastPath = req.uri.path;
      lastAuthorization = req.headers.value('authorization');
      final raw = await utf8.decoder.bind(req).join();
      lastPayload = raw.isEmpty
          ? null
          : jsonDecode(raw) as Map<String, dynamic>;
      req.response.statusCode = nextStatus;
      req.response.headers.contentType = ContentType.json;
      req.response.write(nextBody is String ? nextBody : jsonEncode(nextBody));
      await req.response.close();
    });
  });

  tearDown(() async {
    OpenAiService.debugConfiguredOverride = null;
    await server.close(force: true);
  });

  test('generateJson posts to /api/ai/generate and decodes response', () async {
    nextStatus = 200;
    nextBody = {
      'summary': 'Consistent depth across reps.',
      'tips': ['Brace core before descent'],
    };

    final service = service_();
    final result = await service.generateJson(
      system: 'sys',
      user: 'usr',
      schema: {'type': 'object'},
      schemaName: 'form_review',
      imageBytes: const [0x89, 0x50, 0x4e, 0x47, 0x0d],
    );

    expect(lastPath, '/api/ai/generate');
    expect(lastAuthorization, 'Bearer access-1');
    expect(lastPayload?['schemaName'], 'form_review');
    expect(lastPayload?['imageMimeType'], 'image/png');
    expect(result['summary'], 'Consistent depth across reps.');
  });

  test(
    'domain helpers call workout-plan, meal-plan, food-photo and form-review',
    () async {
      final service = service_();

      nextStatus = 200;
      nextBody = {'name': 'Upper Push'};
      final workout = await service.generateWorkoutPlan(
        request: 'Upper body push',
        level: 'Intermediate',
        durationMinutes: 45,
      );
      expect(lastPath, '/api/ai/workout-plan');
      expect(workout['name'], 'Upper Push');

      nextBody = {'totalKcal': 2100};
      final mealPlan = await service.generateMealPlan(
        targetKcal: 2100,
        proteinG: 160,
        meals: 4,
      );
      expect(lastPath, '/api/ai/meal-plan');
      expect(mealPlan['totalKcal'], 2100);

      nextBody = {'dishes': <Object>[], 'note': 'ok'};
      await service.analyzeFoodPhoto(const [0xff, 0xd8, 0xff, 0xe0]);
      expect(lastPath, '/api/ai/food-photo');
      expect(lastPayload?['imageMimeType'], 'image/jpeg');

      nextBody = {'summary': 'Good', 'tips': <Object>[]};
      await service.reviewForm(
        exercise: 'Squat',
        reps: const [
          {
            'number': 1,
            'minKneeAngle': 80,
            'descentMs': 1000,
            'ascentMs': 900,
            'faults': <String>[],
          },
        ],
      );
      expect(lastPath, '/api/ai/form-review');
    },
  );

  test('maps backend error bodies to OpenAiException codes', () async {
    final service = service_();

    nextStatus = 422;
    nextBody = {
      'statusCode': 422,
      'error': 'Unprocessable Entity',
      'message': 'refused',
    };
    await expectLater(
      service.generateJson(
        system: 's',
        user: 'u',
        schema: const {},
        schemaName: 'test',
      ),
      throwsA(isA<OpenAiException>().having((e) => e.code, 'code', 'refused')),
    );

    nextStatus = 503;
    nextBody = {
      'statusCode': 503,
      'error': 'Service Unavailable',
      'message': 'not-configured',
    };
    await expectLater(
      service.generateJson(
        system: 's',
        user: 'u',
        schema: const {},
        schemaName: 'test',
      ),
      throwsA(
        isA<OpenAiException>().having((e) => e.code, 'code', 'not-configured'),
      ),
    );
  });

  test('a signed-out user is told to sign in, without a request', () async {
    await tokens.clear();
    lastPath = null;
    await expectLater(
      service_().generateWorkoutPlan(request: 'legs'),
      throwsA(
        isA<OpenAiException>().having((e) => e.code, 'code', 'signed-out'),
      ),
    );
    expect(lastPath, isNull);
  });

  test('derives codes from the status when the backend sent none', () {
    String code(ApiException e) => OpenAiService.errorCodeFor(e);
    expect(code(const ApiException(null, 'x', timedOut: true)), 'timeout');
    expect(code(const ApiException(null, 'No connection')), 'offline');
    expect(code(const ApiException(401, 'Unauthorized')), 'signed-out');
    expect(code(const ApiException(429, 'Too Many')), 'rate-limited');
    expect(code(const ApiException(502, 'unauthorized')), 'unauthorized');
    expect(code(const ApiException(500, 'boom')), 'server-error');
    expect(code(const ApiException(418, 'teapot')), 'http-418');
  });
}
