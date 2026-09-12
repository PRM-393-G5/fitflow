import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/personal_records.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise logged(String name, double kg, List<SetEntry> sets) => Exercise(
  id: name,
  name: name,
  muscleGroup: 'x',
  sets: sets.length,
  weightKg: kg,
  performedSets: sets,
);

WorkoutSession session(DateTime day, List<Exercise> exercises) =>
    WorkoutSession(
      id: day.toIso8601String(),
      workoutId: 'workout',
      workoutName: 'Workout',
      startedAt: day,
      completedAt: day,
      completedSets: 3,
      volumeKg: 0,
      exercises: exercises,
    );

void main() {
  test('Exercise JSON round-trips performed sets', () {
    final exercise = logged('Bench Press', 20, [
      const SetEntry(amount: 10, weightKg: 20),
      const SetEntry(amount: 8, weightKg: 22.5),
    ]);

    final decoded = Exercise.fromJson(exercise.toJson());

    expect(decoded.performedSets.map((set) => set.amount), [10, 8]);
    expect(decoded.performedSets.map((set) => set.weightKg), [20, 22.5]);
  });

  test('performedVolumeKg sums actual sets, ignoring bodyweight', () {
    final exercise = logged('Squat', 0, [
      const SetEntry(amount: 10, weightKg: 20),
      const SetEntry(amount: 10, weightKg: 20),
      const SetEntry(amount: 12), // bodyweight drop set
    ]);

    expect(exercise.performedVolumeKg, 400);
  });

  test('personal records use the heaviest logged set, not the plan', () {
    final sessions = [
      session(DateTime(2026, 4, 1), [
        logged('Bench Press', 20, [
          const SetEntry(amount: 10, weightKg: 20),
          const SetEntry(amount: 8, weightKg: 25),
        ]),
      ]),
    ];

    expect(PersonalRecords.best(sessions)['Bench Press']!.value, 25);
  });

  test('timed PRs use longest logged hold', () {
    final plank = Exercise(
      id: 'plank',
      name: 'Plank',
      muscleGroup: 'x',
      sets: 2,
      durationSeconds: 30,
      performedSets: const [SetEntry(amount: 45), SetEntry(amount: 60)],
    );

    expect(
      PersonalRecords.best([
        session(DateTime(2026, 4, 1), [plank]),
      ])['Plank']!.value,
      60,
    );
  });

  testWidgets('active workout logs entered reps and weight per set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences),
      preferences,
    );
    await controller.load();

    const workout = Workout(
      id: 'w1',
      name: 'Legs',
      duration: Duration(minutes: 5),
      level: 'Beginner',
      category: 'Strength',
      description: '',
      exercises: [
        Exercise(
          id: 'squat',
          name: 'Squat',
          muscleGroup: 'Legs',
          sets: 2,
          reps: 10,
          restSeconds: 30,
          weightKg: 20,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutPage(workout: workout, controller: controller),
      ),
    );

    // Set 1: plan defaults (10 × 20).
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();

    // Set 2: user edits actuals (8 × 22.5).
    await tester.enterText(find.byKey(const Key('set-amount')), '8');
    await tester.enterText(find.byKey(const Key('set-weight')), '22.5');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    final saved = controller.sessions.single;
    expect(saved.completedSets, 2);
    expect(saved.volumeKg, 10 * 20 + 8 * 22.5);
    expect(saved.exercises.single.performedSets.map((set) => set.amount), [
      10,
      8,
    ]);
    expect(saved.exercises.single.performedSets.map((set) => set.weightKg), [
      20,
      22.5,
    ]);
  });
}
