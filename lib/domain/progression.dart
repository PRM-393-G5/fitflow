import 'models/exercise.dart';
import 'models/workout_session.dart';
import 'workout_stats.dart';

/// What the user did last time on an exercise, and what to try today.
class ProgressionHint {
  const ProgressionHint({
    required this.lastSets,
    required this.lastDate,
    required this.amount,
    required this.weightKg,
    required this.stepUp,
  });

  /// Sets logged for the exercise in its most recent session.
  final List<SetEntry> lastSets;
  final DateTime lastDate;

  /// Suggested reps (or hold seconds) for today's sets.
  final int amount;

  /// Suggested load in kg; 0 for bodyweight.
  final double weightKg;

  /// True when last time hit every planned set and rep, so the suggestion
  /// is one step harder than last time.
  final bool stepUp;
}

/// Progressive overload: prefill today's sets from the last session of the
/// same exercise, and step up once every planned set was completed.
///
/// - Loaded: every set at the top weight with the planned reps →
///   + one weight step at the planned reps; otherwise repeat the weight.
/// - Bodyweight: the reps reached on every set ≥ the plan → one more rep;
///   otherwise the same reps again (at least the planned reps).
/// - Timed: the same with hold seconds, [holdStepSeconds] at a time; any
///   load is kept.
abstract final class Progression {
  static const repStep = 1;
  static const holdStepSeconds = 5;

  /// Weight steps: 2.5 kg, or 5 lb for imperial users.
  static const metricStepKg = 2.5;
  static const imperialStepKg = 5 * 0.453592;

  /// The hint for performing [planned] today, from the newest session that
  /// logged an exercise of the same name and kind. Camera form checks are
  /// skipped — a single test set says nothing about the planned sets.
  /// Null when there is no history.
  static ProgressionHint? forExercise(
    Iterable<WorkoutSession> sessions,
    Exercise planned, {
    double weightStepKg = metricStepKg,
  }) {
    final last = _lastPerformance(sessions, planned);
    if (last == null) return null;
    final (sets, date) = last;

    final topWeight = sets.fold<double>(
      0,
      (best, set) => set.weightKg > best ? set.weightKg : best,
    );
    final lowestAmount = sets.fold<int>(
      sets.first.amount,
      (low, set) => set.amount < low ? set.amount : low,
    );
    final target = planned.isTimed ? planned.durationSeconds : planned.reps;
    final allSets = sets.length >= planned.sets;
    final hitTarget = allSets && lowestAmount >= target;

    if (planned.isTimed || topWeight <= 0) {
      final step = planned.isTimed ? holdStepSeconds : repStep;
      // Without a step up, repeat what every set reached — but never
      // suggest less than the plan.
      return ProgressionHint(
        lastSets: sets,
        lastDate: date,
        amount: hitTarget
            ? lowestAmount + step
            : (lowestAmount > target ? lowestAmount : target),
        weightKg: topWeight,
        stepUp: hitTarget,
      );
    }
    // A drop set below the top weight means the weight was not held for
    // every set yet.
    final heldWeight = sets.every((set) => set.weightKg >= topWeight);
    final stepUp = hitTarget && heldWeight;
    return ProgressionHint(
      lastSets: sets,
      lastDate: date,
      amount: target,
      weightKg: stepUp ? topWeight + weightStepKg : topWeight,
      stepUp: stepUp,
    );
  }

  static (List<SetEntry>, DateTime)? _lastPerformance(
    Iterable<WorkoutSession> sessions,
    Exercise planned,
  ) {
    final name = _normalize(planned.name);
    final ordered =
        WorkoutStats.counted(sessions)
            .where((item) => item.workoutId != WorkoutStats.formCheckId)
            .toList()
          ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        if (_normalize(exercise.name) != name ||
            exercise.isTimed != planned.isTimed) {
          continue;
        }
        final sets = [
          for (final set in exercise.performedSets)
            if (set.amount > 0) set,
        ];
        if (sets.isNotEmpty) return (sets, session.completedAt);
      }
    }
    return null;
  }

  static String _normalize(String name) => name.trim().toLowerCase();
}
