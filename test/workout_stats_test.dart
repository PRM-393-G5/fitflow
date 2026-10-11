import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/workout_stats.dart';

WorkoutSession session(
  DateTime day, {
  int minutes = 30,
  double volume = 100,
  int sets = 3,
  String workoutId = 'workout',
  String name = 'Workout',
  List<Exercise> exercises = const [],
}) => WorkoutSession(
  id: day.toIso8601String(),
  workoutId: workoutId,
  workoutName: name,
  startedAt: day.subtract(Duration(minutes: minutes)),
  completedAt: day,
  completedSets: sets,
  volumeKg: volume,
  exercises: exercises,
);

void main() {
  test('calculates totals and weekly activity', () {
    final now = DateTime(2026, 4, 8, 12);
    final sessions = [
      session(DateTime(2026, 4, 8, 10), volume: 300),
      session(DateTime(2026, 4, 7, 10), minutes: 20, volume: 200),
      session(DateTime(2026, 4, 6, 10), minutes: 10, volume: 100),
      session(DateTime(2026, 3, 20, 10)),
    ];

    expect(WorkoutStats.totalMinutes(sessions), 90);
    expect(WorkoutStats.totalVolume(sessions), 700);
    expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 3);
  });

  group('weekly streak', () {
    // Mon/Wed/Fri for [weeks] weeks starting Monday 2026-03-02.
    List<WorkoutSession> monWedFri(int weeks, {DateTime? from}) {
      final start = from ?? DateTime(2026, 3, 2);
      return [
        for (var w = 0; w < weeks; w++)
          for (final day in const [0, 2, 4])
            session(
              DateTime(start.year, start.month, start.day + 7 * w + day, 18),
            ),
      ];
    }

    test('rest days between sessions never break it', () {
      // Friday evening of week 5, after the last workout.
      final now = DateTime(2026, 4, 3, 20);
      final streak = WorkoutStats.weeklyStreak(monWedFri(5), 3, now: now);

      expect(streak.current, 5);
      expect(streak.longest, 5);
    });

    test('a week still in progress keeps the streak alive', () {
      final sessions = [
        ...monWedFri(5),
        session(DateTime(2026, 4, 6, 18)), // Monday of week 6
      ];
      final tuesday = DateTime(2026, 4, 7, 12);
      final streak = WorkoutStats.weeklyStreak(sessions, 3, now: tuesday);

      expect(streak.current, 5);
      expect(WorkoutStats.sessionsThisWeek(sessions, now: tuesday), 1);
    });

    test('a finished week below the goal breaks it', () {
      final sessions = [
        ...monWedFri(2),
        // Week 3: only two sessions against a goal of three.
        session(DateTime(2026, 3, 16, 18)),
        session(DateTime(2026, 3, 18, 18)),
        ...monWedFri(2, from: DateTime(2026, 3, 23)),
      ];
      final nextMonday = DateTime(2026, 4, 6, 9);
      final streak = WorkoutStats.weeklyStreak(sessions, 3, now: nextMonday);

      expect(streak.current, 2);
      expect(streak.longest, 2);
      // Two sessions a week clears a goal of two every week.
      expect(
        WorkoutStats.weeklyStreak(sessions, 2, now: nextMonday).current,
        5,
      );
    });

    test('a week without any session ends it', () {
      final sessions = monWedFri(3);
      // Week 4 was skipped entirely; now it is Wednesday of week 5.
      final now = DateTime(2026, 4, 1, 12);

      expect(WorkoutStats.weeklyStreak(sessions, 3, now: now).current, 0);
      expect(WorkoutStats.weeklyStreak(sessions, 3, now: now).longest, 3);
    });

    test('ignores future-dated weeks and form checks', () {
      final now = DateTime(2026, 3, 13, 20); // Friday of week 2
      final sessions = [
        ...monWedFri(4),
        for (var day = 9; day <= 13; day++)
          session(
            DateTime(2026, 3, day, 7),
            workoutId: WorkoutStats.formCheckId,
            sets: 1,
          ),
      ];
      final streak = WorkoutStats.weeklyStreak(sessions, 3, now: now);

      expect(streak.current, 2);
      expect(streak.longest, 2);
      expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 3);
      expect(WorkoutStats.weeklyStreak(const <WorkoutSession>[], 3, now: now), (
        current: 0,
        longest: 0,
      ));
    });
  });

  test('this week excludes future sessions and next week', () {
    final now = DateTime(2026, 4, 8, 12); // Wednesday
    final sessions = [
      session(DateTime(2026, 4, 6, 8)), // Monday, counted
      session(DateTime(2026, 4, 12, 23)), // Sunday, counted
      session(DateTime(2026, 4, 13, 0, 30)), // next Monday
      session(DateTime(2026, 4, 5, 23)), // last Sunday
    ];

    expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 2);
  });

  test('this week stays bounded across a DST change', () {
    // 2026-03-29 is the EU spring-forward Sunday.
    final now = DateTime(2026, 3, 25, 12);
    final sessions = [
      session(DateTime(2026, 3, 29, 22)),
      session(DateTime(2026, 3, 30, 1)),
    ];

    expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 1);
  });

  test('empty sessions do not count toward stats', () {
    final now = DateTime(2026, 4, 8, 12);
    final sessions = [
      session(DateTime(2026, 4, 8, 10), sets: 0),
      session(DateTime(2026, 4, 7, 10)),
    ];

    expect(WorkoutStats.totalMinutes(sessions), 30);
    expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 1);
    expect(WorkoutStats.weeklyStreak(sessions, 1, now: now).current, 1);
  });

  test('form checks are not training sessions', () {
    final now = DateTime(2026, 4, 8, 12);
    final sessions = [
      session(DateTime(2026, 4, 8, 10), minutes: 40),
      for (var day = 6; day <= 8; day++)
        session(
          DateTime(2026, 4, day, 7),
          workoutId: WorkoutStats.formCheckId,
          minutes: 2,
          volume: 0,
          sets: 1,
        ),
    ];

    expect(WorkoutStats.training(sessions), hasLength(1));
    expect(WorkoutStats.totalMinutes(sessions), 40);
    expect(WorkoutStats.sessionsThisWeek(sessions, now: now), 1);
    // One real session: a goal of 1 is met, the form checks add nothing.
    expect(WorkoutStats.weeklyStreak(sessions, 1, now: now).current, 1);
    expect(WorkoutStats.weeklyStreak(sessions, 2, now: now).current, 0);
  });

  test('goals outside 1–7 are measured as 1 or 7', () {
    // Seven sessions, Monday to Sunday.
    final sessions = [
      for (var day = 2; day <= 8; day++) session(DateTime(2026, 3, day, 9)),
    ];
    final now = DateTime(2026, 3, 9, 12);

    expect(WorkoutStats.weeklyStreak(sessions, 10, now: now).current, 1);
    expect(WorkoutStats.weeklyStreak(sessions, 0, now: now).current, 1);
  });

  // Only crosses a DST change on machines in a DST time zone (e.g. run
  // with TZ=Europe/Berlin); under UTC it passes trivially.
  test('weekly streak spans a DST change', () {
    List<WorkoutSession> week(DateTime monday, int count) => [
      for (var i = 0; i < count; i++)
        session(DateTime(monday.year, monday.month, monday.day + i, 9)),
    ];
    final sessions = [
      ...week(DateTime(2026, 3, 2), 3),
      ...week(DateTime(2026, 3, 9), 3),
      ...week(DateTime(2026, 3, 16), 2), // misses a goal of 3
      ...week(DateTime(2026, 3, 23), 3),
      ...week(DateTime(2026, 3, 30), 4), // spans the DST change
      ...week(DateTime(2026, 4, 6), 3),
    ];

    final now = DateTime(2026, 4, 10, 12);
    final goalThree = WorkoutStats.weeklyStreak(sessions, 3, now: now);
    expect(goalThree.longest, 3);
    expect(goalThree.current, 3);
    expect(WorkoutStats.weeklyStreak(sessions, 2, now: now).longest, 6);
  });

  test('form-check results read old and new session formats', () {
    final day = DateTime(2026, 4, 8);
    final oldPlank = session(
      day,
      workoutId: 'form-check',
      name: 'Plank Form Check (45s)',
      sets: 45,
    );
    final oldSquat = session(
      day,
      workoutId: 'form-check',
      name: 'Squat Form Check (12 reps)',
      sets: 12,
    );
    final newSquat = session(
      day,
      workoutId: 'form-check',
      name: 'Squat Form Check (9 reps)',
      sets: 1,
      exercises: const [
        Exercise(
          id: 'squat',
          name: 'Squat',
          muscleGroup: 'Legs',
          sets: 1,
          reps: 9,
          performedSets: [SetEntry(amount: 9)],
        ),
      ],
    );

    expect(WorkoutStats.formCheckLabel(oldPlank), '45 s hold');
    expect(WorkoutStats.formCheckLabel(oldSquat), '12 reps');
    expect(WorkoutStats.formCheckLabel(newSquat), '9 reps');
    expect(WorkoutStats.formCheckLabel(session(day)), isNull);
  });
}
