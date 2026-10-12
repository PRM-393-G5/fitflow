import 'dart:math' as math;

import 'load_math.dart';
import 'models/exercise.dart';
import 'models/workout_session.dart';
import 'workout_stats.dart';

/// Why [Progression] suggests what it does; the workout screen explains
/// each one.
enum ProgressionReason {
  /// Top of the rep range twice in a row (or every rep/hold for
  /// bodyweight and timed work): one step harder.
  stepUp,

  /// Every set reached the target: same load, one more rep towards the
  /// top of the range.
  building,

  /// Missed reps or skipped sets last time: same load and target again.
  repeat,

  /// Missed reps three sessions in a row at the same load: 10% lighter.
  deload,

  /// First session after a long break: lighter for a session.
  comeback,

  /// Already at the cap for reps, hold time or the form's max load.
  capped,

  /// Mobility and cardio work is repeated as last time, not loaded up.
  maintain,
}

/// What the user did last time on an exercise, and what to try today.
class ProgressionHint {
  const ProgressionHint({
    required this.lastSets,
    required this.lastDate,
    required this.amount,
    required this.weightKg,
    required this.reason,
    this.weeksAway = 0,
  });

  /// Sets logged for the exercise in its most recent comparable session.
  final List<SetEntry> lastSets;
  final DateTime lastDate;

  /// Suggested reps (or hold seconds) for today's sets.
  final int amount;

  /// Suggested load in kg; 0 for bodyweight.
  final double weightKg;

  final ProgressionReason reason;

  /// Whole weeks since the exercise was last done, for
  /// [ProgressionReason.comeback].
  final int weeksAway;

  /// True when today's suggestion is one step harder than last time.
  bool get stepUp => reason == ProgressionReason.stepUp;
}

/// One session's sets of the exercise.
typedef _Performance = ({
  DateTime date,
  Exercise exercise,
  List<SetEntry> sets,
});

/// How a loaded session went against today's plan.
enum _Outcome { top, success, incomplete, failed }

/// Progressive overload from history alone (nothing extra is stored).
///
/// Loaded exercises use double progression with the 2-for-2 rule (ACSM
/// 2009, NSCA): the plan's reps are the bottom of a range two reps wide.
/// Each session at the same load adds a rep until every working set
/// reaches the top of the range; after two such sessions in a row the
/// load goes up by 2.5% (upper body) or 5% (lower body), rounded to a
/// load the gym has, and reps go back to the plan.
///
/// - Missed reps repeat the load; three misses in a row at the same load
///   cut it by 10% (StrongLifts). Skipped sets repeat without counting as
///   a miss.
/// - After more than four weeks away the load starts 10% lighter (20%
///   after twelve) — a coaching convention: strength holds for about
///   that long (Mujika & Padilla; Bosquet et al. 2013). It never stacks
///   with a deload.
/// - Bodyweight work adds a rep per session up to [bodyweightRepCap];
///   timed holds add [holdStepSeconds] up to [holdCapSeconds]. Past the
///   cap the user is pointed to a harder variation.
/// - Mobility and cardio plans repeat last time's work.
///
/// The working load of a session is the most common logged load (ties go
/// to the heavier), so warm-up sets and drop sets don't count as the
/// load that was trained.
abstract final class Progression {
  /// Reps above the plan's target that mark the top of the range.
  static const repRange = 2;
  static const holdStepSeconds = 5;
  static const holdCapSeconds = 60;
  static const bodyweightRepCap = 20;

  /// A gap longer than this between sessions ends a run, and a gap this
  /// long before today means coming back from a break.
  static const breakDays = 28;
  static const longBreakDays = 84;

  /// Muscle groups whose lifts move enough load for 5% steps.
  static const lowerBody = {'Legs', 'Glutes', 'Calves', 'Hips', 'Full body'};

  /// Plan categories that are not progressively loaded.
  static const maintainCategories = {'Mobility', 'Cardio'};

  /// The hint for performing [planned] today, from the newest session that
  /// logged an exercise of the same name and kind — preferring sessions
  /// that planned the same reps (or hold), so alternating heavy and light
  /// plans don't mix. Camera form checks are skipped: a single test set
  /// says nothing about the planned sets. Suggestions are capped at
  /// [maxAmount] reps/seconds and [maxWeightKg], the limits of the set
  /// form. Null when there is no history.
  static ProgressionHint? forExercise(
    Iterable<WorkoutSession> sessions,
    Exercise planned, {
    String? category,
    bool metric = true,
    DateTime? now,
    int maxAmount = 1 << 30,
    double maxWeightKg = double.infinity,
  }) {
    final history = _history(sessions, planned);
    if (history.isEmpty) return null;
    final target = _target(planned);
    final sameTarget = [
      for (final item in history)
        if (_target(item.exercise) == target) item,
    ];
    final pool = sameTarget.isNotEmpty ? sameTarget : history;
    final last = pool.first;
    final sets = last.sets;
    final lowest = sets.map((set) => set.amount).reduce(math.min);
    final daysAway = (now ?? DateTime.now())
        .difference(history.first.date)
        .inDays;

    ProgressionHint hint(
      ProgressionReason reason, {
      required int amount,
      required double weightKg,
    }) => ProgressionHint(
      lastSets: sets,
      lastDate: last.date,
      amount: math.min(amount, maxAmount),
      weightKg: math.min(weightKg, maxWeightKg),
      reason: reason,
      weeksAway: daysAway ~/ 7,
    );

    final topWeight = sets.map((set) => set.weightKg).reduce(math.max);
    final load = topWeight > 0 ? topWeight : planned.weightKg;
    // Without a step up, repeat what every set reached — but never
    // suggest less than the plan.
    final repeatAmount = math.max(lowest, target);

    if (maintainCategories.contains(category)) {
      return hint(
        ProgressionReason.maintain,
        amount: repeatAmount,
        weightKg: load,
      );
    }

    if (planned.isTimed || load <= 0) {
      // A lighter set blocks the step up, as for lifts.
      final heldWeight = sets.every(
        (set) => !LoadMath.heavier(topWeight, set.weightKg),
      );
      final hit = sets.length >= planned.sets && lowest >= target && heldWeight;
      if (!hit) {
        return hint(
          ProgressionReason.repeat,
          amount: repeatAmount,
          weightKg: load,
        );
      }
      final (step, cap) = planned.isTimed
          ? (holdStepSeconds, math.max(target, holdCapSeconds))
          : (1, math.max(target, bodyweightRepCap));
      final raised = math.min(math.min(lowest + step, cap), maxAmount);
      return raised > lowest
          ? hint(ProgressionReason.stepUp, amount: raised, weightKg: load)
          : hint(ProgressionReason.capped, amount: lowest, weightKg: load);
    }

    final working = _workingWeight(sets);
    if (working <= 0) {
      // Sets logged without weight on a loaded plan read as a blank
      // field, not a switch to bodyweight: suggest the plan load again.
      return hint(
        ProgressionReason.repeat,
        amount: target,
        weightKg: planned.weightKg,
      );
    }

    // Consecutive sessions, newest first, at this load on this plan with
    // no break in between.
    var topRun = 0;
    var failRun = 0;
    var countingTop = true;
    var countingFail = true;
    DateTime? newer;
    for (final item in pool) {
      if (!LoadMath.same(_workingWeight(item.sets), working) ||
          _target(item.exercise) != target ||
          item.exercise.sets != planned.sets ||
          (newer != null && newer.difference(item.date).inDays > breakDays)) {
        break;
      }
      final outcome = _outcome(item.sets, working, target, planned.sets);
      countingTop = countingTop && outcome == _Outcome.top;
      countingFail = countingFail && outcome == _Outcome.failed;
      if (countingTop) topRun++;
      if (countingFail) failRun++;
      if (!countingTop && !countingFail) break;
      newer = item.date;
    }

    final comebackCut = daysAway > longBreakDays
        ? 0.2
        : daysAway > breakDays
        ? 0.1
        : 0.0;
    final deloadCut = failRun >= 3 ? 0.1 : 0.0;
    if (comebackCut > 0 || deloadCut > 0) {
      final comeback = comebackCut >= deloadCut;
      final reduced = LoadMath.reduce(
        working,
        comeback ? comebackCut : deloadCut,
        metric: metric,
      );
      return hint(
        reduced == null
            ? ProgressionReason.repeat
            : comeback
            ? ProgressionReason.comeback
            : ProgressionReason.deload,
        amount: target,
        weightKg: reduced ?? working,
      );
    }

    if (topRun >= 2) {
      final raised = LoadMath.increase(
        working,
        lowerBody.contains(planned.muscleGroup) ? 0.05 : 0.025,
        metric: metric,
      );
      return LoadMath.heavier(math.min(raised, maxWeightKg), working)
          ? hint(ProgressionReason.stepUp, amount: target, weightKg: raised)
          : hint(ProgressionReason.capped, amount: target, weightKg: working);
    }

    final outcome = _outcome(sets, working, target, planned.sets);
    if (outcome == _Outcome.top || outcome == _Outcome.success) {
      final workingLowest = sets
          .where((set) => LoadMath.same(set.weightKg, working))
          .map((set) => set.amount)
          .reduce(math.min);
      return hint(
        ProgressionReason.building,
        amount: (workingLowest + 1).clamp(target, target + repRange),
        weightKg: working,
      );
    }
    return hint(ProgressionReason.repeat, amount: target, weightKg: working);
  }

  /// Sessions that did the exercise, newest first; when it was done twice
  /// in one session, the entry with more sets.
  static List<_Performance> _history(
    Iterable<WorkoutSession> sessions,
    Exercise planned,
  ) {
    final name = _normalize(planned.name);
    final ordered = WorkoutStats.training(sessions).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return [
      for (final session in ordered)
        ?_bestEntry(session, name, planned.isTimed),
    ];
  }

  static _Performance? _bestEntry(
    WorkoutSession session,
    String name,
    bool timed,
  ) {
    _Performance? best;
    for (final exercise in session.exercises) {
      if (_normalize(exercise.name) != name || exercise.isTimed != timed) {
        continue;
      }
      final sets = [
        for (final set in exercise.performedSets)
          if (set.amount > 0) set,
      ];
      if (sets.isNotEmpty && (best == null || sets.length > best.sets.length)) {
        best = (date: session.completedAt, exercise: exercise, sets: sets);
      }
    }
    return best;
  }

  /// The most common load among loaded sets (within the tolerance); ties
  /// go to the heavier. 0 when no set has a load.
  static double _workingWeight(List<SetEntry> sets) {
    var best = 0.0;
    var bestCount = 0;
    for (final candidate in sets) {
      if (candidate.weightKg <= 0) continue;
      final count = sets
          .where((set) => LoadMath.same(set.weightKg, candidate.weightKg))
          .length;
      if (count > bestCount ||
          (count == bestCount && candidate.weightKg > best)) {
        best = candidate.weightKg;
        bestCount = count;
      }
    }
    return best;
  }

  /// A miss on any working set is a failure; fewer working sets than
  /// planned is only incomplete.
  static _Outcome _outcome(
    List<SetEntry> sets,
    double working,
    int target,
    int plannedSets,
  ) {
    final reps = [
      for (final set in sets)
        if (LoadMath.same(set.weightKg, working)) set.amount,
    ];
    if (reps.any((amount) => amount < target)) return _Outcome.failed;
    if (reps.length < plannedSets) return _Outcome.incomplete;
    return reps.every((amount) => amount >= target + repRange)
        ? _Outcome.top
        : _Outcome.success;
  }

  static int _target(Exercise exercise) =>
      exercise.isTimed ? exercise.durationSeconds : exercise.reps;

  static String _normalize(String name) => name.trim().toLowerCase();
}
