import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/personal_records.dart';

Exercise weighted(String name, double kg) =>
    Exercise(id: name, name: name, muscleGroup: 'x', sets: 3, weightKg: kg);

Exercise timed(String name, int seconds) => Exercise(
  id: name,
  name: name,
  muscleGroup: 'x',
  sets: 1,
  durationSeconds: seconds,
);

WorkoutSession session(DateTime day, List<Exercise> exercises) =>
    WorkoutSession(
      id: day.toIso8601String(),
      workoutId: 'workout',
      workoutName: 'Workout',
      startedAt: day,
      completedAt: day,
      completedSets: 3,
      volumeKg: 0,
      exercises: exercises,
    );

void main() {
  test('keeps the heaviest weight per exercise across sessions', () {
    final sessions = [
      session(DateTime(2026, 4, 1), [weighted('Bench Press', 20)]),
      session(DateTime(2026, 4, 8), [weighted('Bench Press', 25)]),
      session(DateTime(2026, 4, 15), [weighted('Bench Press', 22.5)]),
    ];

    final records = PersonalRecords.best(sessions);

    expect(records['Bench Press']!.value, 25);
    expect(records['Bench Press']!.date, DateTime(2026, 4, 15 - 7));
    expect(records['Bench Press']!.isTimed, isFalse);
  });

  test('uses hold duration for timed exercises and skips bodyweight', () {
    final sessions = [
      session(DateTime(2026, 4, 1), [timed('Plank', 30), weighted('Squat', 0)]),
      session(DateTime(2026, 4, 8), [timed('Plank', 45)]),
    ];

    final records = PersonalRecords.best(sessions);

    expect(records['Plank']!.value, 45);
    expect(records['Plank']!.isTimed, isTrue);
    expect(records.containsKey('Squat'), isFalse);
  });

  test('flags only exercises that beat the previous best', () {
    final past = [session(DateTime(2026, 4, 1), [weighted('Squat', 40)])];
    final performed = [weighted('Squat', 40), weighted('Squat', 50)];

    final first = PersonalRecords.newRecords(past, [performed.first]);
    final second = PersonalRecords.newRecords(past, [performed.last]);
    final debut = PersonalRecords.newRecords(past, [weighted('Row', 30)]);

    expect(first, isEmpty);
    expect(second.single.name, 'Squat');
    expect(debut.single.name, 'Row');
  });
}
