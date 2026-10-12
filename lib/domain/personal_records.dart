import 'load_math.dart';
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
    this.bestSet,
  });

  final String exerciseName;
  final RecordKind kind;

  /// kg for [RecordKind.weight], seconds for [RecordKind.hold], reps for
  /// [RecordKind.reps].
  final double value;

  /// When [value] was first reached.
  final DateTime date;

  /// Best Epley estimate over all sets of at most
  /// [PersonalRecords.maxRepsForEstimate] reps; weight records only, 0
  /// when no set qualifies.
  final double estimatedOneRepMaxKg;

  /// The set with the most volume (kg × reps), first reached; weight
  /// records only.
  final SetEntry? bestSet;

  /// kg × reps of [bestSet]; 0 without one.
  double get bestSetVolumeKg =>
      bestSet == null ? 0 : bestSet!.weightKg * bestSet!.amount;

  /// True for duration-based exercises (planks): [value] is seconds.
  bool get isTimed => kind == RecordKind.hold;

  /// Records are per exercise name *and* kind, so a timed and a weighted
  /// exercise sharing a name never compete.
  String get key => recordKey(exerciseName, kind);

  static String recordKey(String name, RecordKind kind) => '$name|${kind.name}';
}

/// One exercise's best values within a single session.
typedef _Performance = ({
  RecordKind kind,
  double value,
  double oneRepMax,
  SetEntry? bestSet,
});

/// Personal records, derived from session history every time so that
/// editing or deleting a session corrects them.
///
/// Loaded exercises track three bests, like most lifting apps: the
/// heaviest set, the best estimated 1RM and the best set volume (kg ×
/// reps). Beating any of them is a new record, so adding reps at the same
/// weight counts as progress too. Loads compare with
/// [LoadMath.toleranceKg], so kg/lb round trips never fake a record.
abstract final class PersonalRecords {
  /// Rep-max equations only predict a 1RM reliably from sets of up to ten
  /// reps (LeSuer et al. 1997); longer sets get no estimate.
  static const maxRepsForEstimate = 10;

  /// Epley estimated one-rep max: weight × (1 + reps / 30). A single rep
  /// is already a 1RM, so it is returned as-is; 0 beyond
  /// [maxRepsForEstimate] reps.
  static double estimatedOneRepMax(double weightKg, int reps) {
    if (weightKg <= 0 || reps <= 0 || reps > maxRepsForEstimate) return 0;
    if (reps == 1) return weightKg;
    return weightKg * (1 + reps / 30);
  }

  /// Every record keyed by [PersonalRecord.key]. Sessions are read oldest
  /// first, whatever order they come in, so a value within the tolerance
  /// of an earlier one never replaces it and each record dates from when
  /// it was first reached.
  static Map<String, PersonalRecord> all(Iterable<WorkoutSession> sessions) {
    final ordered = sessions.toList()
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final records = <String, PersonalRecord>{};
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        final performance = _performanceOf(exercise);
        if (performance == null) continue;
        final key = PersonalRecord.recordKey(exercise.name, performance.kind);
        final current = records[key];
        if (current == null) {
          records[key] = PersonalRecord(
            exerciseName: exercise.name,
            kind: performance.kind,
            value: performance.value,
            date: session.completedAt,
            estimatedOneRepMaxKg: performance.oneRepMax,
            bestSet: performance.bestSet,
          );
          continue;
        }
        final better = _greater(
          performance.kind,
          performance.value,
          current.value,
        );
        final set = performance.bestSet;
        final betterSet =
            set != null &&
            LoadMath.moreVolume(
              set.weightKg,
              set.amount,
              current.bestSetVolumeKg,
            );
        records[key] = PersonalRecord(
          exerciseName: exercise.name,
          kind: performance.kind,
          value: better ? performance.value : current.value,
          date: better ? session.completedAt : current.date,
          estimatedOneRepMaxKg:
              performance.oneRepMax > current.estimatedOneRepMaxKg
              ? performance.oneRepMax
              : current.estimatedOneRepMaxKg,
          bestSet: betterSet ? set : current.bestSet,
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
  /// kind in [sessions], each name once. A first-ever performance sets a
  /// baseline rather than a PR, so a debut workout never floods the
  /// celebration toast.
  static List<Exercise> newRecords(
    Iterable<WorkoutSession> sessions,
    Iterable<Exercise> performed,
  ) {
    final previous = all(sessions);
    final names = <String>{};
    return [
      for (final exercise in performed)
        if (_beats(previous, exercise) && names.add(exercise.name)) exercise,
    ];
  }

  static bool _beats(Map<String, PersonalRecord> previous, Exercise exercise) {
    final performance = _performanceOf(exercise);
    if (performance == null) return false;
    final record =
        previous[PersonalRecord.recordKey(exercise.name, performance.kind)];
    if (record == null) return false;
    if (_greater(performance.kind, performance.value, record.value)) {
      return true;
    }
    if (performance.kind != RecordKind.weight) return false;
    final set = performance.bestSet;
    return LoadMath.heavier(
          performance.oneRepMax,
          record.estimatedOneRepMaxKg,
        ) ||
        (set != null &&
            LoadMath.moreVolume(
              set.weightKg,
              set.amount,
              record.bestSetVolumeKg,
            ));
  }

  /// Loads beat a record only past the tolerance; reps and seconds are
  /// whole numbers.
  static bool _greater(RecordKind kind, double value, double record) =>
      kind == RecordKind.weight
      ? LoadMath.heavier(value, record)
      : value > record;

  /// Best single-set values: heaviest kg, best estimate and most volume
  /// for loaded exercises, most reps for bodyweight ones, longest hold
  /// for timed. Falls back to the plan snapshot for sessions recorded
  /// before per-set logging existed. Null when nothing measurable was
  /// done.
  static _Performance? _performanceOf(Exercise exercise) {
    if (exercise.isTimed) {
      var hold = exercise.performedSets.isEmpty ? exercise.durationSeconds : 0;
      for (final set in exercise.performedSets) {
        if (set.amount > hold) hold = set.amount;
      }
      return hold > 0
          ? (
              kind: RecordKind.hold,
              value: hold.toDouble(),
              oneRepMax: 0,
              bestSet: null,
            )
          : null;
    }
    if (exercise.performedSets.isEmpty) {
      if (exercise.weightKg > 0) {
        final planned = SetEntry(
          amount: exercise.reps,
          weightKg: exercise.weightKg,
        );
        return (
          kind: RecordKind.weight,
          value: exercise.weightKg,
          oneRepMax: estimatedOneRepMax(exercise.weightKg, exercise.reps),
          bestSet: exercise.reps > 0 ? planned : null,
        );
      }
      return exercise.reps > 0
          ? (
              kind: RecordKind.reps,
              value: exercise.reps.toDouble(),
              oneRepMax: 0,
              bestSet: null,
            )
          : null;
    }
    final sets = exercise.performedSets;
    var heaviest = 0.0;
    var oneRepMax = 0.0;
    var reps = 0;
    SetEntry? bestSet;
    for (final set in sets) {
      if (set.amount <= 0) continue;
      if (set.weightKg > 0) {
        if (set.weightKg > heaviest) heaviest = set.weightKg;
        final estimate = estimatedOneRepMax(set.weightKg, set.amount);
        if (estimate > oneRepMax) oneRepMax = estimate;
        if (bestSet == null ||
            set.weightKg * set.amount > bestSet.weightKg * bestSet.amount) {
          bestSet = set;
        }
      } else if (set.amount > reps) {
        reps = set.amount;
      }
    }
    // A loaded exercise with a bodyweight drop set is still a lift.
    if (heaviest > 0) {
      return (
        kind: RecordKind.weight,
        value: heaviest,
        oneRepMax: oneRepMax,
        bestSet: bestSet,
      );
    }
    return reps > 0
        ? (
            kind: RecordKind.reps,
            value: reps.toDouble(),
            oneRepMax: 0,
            bestSet: null,
          )
        : null;
  }
}
