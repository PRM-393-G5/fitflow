import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/firestore_workout_repository.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutSession session(String id, int day) => WorkoutSession(
  id: id,
  workoutId: 'w',
  workoutName: 'W',
  startedAt: DateTime(2026, 4, day),
  completedAt: DateTime(2026, 4, day),
  completedSets: 1,
  volumeKg: 100,
);

void main() {
  test('mergeById unions lists, remote wins on shared ids', () {
    final merged = FirestoreWorkoutRepository.mergeById(
      [session('shared', 1), session('local-only', 2)],
      [session('shared', 9), session('remote-only', 3)],
      (item) => item.id,
    );

    expect(
      merged.map((item) => item.id),
      containsAll(['shared', 'local-only', 'remote-only']),
    );
    // Remote copy of 'shared' wins (day 9 over day 1).
    expect(
      merged.singleWhere((item) => item.id == 'shared').completedAt.day,
      9,
    );
  });

  test('overwriteSessions replaces stored sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWorkoutRepository(preferences);

    await repository.saveSession(session('old', 1));
    await repository.overwriteSessions([session('new', 2)]);

    expect((await repository.getRecentSessions()).map((item) => item.id), [
      'new',
    ]);
  });

  test('clearAll drops workouts and sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWorkoutRepository(preferences);

    await repository.saveSession(session('s', 1));
    await repository.clearAll();

    expect(await repository.getRecentSessions(), isEmpty);
    expect(await repository.getSavedWorkouts(), isEmpty);
  });

  test('reconcile keeps items added and drops items deleted mid-sync', () {
    final result = FirestoreWorkoutRepository.reconcile(
      [session('a', 1), session('b', 2), session('remote', 3)],
      [session('a', 1), session('b', 2)],
      [session('a', 1), session('new', 4)],
      (item) => item.id,
    );
    expect(
      result.map((item) => item.id),
      unorderedEquals(['a', 'remote', 'new']),
    );
  });

  test('decodeList skips malformed records instead of failing', () {
    final raw = '[${jsonEncode(session('ok', 1).toJson())}, {"id": "broken"}]';
    final sessions = LocalWorkoutRepository.decodeList(
      raw,
      WorkoutSession.fromJson,
    );
    expect(sessions.map((item) => item.id), ['ok']);
  });

  test('deleteSession removes only that session', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWorkoutRepository(preferences);

    await repository.saveSession(session('keep', 1));
    await repository.saveSession(session('drop', 2));
    await repository.deleteSession('drop');

    expect((await repository.getRecentSessions()).map((item) => item.id), [
      'keep',
    ]);
  });

  test('reconcile keeps a local edit made mid-sync over the merged copy', () {
    final original = session('a', 1);
    final edited = session('a', 5);
    final result = FirestoreWorkoutRepository.reconcile(
      [session('a', 9)],
      [original],
      [edited],
      (item) => item.id,
    );
    expect(result.single.completedAt.day, 5);
  });

  test('reconcile takes the merged copy of untouched items', () {
    final original = session('a', 1);
    final result = FirestoreWorkoutRepository.reconcile(
      [session('a', 9)],
      [original],
      [original],
      (item) => item.id,
    );
    expect(result.single.completedAt.day, 9);
  });
}
