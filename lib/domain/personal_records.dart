import 'dart:math' as math;

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
    DateTime? lastImprovedAt,
  }) : lastImprovedAt = lastImprovedAt ?? date;

  final String exerciseName;
  final RecordKind kind;

  /// kg for [RecordKind.weight], seconds for [RecordKind.hold], reps for
  /// [RecordKind.reps].
  final double value;

  /// When [value] was first reached.
  final DateTime date;

  /// Best Epley estimate over all logged sets; weight records only.
  final double estimatedOneRepMaxKg;

  /// The set behind [estimatedOneRepMaxKg]; weight records only.
  final SetEntry? bestSet;

  /// The latest session that set any record for this exercise — a
  /// heavier set, a better estimate or more reps at a load — so newly
  /// celebrated records sort first. [date] for holds and bodyweight reps.
  final DateTime lastImprovedAt;

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

  /// Loaded sets with reps, for rep records at a load.
  List<SetEntry> loadedSets,
});

/// Personal records, derived from session history every time so that
/// editing or deleting a session corrects them.
///
/// A loaded exercise sets a record with a heavier set, a better estimated
/// 1RM, or more reps than ever at a load it has been lifted at before (or
/// any heavier one). The last one makes double progression — adding reps
/// before adding weight — count as progress, while a first warm-up at a
/// new, lighter load is only a baseline. Loads compare with
/// [LoadMath.toleranceKg], so kg/lb round trips never fake a record.
abstract final class PersonalRecords {
  /// Rep-max equations predict a 1RM reliably only from sets of up to ten
  /// reps (LeSuer et al. 1997); longer sets count as ten, a conservative
  /// lower bound — 20 kg × 50 reads as 26.7 kg, not a 53 kg single.
  static const maxRepsForEstimate = 10;

  /// Epley estimated one-rep max: weight × (1 + reps / 30), with reps
  /// capped at [maxRepsForEstimate]. A single rep is already a 1RM, so it
  /// is returned as-is. Never below [weightKg] for a completed set.
  static double estimatedOneRepMax(double weightKg, int reps) {
    if (weightKg <= 0 || reps <= 0) return 0;
    if (reps == 1) return weightKg;
    return weightKg * (1 + math.min(reps, maxRepsForEstimate) / 30);
  }

  /// Every record keyed by [PersonalRecord.key]. Sessions are read oldest
  /// first (ties by id), whatever order they come in, so a value within
  /// the tolerance of an earlier one never replaces it and each record
  /// dates from when it was first reached.
  static Map<String, PersonalRecord> all(Iterable<WorkoutSession> sessions) => {
    for (final entry in _bests(sessions).entries)
      entry.key: entry.value.toRecord(),
  };

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

  /// Heaviest load ever logged for an exercise — name matched ignoring
  /// case and spaces, timed and rep work kept apart — counting sets with
  /// reps (or seconds) and the plan load of sessions from before per-set
  /// logging. [exceptSessionId] leaves one session out. 0 without any.
  static double heaviestLoad(
    Iterable<WorkoutSession> sessions,
    String name, {
    required bool timed,
    String? exceptSessionId,
  }) {
    final wanted = name.trim().toLowerCase();
    var heaviest = 0.0;
    for (final session in sessions) {
      if (session.id == exceptSessionId) continue;
      for (final exercise in session.exercises) {
        if (exercise.isTimed != timed ||
            exercise.name.trim().toLowerCase() != wanted) {
          continue;
        }
        if (exercise.performedSets.isEmpty) {
          heaviest = math.max(heaviest, exercise.weightKg);
        }
        for (final set in exercise.performedSets) {
          if (set.amount > 0) heaviest = math.max(heaviest, set.weightKg);
        }
      }
    }
    return heaviest;
  }

  /// Exercises in [performed] that beat a previous record of the same
  /// kind in [sessions], each name once — by the same rules that build
  /// the records. A first-ever performance sets a baseline rather than a
  /// PR, so a debut workout never floods the celebration toast.
  static List<Exercise> newRecords(
    Iterable<WorkoutSession> sessions,
    Iterable<Exercise> performed,
  ) {
    final previous = _bests(sessions);
    final names = <String>{};
    return [
      for (final exercise in performed)
        if (_performanceOf(exercise) case final performance?)
          if (previous[PersonalRecord.recordKey(
                    exercise.name,
                    performance.kind,
                  )]
                  ?.improvedBy(performance) ??
              false)
            if (names.add(exercise.name)) exercise,
    ];
  }

  static Map<String, _Best> _bests(Iterable<WorkoutSession> sessions) {
    final ordered = sessions.toList()
      ..sort((a, b) {
        final byTime = a.completedAt.compareTo(b.completedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final bests = <String, _Best>{};
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        final performance = _performanceOf(exercise);
        if (performance == null) continue;
        final key = PersonalRecord.recordKey(exercise.name, performance.kind);
        final best = bests[key];
        if (best == null) {
          bests[key] = _Best(exercise.name, performance, session.completedAt);
        } else {
          best.absorb(performance, session.completedAt);
        }
      }
    }
    return bests;
  }

  /// Best single-set values: heaviest kg and best estimate for loaded
  /// exercises, most reps for bodyweight ones, longest hold for timed.
  /// Falls back to the plan snapshot for sessions recorded before
  /// per-set logging existed. Null when nothing measurable was done.
  static _Performance? _performanceOf(Exercise exercise) {
    if (exercise.isTimed) {
      var hold = exercise.performedSets.isEmpty ? exercise.durationSeconds : 0;
      for (final set in exercise.performedSets) {
        if (set.amount > hold) hold = set.amount;
      }
      return hold > 0 ? _unloaded(RecordKind.hold, hold) : null;
    }
    if (exercise.performedSets.isEmpty) {
      if (exercise.weightKg > 0) {
        // A plan snapshot without reps still proves one rep at its load.
        final planned = SetEntry(
          amount: math.max(exercise.reps, 1),
          weightKg: exercise.weightKg,
        );
        return (
          kind: RecordKind.weight,
          value: exercise.weightKg,
          oneRepMax: estimatedOneRepMax(planned.weightKg, planned.amount),
          bestSet: exercise.reps > 0 ? planned : null,
          loadedSets: exercise.reps > 0 ? [planned] : const [],
        );
      }
      return exercise.reps > 0
          ? _unloaded(RecordKind.reps, exercise.reps)
          : null;
    }
    var heaviest = 0.0;
    var oneRepMax = 0.0;
    var reps = 0;
    SetEntry? bestSet;
    final loaded = <SetEntry>[];
    for (final set in exercise.performedSets) {
      if (set.amount <= 0) continue;
      if (set.weightKg > 0) {
        loaded.add(set);
        if (set.weightKg > heaviest) heaviest = set.weightKg;
        final estimate = estimatedOneRepMax(set.weightKg, set.amount);
        if (estimate > oneRepMax) {
          oneRepMax = estimate;
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
        loadedSets: loaded,
      );
    }
    return reps > 0 ? _unloaded(RecordKind.reps, reps) : null;
  }

  static _Performance _unloaded(RecordKind kind, int value) => (
    kind: kind,
    value: value.toDouble(),
    oneRepMax: 0,
    bestSet: null,
    loadedSets: const [],
  );
}

/// Running bests for one exercise and kind while history is read oldest
/// first. [improvedBy] is the single definition of "a new record", shared
/// by the records and the post-workout toast.
class _Best {
  _Best(this.name, _Performance first, DateTime date)
    : kind = first.kind,
      value = first.value,
      date = date,
      lastImprovedAt = date,
      oneRepMax = first.oneRepMax,
      bestSet = first.bestSet {
    _addReps(first.loadedSets);
  }

  final String name;
  final RecordKind kind;
  double value;
  DateTime date;
  DateTime lastImprovedAt;
  double oneRepMax;
  SetEntry? bestSet;

  /// Most reps per load (0.1 kg buckets, so lb round trips share one).
  final Map<int, int> _repsByLoad = {};

  bool _heavier(_Performance performance) => kind == RecordKind.weight
      ? LoadMath.heavier(performance.value, value)
      : performance.value > value;

  bool _betterEstimate(_Performance performance) =>
      LoadMath.heavier(performance.oneRepMax, oneRepMax);

  /// More reps than ever at this load or any heavier one — counted only
  /// at loads lifted before, so a first set at a new load is a baseline.
  bool _moreReps(SetEntry set) {
    final load = _bucket(set.weightKg);
    if (!_repsByLoad.containsKey(load)) return false;
    var most = 0;
    for (final MapEntry(key: other, value: reps) in _repsByLoad.entries) {
      if (other >= load && reps > most) most = reps;
    }
    return set.amount > most;
  }

  bool improvedBy(_Performance performance) =>
      _heavier(performance) ||
      _betterEstimate(performance) ||
      performance.loadedSets.any(_moreReps);

  void absorb(_Performance performance, DateTime at) {
    if (improvedBy(performance)) lastImprovedAt = at;
    if (_heavier(performance)) {
      value = performance.value;
      date = at;
    }
    if (_betterEstimate(performance)) {
      oneRepMax = performance.oneRepMax;
      bestSet = performance.bestSet;
    }
    _addReps(performance.loadedSets);
  }

  void _addReps(List<SetEntry> sets) {
    for (final set in sets) {
      final load = _bucket(set.weightKg);
      _repsByLoad[load] = math.max(_repsByLoad[load] ?? 0, set.amount);
    }
  }

  static int _bucket(double kg) => (kg * 10).round();

  PersonalRecord toRecord() => PersonalRecord(
    exerciseName: name,
    kind: kind,
    value: value,
    date: date,
    estimatedOneRepMaxKg: oneRepMax,
    bestSet: bestSet,
    lastImprovedAt: lastImprovedAt,
  );
}
