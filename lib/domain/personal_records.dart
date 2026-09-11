import 'models/exercise.dart';
import 'models/workout_session.dart';

/// The best recorded performance for one exercise, across all sessions.
class PersonalRecord {
  const PersonalRecord({
    required this.exerciseName,
    required this.isTimed,
    required this.value,
    required this.date,
  });

  final String exerciseName;

  /// True for duration-based exercises (planks): [value] is seconds.
  /// False for weighted exercises: [value] is weight in kg.
  final bool isTimed;
  final double value;
  final DateTime date;
}

abstract final class PersonalRecords {
  /// Heaviest weight (or longest hold for timed exercises) ever recorded
  /// per exercise name. Bodyweight rep-based exercises (weightKg == 0)
  /// are skipped — they carry no load to beat.
  static Map<String, PersonalRecord> best(
    Iterable<WorkoutSession> sessions,
  ) {
    final records = <String, PersonalRecord>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final value = exercise.isTimed
            ? exercise.durationSeconds.toDouble()
            : exercise.weightKg;
        if (value <= 0) continue;
        final current = records[exercise.name];
        if (current == null || value > current.value) {
          records[exercise.name] = PersonalRecord(
            exerciseName: exercise.name,
            isTimed: exercise.isTimed,
            value: value,
            date: session.completedAt,
          );
        }
      }
    }
    return records;
  }

  /// Exercises in [performed] that beat the all-time best in [sessions]
  /// (or set a first-ever record). Used to celebrate on workout finish.
  static List<Exercise> newRecords(
    Iterable<WorkoutSession> sessions,
    Iterable<Exercise> performed,
  ) {
    final bestSoFar = best(sessions);
    return [
      for (final exercise in performed)
        if (_beats(bestSoFar[exercise.name], exercise)) exercise,
    ];
  }

  static bool _beats(PersonalRecord? record, Exercise exercise) {
    final value = exercise.isTimed
        ? exercise.durationSeconds.toDouble()
        : exercise.weightKg;
    if (value <= 0) return false;
    return record == null || value > record.value;
  }
}
