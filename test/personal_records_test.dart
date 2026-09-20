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
    final past = [
      session(DateTime(2026, 4, 1), [weighted('Squat', 40)]),
    ];
    final performed = [weighted('Squat', 40), weighted('Squat', 50)];

    final first = PersonalRecords.newRecords(past, [performed.first]);
    final second = PersonalRecords.newRecords(past, [performed.last]);
    final debut = PersonalRecords.newRecords(past, [weighted('Row', 30)]);

    expect(first, isEmpty);
    expect(second.single.name, 'Squat');
    // No previous record: a baseline, not a PR.
    expect(debut, isEmpty);
  });

  test('first-ever workout flags no PRs', () {
    final performed = [weighted('Squat', 60), timed('Plank', 60)];

    expect(PersonalRecords.newRecords(const [], performed), isEmpty);
  });

  test('record date is the first time the best was reached', () {
    // Newest first, as the controller stores them.
    final sessions = [
      session(DateTime(2026, 4, 15), [weighted('Bench Press', 25)]),
      session(DateTime(2026, 4, 8), [weighted('Bench Press', 25)]),
      session(DateTime(2026, 4, 1), [weighted('Bench Press', 20)]),
    ];

    final record = PersonalRecords.best(sessions)['Bench Press']!;

    expect(record.value, 25);
    expect(record.date, DateTime(2026, 4, 8));
  });

  test('timed and weighted exercises sharing a name keep separate records', () {
    final sessions = [
      session(DateTime(2026, 4, 1), [timed('Plank', 90)]),
      session(DateTime(2026, 4, 2), [weighted('Plank', 20)]),
    ];

    final all = PersonalRecords.all(sessions);

    expect(all[PersonalRecord.recordKey('Plank', RecordKind.hold)]!.value, 90);
    expect(
      all[PersonalRecord.recordKey('Plank', RecordKind.weight)]!.value,
      20,
    );
    // A 25 kg weighted plank beats 20 kg, not the 90 s hold.
    expect(
      PersonalRecords.newRecords(sessions, [weighted('Plank', 25)]).single.name,
      'Plank',
    );
    expect(PersonalRecords.newRecords(sessions, [timed('Plank', 60)]), isEmpty);
  });

  test('bodyweight exercises record most reps in a set', () {
    Exercise pushups(List<int> reps) => Exercise(
      id: 'pu',
      name: 'Push-up',
      muscleGroup: 'x',
      sets: reps.length,
      performedSets: [for (final r in reps) SetEntry(amount: r)],
    );
    final sessions = [
      session(DateTime(2026, 4, 1), [
        pushups([12, 15, 10]),
      ]),
    ];

    final record = PersonalRecords.all(
      sessions,
    )[PersonalRecord.recordKey('Push-up', RecordKind.reps)]!;

    expect(record.value, 15);
    expect(PersonalRecords.best(sessions), isNot(contains('Push-up')));
    expect(
      PersonalRecords.newRecords(sessions, [
        pushups([16]),
      ]).single.name,
      'Push-up',
    );
  });

  test('estimated 1RM uses Epley over the best logged set', () {
    expect(PersonalRecords.estimatedOneRepMax(100, 1), 100);
    expect(PersonalRecords.estimatedOneRepMax(100, 10), closeTo(133.33, 0.01));
    expect(PersonalRecords.estimatedOneRepMax(100, 0), 0);

    final sessions = [
      session(DateTime(2026, 4, 1), [
        Exercise(
          id: 'b',
          name: 'Bench Press',
          muscleGroup: 'x',
          sets: 2,
          performedSets: const [
            SetEntry(amount: 3, weightKg: 100), // 110
            SetEntry(amount: 12, weightKg: 80), // 112
          ],
        ),
      ]),
    ];
    final record = PersonalRecords.best(sessions)['Bench Press']!;

    expect(record.value, 100);
    expect(record.estimatedOneRepMaxKg, closeTo(112, 0.001));
  });
}
