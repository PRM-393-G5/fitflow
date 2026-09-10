import 'models/workout_session.dart';

abstract final class WorkoutStats {
  static int totalMinutes(Iterable<WorkoutSession> sessions) =>
      sessions.fold(0, (sum, session) => sum + session.durationMinutes);

  static double totalVolume(Iterable<WorkoutSession> sessions) =>
      sessions.fold(0, (sum, session) => sum + session.volumeKg);

  static int sessionsThisWeek(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final day = DateTime(current.year, current.month, current.day);
    final start = DateTime(day.year, day.month, day.day - (day.weekday - 1));
    return sessions.where((item) => !item.completedAt.isBefore(start)).length;
  }

  static int longestStreak(Iterable<WorkoutSession> sessions) {
    final dates = sessions
        .map(
          (item) => DateTime(
            item.completedAt.year,
            item.completedAt.month,
            item.completedAt.day,
          ),
        )
        .toSet();
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

  static int streak(Iterable<WorkoutSession> sessions, {DateTime? now}) {
    final dates = sessions
        .map(
          (item) => DateTime(
            item.completedAt.year,
            item.completedAt.month,
            item.completedAt.day,
          ),
        )
        .toSet();
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
}
