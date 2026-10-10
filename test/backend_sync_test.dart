import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prm/app/app_controller.dart';
import 'package:prm/data/backend_auth_service.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/data/remote_workout_repository.dart';
import 'package:prm/data/sync_outbox.dart';
import 'package:prm/domain/meal_plan.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/fake_backend.dart';

/// A tiny in-memory FitFlow API: docs per kind (with tombstones), meta
/// with last-write-wins, Google sign-in, logout and account deletion.
class FakeServer {
  final docs = <String, Map<String, Map<String, dynamic>>>{};
  int metaUpdatedAt = 0;
  Map<String, dynamic>? meta;
  bool online = true;
  bool accountDeleted = false;

  late final backend = FakeBackend({
    'POST /api/auth/google': signInResponse,
    'POST /api/auth/logout': (_) => FakeBackend.json(null, 204),
    'GET /api/templates': (_) => FakeBackend.json([]),
  }, fallback: _route);

  http.Response? _route(http.Request request) {
    if (!online) throw http.ClientException('offline');
    final segments = request.url.pathSegments; // api, me, ...
    if (segments.length < 2 || segments[1] != 'me') return null;
    if (segments.length == 2 && request.method == 'DELETE') {
      accountDeleted = true;
      docs.clear();
      return FakeBackend.json(null, 204);
    }
    if (segments.length == 3 && segments[2] == 'meta') {
      if (request.method == 'GET') {
        return FakeBackend.json({'updatedAt': metaUpdatedAt, 'meta': meta});
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final ts = body['updatedAt'] as int;
      if (ts > metaUpdatedAt) {
        metaUpdatedAt = ts;
        meta = body['meta'] as Map<String, dynamic>;
        return FakeBackend.json({
          'applied': true,
          'updatedAt': ts,
          'meta': meta,
        });
      }
      return FakeBackend.json({
        'applied': false,
        'updatedAt': metaUpdatedAt,
        'meta': meta,
      });
    }
    if (segments.length >= 4 && segments[2] == 'docs') {
      final kind = docs.putIfAbsent(segments[3], () => {});
      if (segments.length == 4 && request.method == 'GET') {
        final since = request.url.queryParameters['since'];
        return FakeBackend.json([
          for (final doc in kind.values)
            if (since == null || (doc['id'] as String).compareTo(since) >= 0)
              doc,
        ]);
      }
      if (segments.length == 4 && request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        for (final doc in body['docs'] as List) {
          kind[doc['id'] as String] = Map<String, dynamic>.from(doc as Map);
        }
        return FakeBackend.json(null, 204);
      }
      final id = segments[4];
      if (request.method == 'PUT') {
        kind[id] = {
          ...jsonDecode(request.body) as Map<String, dynamic>,
          'id': id,
        };
      } else if (request.method == 'DELETE') {
        kind[id] = {'id': id, 'deleted': true};
      }
      return FakeBackend.json(null, 204);
    }
    return null;
  }
}

WorkoutSession session(String id, int day) => WorkoutSession(
  id: id,
  workoutId: 'w',
  workoutName: 'W',
  startedAt: DateTime(2026, 10, day, 8),
  completedAt: DateTime(2026, 10, day, 9),
  completedSets: 3,
  volumeKg: 100,
);

/// `load()` starts a background sync; wait for it, then sync again so
/// the test sees a complete round.
Future<void> syncNow(AppController app) async {
  for (var i = 0; app.syncing; i++) {
    if (i > 400) throw StateError('background sync never finished');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await app.sync();
}

void main() {
  late FakeServer server;
  late FakeGoogle google;

  setUp(() {
    server = FakeServer();
    google = FakeGoogle();
  });

  /// One app install: its own preferences, sharing [server].
  Future<(AppController, BackendAuthService)> device({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final backend = server.backend;
    final auth = BackendAuthService(
      api: backend.api,
      tokens: backend.tokens,
      preferences: preferences,
      google: google,
    );
    await auth.init();
    final controller = AppController(
      RemoteWorkoutRepository(
        backend.api,
        LocalWorkoutRepository(preferences, templates: const []),
        preferences,
        SyncOutbox(preferences),
        currentUserId: () => auth.currentUser?.id,
      ),
      preferences,
      auth: auth,
    );
    await controller.load();
    return (controller, auth);
  }

  test('a guest\'s sessions upload when they sign in', () async {
    final (app, auth) = await device();
    await app.addSession(session('guest-1', 1));
    expect(server.docs['sessions'], isNull);

    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    expect(
      await (app.repository as RemoteWorkoutRepository).flushPendingWrites(),
      isTrue,
    );

    expect(server.docs['sessions']!.keys, ['guest-1']);
    expect(app.signedIn, isTrue);
  });

  test('sync pulls sessions and drops ones deleted elsewhere', () async {
    server.docs['sessions'] = {
      'remote-1': {'id': 'remote-1', ...session('remote-1', 2).toJson()},
      'gone': {'id': 'gone', 'deleted': true},
    };
    final (app, auth) = await device();
    // Already on this device (not a pending write) when another device
    // deleted it.
    await app.addSession(session('gone', 3));
    await auth.signInWithGoogle();
    await app.load();

    await syncNow(app);

    expect(app.sessions.map((s) => s.id), ['remote-1']);
  });

  Map<String, dynamic> mealDoc(String id, String label, String dish) => {
    'id': id,
    ...Meal(
      label: label,
      items: [MealItem(name: dish, kcal: 400)],
    ).toJson(),
  };

  test('meals sync one entry per doc and survive signing in again', () async {
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final dinnerId = '${FoodLog.dayKey(yesterday)}:1';
    // Another device logged yesterday's dinner; an entry older than the
    // kept window stays on the server and is not even downloaded.
    server.docs['meals'] = {
      dinnerId: mealDoc(dinnerId, 'Dinner', 'Pho'),
      '2000-01-01:1': mealDoc('2000-01-01:1', 'Lunch', 'Old'),
    };
    final (app, auth) = await device();
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    expect(app.foodLog.mealsOn(yesterday).single.items.single.name, 'Pho');
    expect(app.foodLog.days.keys, [FoodLog.dayKey(yesterday)]);

    const lunch = Meal(
      label: 'Lunch',
      items: [MealItem(name: 'Com tam', kcal: 650)],
    );
    await app.logMeal(today, lunch);
    await app.removeMeal(dinnerId);
    await app.removeMeal(dinnerId); // already gone: no second write
    final repo = app.repository as RemoteWorkoutRepository;
    expect(await repo.flushPendingWrites(), isTrue);
    final lunchId = app.foodLog.entriesOn(today).single.id;
    expect(server.docs['meals']![lunchId], {'id': lunchId, ...lunch.toJson()});
    expect(server.docs['meals']![dinnerId], {'id': dinnerId, 'deleted': true});
    expect(server.docs['meals']!['2000-01-01:1']!['deleted'], isNull);

    // Signing out wipes the device; signing back in restores the log.
    await app.signOut();
    expect(app.foodLog.days, isEmpty);
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    expect(app.foodLog.mealsOn(today).single.label, 'Lunch');
    expect(app.foodLog.mealsOn(yesterday), isEmpty);
  });

  test('an older local food log is rewritten in the current format', () async {
    final day = FoodLog.dayKey(DateTime.now());
    final (app, _) = await device(
      prefs: {
        'food_log_v1': jsonEncode({
          'version': 2,
          'days': {
            day: [
              const Meal(
                label: 'Lunch',
                items: [MealItem(name: 'Bun', kcal: 500)],
              ).toJson(),
            ],
          },
        }),
      },
    );
    await pumpEventQueue();
    final stored = app.preferences.getString('food_log_v1')!;
    expect(FoodLog.isCurrentFormat(stored), isTrue);
    // Ids persist across reloads instead of being re-generated.
    final id = app.foodLog.entries.single.id;
    await app.load();
    expect(app.foodLog.entries.single.id, id);
  });

  test('two devices logging the same day keep both meals', () async {
    final today = DateTime.now();
    final (phone, phoneAuth) = await device();
    await phoneAuth.signInWithGoogle();
    await phone.load();
    await syncNow(phone);
    // Logged offline on the phone…
    server.online = false;
    await phone.logMeal(
      today,
      const Meal(
        label: 'Lunch',
        items: [MealItem(name: 'Bun', kcal: 500)],
      ),
    );
    server.online = true;
    // …while the tablet logs breakfast for the same day.
    final breakfastId = '${FoodLog.dayKey(today)}:1';
    server.docs['meals']![breakfastId] = mealDoc(
      breakfastId,
      'Breakfast',
      'Banh mi',
    );

    await syncNow(phone);
    expect(
      await (phone.repository as RemoteWorkoutRepository).flushPendingWrites(),
      isTrue,
    );
    expect(phone.foodLog.mealsOn(today).map((m) => m.label).toSet(), {
      'Breakfast',
      'Lunch',
    });
    expect(
      server.docs['meals']!.values.where((doc) => doc['deleted'] == null),
      hasLength(2),
    );
  });

  test('sync status tracks success, failure and the account', () async {
    final (app, auth) = await device();
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    expect(app.lastSyncFailed, isFalse);
    expect(app.lastSyncedAt, isNotNull);

    server.online = false;
    await app.sync();
    expect(app.lastSyncFailed, isTrue);
    server.online = true;

    // Another account must not inherit this one's status.
    await app.signOut(force: true);
    expect(app.lastSyncedAt, isNull);
    expect(app.lastSyncFailed, isFalse);
  });

  test('profile changes push to the server, newest write wins', () async {
    final (app, auth) = await device();
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app); // first pull: server is empty → local pushed

    await app.setWeeklyGoal(5);
    await pumpEventQueue();
    expect(server.meta?['weeklyGoal'], 5);

    // Another device wrote later: this device's stale push adopts it.
    server.metaUpdatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
    server.meta = {...server.meta!, 'weeklyGoal': 2};
    await app.setWeeklyGoal(4);
    await pumpEventQueue();
    expect(app.weeklyGoal, 2);
  });

  test('sign-out waits for offline writes unless forced', () async {
    final (app, auth) = await device();
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    server.online = false;
    await app.addSession(session('offline', 4));

    expect(await app.signOut(), isFalse);
    expect(auth.currentUser, isNotNull);

    expect(await app.signOut(force: true), isTrue);
    expect(auth.currentUser, isNull);
    expect(app.sessions, isEmpty);

    // The discarded write never reaches the account later.
    server.online = true;
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    expect(server.docs['sessions']?.containsKey('offline') ?? false, isFalse);
  });

  test('forced sign-out keeps another account\'s queued writes', () async {
    final theirs = jsonEncode([
      const OutboxEntry(
        owner: 'someone-else',
        kind: 'sessions',
        id: 'x',
      ).toJson(),
    ]);
    final (app, auth) = await device(prefs: {'sync_outbox_v1': theirs});
    await auth.signInWithGoogle();
    await app.load();
    await syncNow(app);
    server.online = false;
    await app.addSession(session('mine', 6));

    expect(await app.signOut(force: true), isTrue);

    final left = SyncOutbox(await SharedPreferences.getInstance()).entries;
    expect(left.map((e) => e.owner), ['someone-else']);
  });

  test('deleting without an account is an error, not a success', () async {
    final (app, _) = await device();
    await expectLater(app.deleteAccount(), throwsStateError);
  });

  test('account deletion goes through the API and clears the device', () async {
    final (app, auth) = await device();
    await auth.signInWithGoogle();
    await app.load();
    await app.addSession(session('s1', 5));
    await syncNow(app);

    await app.deleteAccount();

    expect(server.accountDeleted, isTrue);
    expect(auth.currentUser, isNull);
    expect(app.sessions, isEmpty);
    expect(google.signIns, 2); // sign-in + re-authentication
  });
}
