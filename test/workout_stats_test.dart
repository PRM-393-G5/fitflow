import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/workout_stats.dart';

WorkoutSession session(DateTime day, {int minutes = 30, double volume = 100}) =>
    WorkoutSession(
      id: day.toIso8601String(),
      workoutId: 'workout',
      workoutName: 'Workout',
      startedAt: day.subtract(Duration(minutes: minutes)),
      completedAt: day,
      completedSets: 3,
      volumeKg: volume,
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
}
