import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/ai_workout_parser.dart';

Map<String, dynamic> plan({List<Map<String, dynamic>>? exercises}) => {
  'name': 'Lower Body Blast',
  'description': 'A leg day.',
  'level': 'Beginner',
  'category': 'Strength',
  'durationMinutes': 30,
  'exercises': exercises ?? [exercise()],
};

Map<String, dynamic> exercise({
  int sets = 3,
  int reps = 12,
  int durationSeconds = 0,
  int restSeconds = 45,
  double weightKg = 0,
}) => {
  'name': 'Bodyweight Squat',
  'muscleGroup': 'Legs',
  'sets': sets,
  'reps': reps,
  'durationSeconds': durationSeconds,
  'restSeconds': restSeconds,
  'weightKg': weightKg,
};

void main() {
  test('parses a valid plan into a Workout', () {
    final workout = AiWorkoutParser.parse(plan());

    expect(workout.name, 'Lower Body Blast');
    expect(workout.level, 'Beginner');
    expect(workout.category, 'Strength');
    expect(workout.duration.inMinutes, 30);
    expect(workout.exercises.single.name, 'Bodyweight Squat');
    expect(workout.exercises.single.sets, 3);
    expect(workout.id, startsWith('custom-ai-'));
  });

  test('clamps out-of-range numbers', () {
    final workout = AiWorkoutParser.parse(
      plan(
        exercises: [
          exercise(sets: 99, reps: 500, restSeconds: 0, weightKg: -5),
        ],
      ),
    );
    final parsed = workout.exercises.single;

    expect(parsed.sets, 10);
    expect(parsed.reps, 100);
    expect(parsed.restSeconds, 15);
    expect(parsed.weightKg, 0);
  });

  test('unknown level/category falls back to defaults', () {
    final workout = AiWorkoutParser.parse(
      plan()
        ..['level'] = 'Extreme'
        ..['category'] = 'Yoga',
    );

    expect(workout.level, 'Beginner');
    expect(workout.category, 'Strength');
  });

  test('empty exercise list throws', () {
    expect(
      () => AiWorkoutParser.parse(plan(exercises: [])),
      throwsFormatException,
    );
  });

  test('rep-less non-timed exercise defaults to 10 reps', () {
    final workout = AiWorkoutParser.parse(plan(exercises: [exercise(reps: 0)]));

    expect(workout.exercises.single.reps, 10);
  });

  test('timed exercise keeps zero reps', () {
    final workout = AiWorkoutParser.parse(
      plan(exercises: [exercise(reps: 0, durationSeconds: 30)]),
    );
    final parsed = workout.exercises.single;

    expect(parsed.isTimed, isTrue);
    expect(parsed.prescription, '3 × 30s');
  });
}
