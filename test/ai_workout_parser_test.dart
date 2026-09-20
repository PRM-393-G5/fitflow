import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/domain/ai_workout_parser.dart';
import 'package:prm/features/workouts/presentation/ai_workout_page.dart';

Map<String, dynamic> plan({List<Map<String, dynamic>>? exercises}) => {
  'name': 'Lower Body Blast',
  'description': 'A leg day.',
  'level': 'Beginner',
  'category': 'Strength',
  'durationMinutes': 30,
  'exercises': exercises ?? [exercise()],
};

Map<String, dynamic> exercise({
  String muscleGroup = 'Legs',
  int sets = 3,
  int reps = 12,
  int durationSeconds = 0,
  int restSeconds = 45,
  double weightKg = 0,
}) => {
  'name': 'Bodyweight Squat',
  'muscleGroup': muscleGroup,
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
    // 3 × (12 reps × 3 s + 45 s rest) = 243 s → 5 min, not the claimed 30.
    expect(workout.duration.inMinutes, 5);
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

  test('non-list exercises throws FormatException, not TypeError', () {
    for (final bad in <Object>[
      'squats',
      42,
      {'name': 'x'},
    ]) {
      expect(
        () => AiWorkoutParser.parse(plan()..['exercises'] = bad),
        throwsFormatException,
      );
    }
  });

  test('muscleGroup is whitelisted, case-insensitively', () {
    final workout = AiWorkoutParser.parse(
      plan(
        exercises: [
          exercise(muscleGroup: 'Full Body'),
          exercise(muscleGroup: 'core'),
          exercise(muscleGroup: 'Glutes & hamstrings'),
          exercise(muscleGroup: ''),
        ],
      ),
    );

    expect(workout.exercises.map((item) => item.muscleGroup), [
      'Full body',
      'Core',
      'Full body',
      'Full body',
    ]);
    for (final item in workout.exercises) {
      expect(workoutMuscleGroups, contains(item.muscleGroup));
    }
  });

  test('caps the number of exercises', () {
    final workout = AiWorkoutParser.parse(
      plan(exercises: List.generate(30, (_) => exercise())),
    );

    expect(workout.exercises, hasLength(AiWorkoutPrompt.maxExercises));
  });

  test('duration is estimated from the plan, ignoring the claim', () {
    final workout = AiWorkoutParser.parse(
      plan(
        exercises: [
          exercise(sets: 4, reps: 10, restSeconds: 60),
          exercise(sets: 3, reps: 0, durationSeconds: 45, restSeconds: 30),
        ],
      )..['durationMinutes'] = 90,
    );

    // 4 × (30 + 60) + 3 × (45 + 30) = 585 s → 10 min.
    expect(workout.duration, estimateWorkoutDuration(workout.exercises));
    expect(workout.duration.inMinutes, 10);
  });

  test('rep-less non-timed exercise defaults to 10 reps', () {
    final workout = AiWorkoutParser.parse(plan(exercises: [exercise(reps: 0)]));

    expect(workout.exercises.single.reps, 10);
  });

  test('non-string fields fall back instead of crashing', () {
    final workout = AiWorkoutParser.parse(
      plan()
        ..['name'] = 42
        ..['description'] = null,
    );

    expect(workout.name, 'AI Workout');
    expect(workout.description, '');
  });

  test('timed exercise keeps zero reps', () {
    final workout = AiWorkoutParser.parse(
      plan(exercises: [exercise(reps: 0, durationSeconds: 30)]),
    );
    final parsed = workout.exercises.single;

    expect(parsed.isTimed, isTrue);
    expect(parsed.prescription, '3 × 30s');
  });

  testWidgets('shows config hint and hides generate without API key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: FToaster(child: child!),
        ),
        home: const AiWorkoutPage(),
      ),
    );

    expect(find.byKey(const Key('ai-generate')), findsNothing);
    expect(find.textContaining('OPENAI_API_KEY'), findsOneWidget);
  });
}
