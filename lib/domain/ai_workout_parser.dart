import 'package:clock/clock.dart';

import 'models/exercise.dart';
import 'models/workout.dart';

/// Muscle-group vocabulary shared by the builder picker and the AI parser.
const workoutMuscleGroups = [
  'Legs',
  'Chest',
  'Back',
  'Shoulders',
  'Arms',
  'Core',
  'Full body',
  'Cardio',
];

/// Rough session length from the plan itself: each set is its hold time
/// (or ~3 s per rep, at least 20 s) plus the rest after it. Used instead of
/// any duration a user or model claims.
Duration estimateWorkoutDuration(Iterable<Exercise> exercises) {
  final seconds = exercises.fold<int>(0, (sum, item) {
    final work = item.isTimed
        ? item.durationSeconds
        : (item.reps * 3).clamp(20, 600);
    return sum + item.sets * (work + item.restSeconds);
  });
  return Duration(minutes: (seconds / 60).ceil().clamp(1, 600));
}

/// Prompt contract + parser for AI-generated workout plans.
abstract final class AiWorkoutPrompt {
  /// Hard cap on parsed exercises, whatever the model returns.
  static const maxExercises = 12;

  static final system =
      '''
You are a fitness coach generating workout plans as JSON. Rules:
- 4-10 exercises ordered compound -> isolation -> core/stretch last.
- Timed holds use durationSeconds>0 and reps=0; rep exercises use
  reps>0 and durationSeconds=0.
- restSeconds 30-90 for strength work, 15-45 for cardio/mobility.
- weightKg is 0 for bodyweight exercises.
- Use common, recognizable exercise names in English.
- muscleGroup is one of: ${workoutMuscleGroups.join(', ')}.
- level and category must come from the enums in the schema.''';

  /// OpenAI structured-output schema (strict mode requires every property
  /// in `required` and `additionalProperties: false`).
  static const schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'description': {'type': 'string'},
      'level': {
        'type': 'string',
        'enum': ['Beginner', 'Intermediate', 'Advanced'],
      },
      'category': {
        'type': 'string',
        'enum': ['Strength', 'Cardio', 'Mobility'],
      },
      'durationMinutes': {'type': 'integer'},
      'exercises': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'muscleGroup': {'type': 'string', 'enum': workoutMuscleGroups},
            'sets': {'type': 'integer'},
            'reps': {'type': 'integer'},
            'durationSeconds': {'type': 'integer'},
            'restSeconds': {'type': 'integer'},
            'weightKg': {'type': 'number'},
          },
          'required': [
            'name',
            'muscleGroup',
            'sets',
            'reps',
            'durationSeconds',
            'restSeconds',
            'weightKg',
          ],
          'additionalProperties': false,
        },
      },
    },
    'required': [
      'name',
      'description',
      'level',
      'category',
      'durationMinutes',
      'exercises',
    ],
    'additionalProperties': false,
  };

  static String user({
    required String request,
    String? level,
    int? durationMinutes,
    String? goal,
  }) {
    final buffer = StringBuffer('Create a workout plan.\nRequest: "$request"');
    if (level != null) buffer.write('\nLevel: $level');
    if (durationMinutes != null) {
      buffer.write('\nTarget duration: $durationMinutes minutes');
    }
    if (goal != null) buffer.write('\nUser goal: $goal');
    return buffer.toString();
  }
}

/// Sanitizes AI plan JSON into a [Workout] — the model's numbers are
/// clamped and vocab is whitelisted, so nothing it emits is trusted raw.
/// Throws [FormatException] when the plan has no usable exercises.
abstract final class AiWorkoutParser {
  static const _levels = {'Beginner', 'Intermediate', 'Advanced'};
  static const _categories = {'Strength', 'Cardio', 'Mobility'};

  static Workout parse(Map<String, dynamic> json) {
    final rawExercises = json['exercises'] ?? const [];
    if (rawExercises is! List) {
      throw const FormatException('AI plan exercises is not a list');
    }
    final exercises = [
      for (final (index, item) in rawExercises.indexed)
        if (item is Map<String, dynamic>) _exercise(item, index),
    ].take(AiWorkoutPrompt.maxExercises).toList();
    if (exercises.isEmpty) {
      throw const FormatException('AI plan has no exercises');
    }
    final level = _text(json['level'], '');
    final category = _text(json['category'], '');
    return Workout(
      id: 'custom-ai-${clock.now().microsecondsSinceEpoch}',
      name: _text(json['name'], 'AI Workout'),
      // The model's claimed minutes are ignored — estimate from the plan.
      duration: estimateWorkoutDuration(exercises),
      level: _levels.contains(level) ? level : 'Beginner',
      category: _categories.contains(category) ? category : 'Strength',
      description: _text(json['description'], ''),
      exercises: exercises,
    );
  }

  static Exercise _exercise(Map<String, dynamic> json, int index) {
    var reps = _clampInt(json['reps'], 0, 100, 0);
    final durationSeconds = _clampInt(json['durationSeconds'], 0, 600, 0);
    if (reps == 0 && durationSeconds == 0) reps = 10;
    return Exercise(
      id: 'ai-ex-$index',
      name: _text(json['name'], 'Exercise ${index + 1}'),
      muscleGroup: _muscleGroup(json['muscleGroup']),
      sets: _clampInt(json['sets'], 1, 10, 3),
      reps: reps,
      durationSeconds: durationSeconds,
      restSeconds: _clampInt(json['restSeconds'], 15, 300, 45),
      weightKg: _clampDouble(json['weightKg'], 0, 500, 0),
    );
  }

  static String _muscleGroup(Object? value) {
    final text = _text(value, '').toLowerCase();
    for (final group in workoutMuscleGroups) {
      if (group.toLowerCase() == text) return group;
    }
    return 'Full body';
  }

  static String _text(Object? value, String fallback) {
    if (value is! String) return fallback;
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  static int _clampInt(Object? value, int min, int max, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }

  static double _clampDouble(
    Object? value,
    double min,
    double max,
    double fallback,
  ) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(min, max);
  }
}
