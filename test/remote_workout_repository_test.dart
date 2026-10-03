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

  group('documents', () {
    test(
      'syncDocs merges with the server and uploads local-only docs',
      () async {
        final backend = FakeBackend({
          'GET /api/me/docs/sessions': (_) => FakeBackend.json([
            {'id': 'shared', 'v': 'remote'},
            {'id': 'remote-only', 'v': 2},
            {'id': 'gone', 'deleted': true},
          ]),
          'PUT /api/me/docs/sessions': (_) => FakeBackend.json(null, 204),
        });
        await backend.signIn();
        final repo = repositoryFor(backend);

        final merged = await repo.syncDocs('sessions', [
          {'id': 'shared', 'v': 'local'},
          {'id': 'local-only', 'v': 1},
          {'id': 'gone', 'v': 1},
        ]);
        await pumpEventQueue();

        expect(
          merged!.map((doc) => doc['id']),
          unorderedEquals(['shared', 'remote-only', 'local-only']),
        );
        final upload = backend.requests.last;
        expect(upload.method, 'PUT');
        expect(jsonDecode(upload.body), {
          'docs': [
            {'id': 'local-only', 'v': 1},
          ],
        });
      },
    );

    test('syncDocs uploads in batches of 500', () async {
      final backend = FakeBackend({
        'GET /api/me/docs/sessions': (_) => FakeBackend.json([]),
        'PUT /api/me/docs/sessions': (_) => FakeBackend.json(null, 204),
      });
      await backend.signIn();
      final local = [
        for (var i = 0; i < 1001; i++) {'id': 's$i'},
      ];
      await repositoryFor(backend).syncDocs('sessions', local);
      await pumpEventQueue();
      final sizes = backend.requests
          .where((r) => r.method == 'PUT')
          .map((r) => (jsonDecode(r.body)['docs'] as List).length);
      expect(sizes, [500, 500, 1]);
    });

    test('syncDocs returns null signed out or offline', () async {
      final signedOut = repositoryFor(FakeBackend({}), userId: null);
      expect(await signedOut.syncDocs('sessions', []), isNull);

      final backend = FakeBackend({
        'GET /api/me/docs/sessions': (_) => throw http.ClientException('x'),
      });
      await backend.signIn();
      expect(await repositoryFor(backend).syncDocs('sessions', []), isNull);
    });

    test('saving and deleting sync custom workouts and sessions', () async {
      final backend = FakeBackend({
        'PUT /api/me/docs/workouts/custom-1': (_) =>
            FakeBackend.json(null, 204),
        'DELETE /api/me/docs/workouts/custom-1': (_) =>
            FakeBackend.json(null, 204),
      });
      await backend.signIn();
      final repo = repositoryFor(backend);

      await repo.saveWorkout(customWorkout('custom-1'));
      await repo.saveWorkout(seedWorkouts.first); // template: local only
      await repo.deleteWorkout('custom-1');
      await pumpEventQueue();

      expect(backend.calls, [
        'PUT /api/me/docs/workouts/custom-1',
        'DELETE /api/me/docs/workouts/custom-1',
      ]);
    });

    test('nothing is sent while signed out', () async {
      final backend = FakeBackend({});
      final repo = repositoryFor(backend, userId: null);
      await repo.saveWorkout(customWorkout('custom-1'));
      await pumpEventQueue();
      expect(backend.requests, isEmpty);
      expect(await repo.getWorkout('custom-1'), isNotNull);
    });
  });
}
