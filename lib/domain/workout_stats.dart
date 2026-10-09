import 'models/workout_session.dart';

/// What a form-check session recorded: reps, or seconds held for planks.
typedef FormCheckResult = ({int amount, bool timed});

abstract final class WorkoutStats {
  /// Workout id given to camera form-check sessions.
  static const formCheckId = 'form-check';

  /// Sessions that actually trained something. Empty sessions
  /// (completedSets == 0) should never be saved, but are excluded from
  /// every stat defensively.
  static Iterable<WorkoutSession> counted(Iterable<WorkoutSession> sessions) =>
      sessions.where((item) => item.completedSets > 0);

  static int totalMinutes(Iterable<WorkoutSession> sessions) =>
      counted(sessions)
          .fold(0, (sum, session) => sum + session.durationMinutes);

  static double totalVolume(Iterable<WorkoutSession> sessions) =>
      counted(sessions).fold(0, (sum, session) => sum + session.volumeKg);

  /// Counted sessions completed in the current Monday-based week.
  static List<WorkoutSession> thisWeek(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) {
    final start = _monday(now ?? DateTime.now());
    // Calendar construction (not Duration) keeps this DST-safe.
    final end = DateTime(start.year, start.month, start.day + 7);
    return counted(sessions)
        .where(
          (item) =>
              !item.completedAt.isBefore(start) &&
              item.completedAt.isBefore(end),
        )
        .toList();
  }

  /// Sessions completed in the current Monday-based calendar week.
  static int sessionsThisWeek(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) => thisWeek(sessions, now: now).length;

  static int longestStreak(Iterable<WorkoutSession> sessions) {
    final dates = _days(sessions);
    var best = 0;
    for (final day in dates) {
      if (dates.contains(DateTime(day.year, day.month, day.day - 1))) {
        continue;
      }
      var run = 0;
      var cursor = day;
      while (dates.contains(cursor)) {
        run++;
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
      if (run > best) best = run;
    }
    return best;
  }

  /// Current run of consecutive training days ending today (or yesterday,
  /// so the streak survives until today's workout is done).
  static int streak(Iterable<WorkoutSession> sessions, {DateTime? now}) {
    final dates = _days(sessions);
    if (dates.isEmpty) return 0;
    var cursor = now ?? DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    if (!dates.contains(cursor)) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    var count = 0;
    while (dates.contains(cursor)) {
      count++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  /// Longest run of consecutive Monday-based weeks with at least
  /// [weeklyGoal] sessions each.
  static int longestWeeklyGoalStreak(
    Iterable<WorkoutSession> sessions,
    int weeklyGoal,
  ) {
    final perWeek = <DateTime, int>{};
    for (final session in counted(sessions)) {
      final week = _monday(session.completedAt);
      perWeek[week] = (perWeek[week] ?? 0) + 1;
    }
    final hit = {
      for (final entry in perWeek.entries)
        if (entry.value >= weeklyGoal.clamp(1, 7)) entry.key,
    };
    var best = 0;
    for (final week in hit) {
      if (hit.contains(DateTime(week.year, week.month, week.day - 7))) {
        continue;
      }
      var run = 0;
      var cursor = week;
      while (hit.contains(cursor)) {
        run++;
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
      }
      if (run > best) best = run;
    }
    return best;
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

  static Set<DateTime> _days(Iterable<WorkoutSession> sessions) => {
    for (final item in counted(sessions))
      DateTime(
        item.completedAt.year,
        item.completedAt.month,
        item.completedAt.day,
      ),
  };

  static DateTime _monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));
}
