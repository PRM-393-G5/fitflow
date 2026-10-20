import 'package:clock/clock.dart';

import 'models/workout_session.dart';

/// What a form-check session recorded: reps, or seconds held for planks.
typedef FormCheckResult = ({int amount, bool timed});

/// Consecutive weeks reaching the weekly goal; see
/// [WorkoutStats.weeklyStreak].
typedef WeeklyStreak = ({
  /// Run ending this week (if its goal is met) or last week.
  int current,

  /// Longest run ever.
  int longest,
});

abstract final class WorkoutStats {
  /// Workout id given to camera form-check sessions.
  static const formCheckId = 'form-check';

  /// Sessions that actually trained something. Empty sessions
  /// (completedSets == 0) should never be saved, but are excluded from
  /// every stat defensively.
  static Iterable<WorkoutSession> counted(Iterable<WorkoutSession> sessions) =>
      sessions.where((item) => item.completedSets > 0);

  /// Counted workouts, without camera form checks: a single test set is
  /// not a training session, so it never counts toward session totals,
  /// minutes, the weekly goal, streaks or badges.
  static Iterable<WorkoutSession> training(Iterable<WorkoutSession> sessions) =>
      counted(sessions).where((item) => item.workoutId != formCheckId);

  static int totalMinutes(Iterable<WorkoutSession> sessions) =>
      training(sessions)
          .fold(0, (sum, session) => sum + session.durationMinutes);

  static double totalVolume(Iterable<WorkoutSession> sessions) =>
      training(sessions).fold(0, (sum, session) => sum + session.volumeKg);

  /// Training sessions completed in the current Monday-based week.
  static List<WorkoutSession> thisWeek(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) {
    final start = _monday(now ?? clock.now());
    // Calendar construction (not Duration) keeps this DST-safe.
    final end = DateTime(start.year, start.month, start.day + 7);
    return training(sessions)
        .where(
          (item) =>
              !item.completedAt.isBefore(start) &&
              item.completedAt.isBefore(end),
        )
        .toList();
  }

  /// Training sessions completed in the current Monday-based week.
  static int sessionsThisWeek(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) => thisWeek(sessions, now: now).length;

  /// Weekly consistency streak, counted in Monday-based weeks that reach
  /// [weeklyGoal] training sessions — rest days never break it.
  ///
  /// [WeeklyStreak.current] runs back from the current week if its goal is
  /// already met, else from last week: a week still in progress has not
  /// failed yet. Weeks after the current one (future-dated sessions) are
  /// ignored.
  static WeeklyStreak weeklyStreak(
    Iterable<WorkoutSession> sessions,
    int weeklyGoal, {
    DateTime? now,
  }) {
    final thisMonday = _monday(now ?? clock.now());
    final goal = weeklyGoal.clamp(1, 7);
    final perWeek = <DateTime, int>{};
    for (final session in training(sessions)) {
      final week = _monday(session.completedAt);
      if (week.isAfter(thisMonday)) continue;
      perWeek[week] = (perWeek[week] ?? 0) + 1;
    }
    final hit = {
      for (final entry in perWeek.entries)
        if (entry.value >= goal) entry.key,
    };

    int runFrom(DateTime week, int direction) {
      var run = 0;
      var cursor = week;
      while (hit.contains(cursor)) {
        run++;
        cursor = DateTime(
          cursor.year,
          cursor.month,
          cursor.day + 7 * direction,
        );
      }
      return run;
    }

    final thisWeekMet = hit.contains(thisMonday);
    final current = runFrom(
      thisWeekMet ? thisMonday : _previousWeek(thisMonday),
      -1,
    );
    var longest = 0;
    for (final week in hit) {
      // Only start counting at the first week of a run.
      if (hit.contains(_previousWeek(week))) continue;
      final run = runFrom(week, 1);
      if (run > longest) longest = run;
    }
    return (current: current, longest: longest);
  }

  /// The reps (or hold seconds) of a form-check session, or null for
  /// regular workouts. Newer sessions store one set on an exercise
  /// snapshot; older ones kept the count in completedSets, with the unit
  /// only in the name ("Plank Form Check (45s)").
  static FormCheckResult? formCheck(WorkoutSession session) {
    if (session.workoutId != formCheckId) return null;
    if (session.exercises.isNotEmpty) {
      final exercise = session.exercises.first;
      final amount = exercise.performedSets.isNotEmpty
          ? exercise.performedSets.first.amount
          : exercise.isTimed
          ? exercise.durationSeconds
          : exercise.reps;
      return (amount: amount, timed: exercise.isTimed);
    }
    final name = session.workoutName;
    final timed =
        name.toLowerCase().contains('plank') ||
        RegExp(r'\(\d+s\)$').hasMatch(name);
    return (amount: session.completedSets, timed: timed);
  }

  /// "12 reps" / "45 s hold" for form checks; null for regular workouts.
  static String? formCheckLabel(WorkoutSession session) {
    final result = formCheck(session);
    if (result == null) return null;
    return result.timed ? '${result.amount} s hold' : '${result.amount} reps';
  }

  static DateTime _monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  static DateTime _previousWeek(DateTime monday) =>
      DateTime(monday.year, monday.month, monday.day - 7);
}
