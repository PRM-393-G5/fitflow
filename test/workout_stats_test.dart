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
  test('calculates totals, weekly activity, and consecutive-day streak', () {
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
    expect(WorkoutStats.streak(sessions, now: now), 3);
  });

  test('finds the longest historical streak', () {
    final sessions = [
      session(DateTime(2026, 4, 8)),
      session(DateTime(2026, 4, 1)),
      session(DateTime(2026, 3, 31)),
      session(DateTime(2026, 3, 30)),
      session(DateTime(2026, 3, 29)),
    ];

    expect(WorkoutStats.longestStreak(sessions), 4);
    expect(WorkoutStats.longestStreak(const <WorkoutSession>[]), 0);
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
    expect(WorkoutStats.streak(sessions, now: now), 1);
    expect(WorkoutStats.longestStreak(sessions), 1);
  });

  test('weekly-goal streak counts consecutive weeks hitting the goal', () {
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

    expect(WorkoutStats.longestWeeklyGoalStreak(sessions, 3), 3);
    expect(WorkoutStats.longestWeeklyGoalStreak(sessions, 2), 6);
    expect(WorkoutStats.longestWeeklyGoalStreak(const [], 3), 0);
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
