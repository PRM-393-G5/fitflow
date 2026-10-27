import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/openai_service.dart';

void main() {
  late HttpServer server;
  late Uri baseUrl;
  int nextStatus = 200;
  Object nextBody = <String, dynamic>{};
  Map<String, dynamic>? lastPayload;
  String? lastPath;

  setUp(() async {
    OpenAiService.debugConfiguredOverride = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}/api/');
    server.listen((HttpRequest req) async {
      lastPath = req.uri.path;
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

    final service = OpenAiService(baseUrl: baseUrl);
    final result = await service.generateJson(
      system: 'sys',
      user: 'usr',
      schema: {'type': 'object'},
      schemaName: 'form_review',
      imageBytes: const [0x89, 0x50, 0x4e, 0x47, 0x0d],
    );

    expect(lastPath, '/api/ai/generate');
    expect(lastPayload?['schemaName'], 'form_review');
    expect(lastPayload?['imageMimeType'], 'image/png');
    expect(result['summary'], 'Consistent depth across reps.');
  });

  test(
    'domain helpers call workout-plan, meal-plan, food-photo and form-review',
    () async {
      final service = OpenAiService(baseUrl: baseUrl);

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
    final service = OpenAiService(baseUrl: baseUrl);

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
}
