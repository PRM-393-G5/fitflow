import 'models/exercise.dart';
import 'models/workout_session.dart';
import 'workout_stats.dart';

/// A muscle drawn on the muscle map.
enum Muscle {
  chest('Chest'),
  deltoids('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Forearms'),
  trapezius('Traps'),
  upperBack('Lats & upper back'),
  lowerBack('Lower back'),
  abs('Abs'),
  obliques('Obliques'),
  glutes('Glutes'),
  quadriceps('Quads'),
  hamstrings('Hamstrings'),
  adductors('Adductors'),
  calves('Calves');

  const Muscle(this.label);

  final String label;
}

/// Sets an exercise gives each muscle: 1 for a muscle it mainly trains,
/// 0.5 for one that only assists.
typedef MuscleWeights = Map<Muscle, double>;

const _primary = 1.0;
const _secondary = 0.5;

/// A name rule: a word in the exercise name starts with one of the
/// keywords ("row" matches "rows", not "narrow").
typedef _Rule = ({RegExp pattern, MuscleWeights weights});

_Rule _rule(List<String> keywords, MuscleWeights weights) => (
  pattern: RegExp('(^|[^a-z])(${keywords.map(RegExp.escape).join('|')})'),
  weights: weights,
);

/// Checked in order, first match wins, so specific names ("leg curl")
/// come before the generic ones they contain ("curl").
final _rules = [
  // Mobility work stretches rather than trains.
  _rule([
    'stretch',
    'rotation',
    'mobility',
    'cat-cow',
    'cat cow',
    "child's pose",
    'foam roll',
    // Cardio machines, not a back row.
    'rowing machine',
    'rower',
  ], const {}),
  _rule(
    ['romanian', 'rdl', 'stiff-leg', 'stiff leg', 'good morning'],
    {
      Muscle.hamstrings: _primary,
      Muscle.glutes: _primary,
      Muscle.lowerBack: _secondary,
    },
  ),
  _rule(
    ['deadlift'],
    {
      Muscle.hamstrings: _primary,
      Muscle.glutes: _primary,
      Muscle.lowerBack: _primary,
      Muscle.quadriceps: _secondary,
      Muscle.trapezius: _secondary,
      Muscle.forearms: _secondary,
    },
  ),
  _rule(
    ['leg curl', 'hamstring curl', 'nordic'],
    {Muscle.hamstrings: _primary},
  ),
  _rule(['leg extension'], {Muscle.quadriceps: _primary}),
  _rule(
    ['back extension', 'hyperextension', 'superman'],
    {
      Muscle.lowerBack: _primary,
      Muscle.glutes: _secondary,
      Muscle.hamstrings: _secondary,
    },
  ),
  _rule(
    [
      'hip thrust',
      'hip extension',
      'glute bridge',
      'bridge',
      'glute',
      'abduct',
    ],
    {Muscle.glutes: _primary, Muscle.hamstrings: _secondary},
  ),
  _rule(['adduct'], {Muscle.adductors: _primary}),
  _rule(['calf', 'calves'], {Muscle.calves: _primary}),
  _rule(
    ['squat', 'leg press', 'lunge', 'step-up', 'step up', 'hack'],
    {
      Muscle.quadriceps: _primary,
      Muscle.glutes: _primary,
      Muscle.adductors: _secondary,
      Muscle.hamstrings: _secondary,
    },
  ),
  _rule(
    ['upright row'],
    {Muscle.deltoids: _primary, Muscle.trapezius: _primary},
  ),
  _rule(
    ['face pull', 'rear delt', 'reverse fly'],
    {Muscle.deltoids: _primary, Muscle.upperBack: _secondary},
  ),
  _rule(
    ['lateral raise', 'front raise', 'side raise'],
    {Muscle.deltoids: _primary},
  ),
  _rule(
    ['overhead press', 'shoulder press', 'military', 'arnold', 'ohp'],
    {Muscle.deltoids: _primary, Muscle.triceps: _secondary},
  ),
  _rule(['shrug'], {Muscle.trapezius: _primary}),
  _rule(
    ['pulldown', 'pull-down', 'pull-up', 'pullup', 'pull up', 'chin'],
    {Muscle.upperBack: _primary, Muscle.biceps: _secondary},
  ),
  _rule(
    ['row'],
    {
      Muscle.upperBack: _primary,
      Muscle.trapezius: _secondary,
      Muscle.biceps: _secondary,
    },
  ),
  _rule(
    ['dip'],
    {
      Muscle.triceps: _primary,
      Muscle.chest: _secondary,
      Muscle.deltoids: _secondary,
    },
  ),
  _rule(
    [
      'bench',
      'push-up',
      'pushup',
      'push up',
      'chest press',
      'incline',
      'decline',
      'dumbbell press',
      'fly',
      'flye',
      'butterfly',
      'pec deck',
    ],
    {
      Muscle.chest: _primary,
      Muscle.triceps: _secondary,
      Muscle.deltoids: _secondary,
    },
  ),
  _rule(
    ['pushdown', 'push-down', 'tricep', 'skull', 'kickback', 'extension'],
    {Muscle.triceps: _primary},
  ),
  _rule(['wrist', 'farmer', 'forearm'], {Muscle.forearms: _primary}),
  _rule(['hammer'], {Muscle.biceps: _primary, Muscle.forearms: _primary}),
  _rule(['curl'], {Muscle.biceps: _primary, Muscle.forearms: _secondary}),
  _rule(
    ['oblique', 'side plank', 'russian twist', 'woodchop', 'pallof'],
    {Muscle.obliques: _primary, Muscle.abs: _secondary},
  ),
  _rule(
    [
      'plank',
      'crunch',
      'sit-up',
      'situp',
      'leg raise',
      'hollow',
      'dead bug',
      'mountain climber',
      'ab wheel',
      'rollout',
    ],
    {Muscle.abs: _primary, Muscle.obliques: _secondary},
  ),
];

/// When the name says nothing, the exercise's tagged muscle group.
const _groups = <String, MuscleWeights>{
  'chest': {
    Muscle.chest: _primary,
    Muscle.triceps: _secondary,
    Muscle.deltoids: _secondary,
  },
  'back': {Muscle.upperBack: _primary, Muscle.biceps: _secondary},
  'shoulders': {Muscle.deltoids: _primary},
  'arms': {Muscle.biceps: _secondary, Muscle.triceps: _secondary},
  'core': {Muscle.abs: _primary, Muscle.obliques: _secondary},
  'glutes': {Muscle.glutes: _primary, Muscle.hamstrings: _secondary},
  'legs': {
    Muscle.quadriceps: _primary,
    Muscle.glutes: _secondary,
    Muscle.hamstrings: _secondary,
  },
  'calves': {Muscle.calves: _primary},
};

/// One exercise's share of a muscle's weekly sets.
typedef MuscleContribution = ({String exercise, double sets, bool primary});

/// A muscle's sets this week and last, and which exercises gave them.
class MuscleWeek {
  const MuscleWeek({
    required this.sets,
    required this.previous,
    required this.exercises,
  });

  final double sets;
  final double previous;

  /// Most sets first.
  final List<MuscleContribution> exercises;

  double get change => sets - previous;
  VolumeLevel get level => MuscleVolume.level(sets);

  /// Sets still needed to reach [MuscleVolume.targetMin]; 0 once there.
  double get missing =>
      sets >= MuscleVolume.targetMin ? 0 : MuscleVolume.targetMin - sets;
}

/// How a muscle's weekly sets compare to the usual hypertrophy range.
enum VolumeLevel { none, low, optimal, high }

abstract final class MuscleVolume {
  /// Weekly hard sets per muscle commonly recommended for growth.
  static const targetMin = 10;
  static const targetMax = 20;

  /// The muscles [exercise] trains, from its name, else from its muscle
  /// group. Empty for full body, cardio and mobility work.
  static MuscleWeights weightsOf(Exercise exercise) {
    final name = exercise.name.toLowerCase();
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(name)) return rule.weights;
    }
    return _groups[exercise.muscleGroup.trim().toLowerCase()] ?? const {};
  }

  /// Every muscle's sets in the current Monday-based week and the one
  /// before. Camera form-check sessions are excluded like in every other
  /// stat.
  static Map<Muscle, MuscleWeek> weekly(
    Iterable<WorkoutSession> sessions, {
    required DateTime now,
  }) {
    final lastWeek = DateTime(
      now.year,
      now.month,
      now.day - 7,
      now.hour,
      now.minute,
    );
    final current = _contributions(WorkoutStats.thisWeek(sessions, now: now));
    final previous = _contributions(
      WorkoutStats.thisWeek(sessions, now: lastWeek),
    );
    return {
      for (final muscle in Muscle.values)
        muscle: MuscleWeek(
          sets: _total(current[muscle]),
          previous: _total(previous[muscle]),
          exercises: [...?current[muscle]]
            ..sort((a, b) => b.sets.compareTo(a.sets)),
        ),
    };
  }

  static Map<Muscle, List<MuscleContribution>> _contributions(
    Iterable<WorkoutSession> sessions,
  ) {
    // Keyed by exercise name, so the same lift on two days is one row.
    final byMuscle = <Muscle, Map<String, MuscleContribution>>{};
    for (final session in sessions) {
      // Sessions from before per-set logging only kept the plan; in newer
      // ones an exercise without logged sets was not done.
      final legacy = session.exercises.every(
        (exercise) => exercise.performedSets.isEmpty,
      );
      for (final exercise in session.exercises) {
        final sets = legacy ? exercise.sets : exercise.performedSets.length;
        if (sets == 0) continue;
        for (final MapEntry(key: muscle, value: weight) in weightsOf(
          exercise,
        ).entries) {
          final rows = byMuscle[muscle] ??= {};
          final row = rows[exercise.name];
          rows[exercise.name] = (
            exercise: exercise.name,
            sets: (row?.sets ?? 0) + sets * weight,
            primary: weight >= _primary,
          );
        }
      }
    }
    return {
      for (final MapEntry(:key, :value) in byMuscle.entries)
        key: value.values.toList(),
    };
  }

  static double _total(List<MuscleContribution>? rows) =>
      rows?.fold<double>(0, (sum, row) => sum + row.sets) ?? 0;

  static VolumeLevel level(double sets) => sets <= 0
      ? VolumeLevel.none
      : sets < targetMin
      ? VolumeLevel.low
      : sets <= targetMax
      ? VolumeLevel.optimal
      : VolumeLevel.high;

  /// "1 set", "7.5 sets".
  static String sets(double sets) =>
      '${format(sets)} ${sets == 1 ? 'set' : 'sets'}';

  /// "12", "7.5": sets are counted in halves.
  static String format(double sets) => sets == sets.roundToDouble()
      ? '${sets.round()}'
      : sets.toStringAsFixed(1);
}
