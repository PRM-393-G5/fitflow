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
    expect(await repository.getWorkouts(), isEmpty);
  });
}
