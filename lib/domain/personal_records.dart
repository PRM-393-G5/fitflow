import 'models/exercise.dart';
import 'models/workout_session.dart';

/// What a record measures.
enum RecordKind {
  /// Heaviest loaded set, in kg.
  weight,

  /// Longest hold of a timed exercise, in seconds.
  hold,

  /// Most reps in one set of a bodyweight exercise.
  reps,
}

/// The best recorded performance for one exercise, across all sessions.
class PersonalRecord {
  const PersonalRecord({
    required this.exerciseName,
    required this.kind,
    required this.value,
    required this.date,
    this.estimatedOneRepMaxKg = 0,
  });

  final String exerciseName;
  final RecordKind kind;

  /// kg for [RecordKind.weight], seconds for [RecordKind.hold], reps for
  /// [RecordKind.reps].
  final double value;

  /// When [value] was first reached.
  final DateTime date;

  /// Best Epley estimate over all logged sets; weight records only.
  final double estimatedOneRepMaxKg;

  /// True for duration-based exercises (planks): [value] is seconds.
  bool get isTimed => kind == RecordKind.hold;

  /// Records are per exercise name *and* kind, so a timed and a weighted
  /// exercise sharing a name never compete.
  String get key => recordKey(exerciseName, kind);

  static String recordKey(String name, RecordKind kind) => '$name|${kind.name}';
}

/// One exercise's best values within a single session.
typedef _Performance = ({RecordKind kind, double value, double oneRepMax});

abstract final class PersonalRecords {
  /// Epley estimated one-rep max: weight × (1 + reps / 30). A single rep
  /// is already a 1RM, so it is returned as-is.
  static double estimatedOneRepMax(double weightKg, int reps) {
    if (weightKg <= 0 || reps <= 0) return 0;
    if (reps == 1) return weightKg;
    return weightKg * (1 + reps / 30);
  }

  /// Every record keyed by [PersonalRecord.key]. Ties keep the earliest
  /// date — the record dates from when it was first achieved.
  static Map<String, PersonalRecord> all(Iterable<WorkoutSession> sessions) {
    final records = <String, PersonalRecord>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final performance = _performanceOf(exercise);
        if (performance == null) continue;
        final key = PersonalRecord.recordKey(exercise.name, performance.kind);
        final current = records[key];
        final date = session.completedAt;
        final better =
            current == null ||
            performance.value > current.value ||
            (performance.value == current.value && date.isBefore(current.date));
        final oneRepMax = current == null
            ? performance.oneRepMax
            : performance.oneRepMax > current.estimatedOneRepMaxKg
            ? performance.oneRepMax
            : current.estimatedOneRepMaxKg;
        records[key] = PersonalRecord(
          exerciseName: exercise.name,
          kind: performance.kind,
          value: better ? performance.value : current.value,
          date: better ? date : current.date,
          estimatedOneRepMaxKg: oneRepMax,
        );
      }
    }
    return records;
  }

  /// Heaviest weight (or longest hold for timed exercises) per exercise
  /// name. Bodyweight rep records are left out — see [all]. When a name
  /// has both a weighted and a timed record, the weighted one wins.
  static Map<String, PersonalRecord> best(Iterable<WorkoutSession> sessions) {
    final records = <String, PersonalRecord>{};
    for (final record in all(sessions).values) {
      if (record.kind == RecordKind.reps) continue;
      final existing = records[record.exerciseName];
      if (existing == null || record.kind == RecordKind.weight) {
        records[record.exerciseName] = record;
      }
    }
    return records;
  }

  /// Exercises in [performed] that beat a previous record of the same
  /// kind in [sessions]. A first-ever performance sets a baseline rather
  /// than a PR, so a debut workout never floods the celebration toast.
  static List<Exercise> newRecords(
    Iterable<WorkoutSession> sessions,
    Iterable<Exercise> performed,
  ) {
    final previous = all(sessions);
    return [
      for (final exercise in performed)
        if (_beats(previous, exercise)) exercise,
    ];
  }

  static bool _beats(Map<String, PersonalRecord> previous, Exercise exercise) {
    final performance = _performanceOf(exercise);
    if (performance == null) return false;
    final record =
        previous[PersonalRecord.recordKey(exercise.name, performance.kind)];
    return record != null && performance.value > record.value;
  }

  /// Best single-set value: heaviest kg for loaded exercises, most reps
  /// for bodyweight ones, longest hold for timed. Falls back to the plan
  /// snapshot for sessions recorded before per-set logging existed.
  /// Null when nothing measurable was done.
  static _Performance? _performanceOf(Exercise exercise) {
    if (exercise.isTimed) {
      var hold = exercise.performedSets.isEmpty ? exercise.durationSeconds : 0;
      for (final set in exercise.performedSets) {
        if (set.amount > hold) hold = set.amount;
      }
      return hold > 0
          ? (kind: RecordKind.hold, value: hold.toDouble(), oneRepMax: 0)
          : null;
    }
    if (exercise.performedSets.isEmpty) {
      if (exercise.weightKg > 0) {
        return (
          kind: RecordKind.weight,
          value: exercise.weightKg,
          oneRepMax: estimatedOneRepMax(exercise.weightKg, exercise.reps),
        );
      }
      return exercise.reps > 0
          ? (
              kind: RecordKind.reps,
              value: exercise.reps.toDouble(),
              oneRepMax: 0,
            )
          : null;
    }
    var heaviest = 0.0;
    var oneRepMax = 0.0;
    var reps = 0;
    for (final set in exercise.performedSets) {
      if (set.amount <= 0) continue;
      if (set.weightKg > 0) {
        if (set.weightKg > heaviest) heaviest = set.weightKg;
        final estimate = estimatedOneRepMax(set.weightKg, set.amount);
        if (estimate > oneRepMax) oneRepMax = estimate;
      } else if (set.amount > reps) {
        reps = set.amount;
      }
    }
    // A loaded exercise with a bodyweight drop set is still a lift.
    if (heaviest > 0) {
      return (kind: RecordKind.weight, value: heaviest, oneRepMax: oneRepMax);
    }
    return reps > 0
        ? (kind: RecordKind.reps, value: reps.toDouble(), oneRepMax: 0)
        : null;
  }
}
