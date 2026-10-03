import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/data/remote_workout_repository.dart';
import 'package:prm/data/seed_workouts.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/fake_backend.dart';

Workout customWorkout(String id) =>
    Workout.fromJson({...seedWorkouts.first.toJson(), 'id': id});

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  RemoteWorkoutRepository repositoryFor(
    FakeBackend backend, {
    String? userId = 'u1',
  }) => RemoteWorkoutRepository(
    backend.api,
    LocalWorkoutRepository(preferences),
    preferences,
    currentUserId: () => userId,
  );

  group('templates', () {
    test('uses the bundled seeds until the first fetch', () async {
      final repo = repositoryFor(FakeBackend({}));
      expect(
        (await repo.getWorkouts()).map((w) => w.id),
        seedWorkouts.map((w) => w.id),
      );
    });

    test('caches the templates served by the API', () async {
      final served = [seedWorkouts.last.toJson()];
      final backend = FakeBackend({
        'GET /api/templates': (_) => FakeBackend.json(served),
      });
      final repo = repositoryFor(backend);

      await repo.refreshTemplates();

      expect((await repo.getWorkouts()).map((w) => w.id), [
        seedWorkouts.last.id,
      ]);
      expect(backend.requests.single.headers['Authorization'], isNull);
    });

    test('keeps the cache when offline or the payload is unusable', () async {
      final repo = repositoryFor(
        FakeBackend({
          'GET /api/templates': (_) => throw http.ClientException('offline'),
        }),
      );
      await repo.refreshTemplates();
      expect(await repo.getWorkouts(), hasLength(seedWorkouts.length));

      final broken = repositoryFor(
        FakeBackend({
          'GET /api/templates': (_) => FakeBackend.json([
            {'id': 'broken'},
          ]),
        }),
      );
      await broken.refreshTemplates();
      expect(await broken.getWorkouts(), hasLength(seedWorkouts.length));
    });
  });

  test('custom workouts are listed after the templates', () async {
    final repo = repositoryFor(FakeBackend({}));
    final custom = customWorkout('custom-1');
    await repo.saveWorkout(custom);
    expect((await repo.getWorkouts()).last.id, 'custom-1');
    expect(
      jsonEncode((await repo.getWorkout('custom-1'))!.toJson()),
      jsonEncode(custom.toJson()),
    );
  });
}
