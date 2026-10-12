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

  test('estimated 1RM uses Epley, counting at most ten reps', () {
    expect(PersonalRecords.estimatedOneRepMax(100, 1), 100);
    expect(PersonalRecords.estimatedOneRepMax(100, 10), closeTo(133.33, 0.01));
    expect(PersonalRecords.estimatedOneRepMax(100, 0), 0);
    // Past ten reps the equations stop predicting a max, so a long set
    // counts as ten: a lower bound, never below the weight lifted.
    expect(PersonalRecords.estimatedOneRepMax(100, 11), closeTo(133.33, 0.01));
    expect(PersonalRecords.estimatedOneRepMax(20, 50), closeTo(26.67, 0.01));

    final sessions = [
      session(DateTime(2026, 4, 1), [
        Exercise(
          id: 'b',
          name: 'Bench Press',
          muscleGroup: 'x',
          sets: 2,
          performedSets: const [
            SetEntry(amount: 3, weightKg: 100), // 110
            SetEntry(amount: 12, weightKg: 80), // counted as 10: 106.7
          ],
        ),
      ]),
    ];
    final record = PersonalRecords.best(sessions)['Bench Press']!;

    expect(record.value, 100);
    expect(record.estimatedOneRepMaxKg, closeTo(110, 0.001));
    expect(record.bestSet!.amount, 3);
    expect(record.bestSet!.weightKg, 100);
  });

  group('loaded records', () {
    Exercise lift(List<SetEntry> sets, {String name = 'Bench Press'}) =>
        Exercise(
          id: name,
          name: name,
          muscleGroup: 'x',
          sets: sets.length,
          performedSets: sets,
        );
    final past = [
      session(DateTime(2026, 4, 1), [
        lift(const [SetEntry(amount: 8, weightKg: 60)]),
      ]),
    ];

    test('a kg/lb round trip is the same load, not a record', () {
      // 60 kg shows as 132.3 lb; re-typing that stores 60.0103 kg.
      final retyped = lift(const [SetEntry(amount: 8, weightKg: 60.0103)]);
      final sessions = [
        ...past,
        session(DateTime(2026, 4, 8), [retyped]),
      ];

      expect(PersonalRecords.newRecords(past, [retyped]), isEmpty);
      final record = PersonalRecords.best(sessions)['Bench Press']!;
      expect(record.value, 60);
      expect(record.date, DateTime(2026, 4, 1));
      expect(record.lastImprovedAt, DateTime(2026, 4, 1));
    });

    test('more reps at a load lifted before is a record', () {
      final moreReps = lift(const [SetEntry(amount: 10, weightKg: 60)]);
      final same = lift(const [SetEntry(amount: 8, weightKg: 60)]);

      expect(PersonalRecords.newRecords(past, [moreReps]), hasLength(1));
      expect(PersonalRecords.newRecords(past, [same]), isEmpty);
    });

    test('a rep record moves the record date, not the heaviest date', () {
      final sessions = [
        session(DateTime(2026, 1, 1), [
          lift(const [SetEntry(amount: 5, weightKg: 60)]),
        ]),
        session(DateTime(2026, 4, 1), [
          lift(const [SetEntry(amount: 8, weightKg: 60)]),
        ]),
      ];
      final record = PersonalRecords.best(sessions)['Bench Press']!;

      expect(record.date, DateTime(2026, 1, 1)); // 60 kg first lifted
      expect(record.lastImprovedAt, DateTime(2026, 4, 1));
    });

    test('a better estimated 1RM alone is a record', () {
      final history = [
        session(DateTime(2026, 4, 1), [
          lift(const [
            SetEntry(amount: 3, weightKg: 60), // heaviest; 1RM ≈ 66 kg
            SetEntry(amount: 12, weightKg: 30),
          ]),
        ]),
      ];
      // Lighter, at a new load, but 1RM ≈ 67.7 kg.
      final harder = lift(const [SetEntry(amount: 5, weightKg: 58)]);

      expect(PersonalRecords.newRecords(history, [harder]), hasLength(1));
    });

    test('a missed set after long sets is not a record', () {
      // Seed-style 3 × 12: before the cap, the history's estimate was 0
      // and any shorter set looked like a new 1RM.
      final history = [
        session(DateTime(2026, 4, 1), [
          lift(name: 'Row', const [
            SetEntry(amount: 12, weightKg: 10),
            SetEntry(amount: 12, weightKg: 10),
          ]),
        ]),
      ];
      final worse = lift(name: 'Row', const [
        SetEntry(amount: 12, weightKg: 10),
        SetEntry(amount: 9, weightKg: 10),
      ]);

      expect(PersonalRecords.newRecords(history, [worse]), isEmpty);
    });

    test('the estimate never sits below the heaviest set', () {
      final history = [
        session(DateTime(2026, 4, 1), [
          lift(const [
            SetEntry(amount: 12, weightKg: 100),
            SetEntry(amount: 5, weightKg: 60),
          ]),
        ]),
      ];
      final record = PersonalRecords.best(history)['Bench Press']!;

      expect(record.estimatedOneRepMaxKg, greaterThan(100));
      expect(
        PersonalRecords.newRecords(history, [
          lift(const [SetEntry(amount: 3, weightKg: 75)]),
        ]),
        isEmpty,
      );
    });

    test('a light warm-up at a new load is not a record', () {
      final history = [
        session(DateTime(2026, 4, 1), [
          lift(const [SetEntry(amount: 5, weightKg: 100)]),
        ]),
      ];
      final warmUpDay = lift(const [
        SetEntry(amount: 15, weightKg: 40),
        SetEntry(amount: 3, weightKg: 90),
      ]);

      expect(PersonalRecords.newRecords(history, [warmUpDay]), isEmpty);
    });

    test('an old plan-only session is a real baseline', () {
      // Sessions from before per-set logging kept only the plan; reps
      // default to 0. Its load still proves at least one rep.
      final history = [
        session(DateTime(2026, 4, 1), [weighted('Bench Press', 50)]),
      ];

      expect(
        PersonalRecords.newRecords(history, [
          lift(const [SetEntry(amount: 5, weightKg: 20)]),
        ]),
        isEmpty,
      );
    });

    test('the result does not depend on session order', () {
      final sessions = [
        session(DateTime(2026, 4, 1), [
          lift(const [SetEntry(amount: 5, weightKg: 60)]),
        ]),
        session(DateTime(2026, 4, 8), [
          lift(const [SetEntry(amount: 5, weightKg: 60.04)]),
        ]),
        session(DateTime(2026, 4, 15), [
          lift(const [SetEntry(amount: 5, weightKg: 60.02)]),
        ]),
      ];
      final forward = PersonalRecords.best(sessions)['Bench Press']!;
      final backward = PersonalRecords.best(sessions.reversed)['Bench Press']!;

      expect(forward.value, 60);
      expect(forward.date, DateTime(2026, 4, 1));
      expect(backward.value, forward.value);
      expect(backward.date, forward.date);
    });

    test('sessions at the same time are read in id order', () {
      final at = DateTime(2026, 4, 1, 9);
      WorkoutSession withId(String id, double kg) => WorkoutSession(
        id: id,
        workoutId: 'workout',
        workoutName: 'Workout',
        startedAt: at,
        completedAt: at,
        completedSets: 1,
        volumeKg: 0,
        exercises: [
          lift([SetEntry(amount: 5, weightKg: kg)]),
        ],
      );
      final a = withId('a', 60);
      final b = withId('b', 60.04);

      expect(PersonalRecords.best([a, b])['Bench Press']!.value, 60);
      expect(PersonalRecords.best([b, a])['Bench Press']!.value, 60);
    });

    test('an exercise done twice in one workout is listed once', () {
      final heavier = lift(const [SetEntry(amount: 8, weightKg: 70)]);

      expect(
        PersonalRecords.newRecords(past, [heavier, heavier]),
        hasLength(1),
      );
    });
  });
}
