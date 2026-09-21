import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/progression.dart';
import 'package:prm/domain/workout_stats.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise plan(
  String name, {
  int sets = 3,
  int reps = 10,
  int seconds = 0,
  double kg = 0,
}) => Exercise(
  id: name,
  name: name,
  muscleGroup: 'x',
  sets: sets,
  reps: seconds > 0 ? 0 : reps,
  durationSeconds: seconds,
  weightKg: kg,
);

WorkoutSession done(
  DateTime day,
  Exercise exercise,
  List<SetEntry> sets, {
  String workoutId = 'workout',
}) => WorkoutSession(
  id: day.toIso8601String(),
  workoutId: workoutId,
  workoutName: 'Workout',
  startedAt: day,
  completedAt: day,
  completedSets: sets.length,
  volumeKg: 0,
  exercises: [exercise.copyWith(performedSets: sets)],
);

List<SetEntry> sets(int count, int amount, [double kg = 0]) => [
  for (var i = 0; i < count; i++) SetEntry(amount: amount, weightKg: kg),
];

void main() {
  final row = plan('Dumbbell Row', kg: 10);

  test('no history gives no hint', () {
    expect(Progression.forExercise(const [], row), isNull);
  });

  test('every rep at the top weight steps the weight up', () {
    final hint = Progression.forExercise([
      done(DateTime(2026, 10, 1), row, sets(3, 10, 12)),
    ], row)!;

    expect(hint.stepUp, isTrue);
    expect(hint.weightKg, 14.5);
    expect(hint.amount, 10);
    expect(hint.lastSets.length, 3);
  });

  test('missed reps repeat the same weight', () {
    final hint = Progression.forExercise([
      done(DateTime(2026, 10, 1), row, const [
        SetEntry(amount: 10, weightKg: 12),
        SetEntry(amount: 8, weightKg: 12),
        SetEntry(amount: 7, weightKg: 12),
      ]),
    ], row)!;

    expect(hint.stepUp, isFalse);
    expect(hint.weightKg, 12);
    expect(hint.amount, 10);
  });

  test('skipped sets or a lighter drop set do not step up', () {
    final skipped = Progression.forExercise([
      done(DateTime(2026, 10, 1), row, sets(2, 10, 12)),
    ], row)!;
    final dropSet = Progression.forExercise([
      done(DateTime(2026, 10, 1), row, const [
        SetEntry(amount: 10, weightKg: 12),
        SetEntry(amount: 10, weightKg: 12),
        SetEntry(amount: 10, weightKg: 8),
      ]),
    ], row)!;

    expect(skipped.stepUp, isFalse);
    expect(dropSet.stepUp, isFalse);
    expect(dropSet.weightKg, 12);
  });

  test('imperial users step up by 5 lb', () {
    final hint = Progression.forExercise(
      [done(DateTime(2026, 10, 1), row, sets(3, 10, 20))],
      row,
      weightStepKg: Progression.imperialStepKg,
    )!;

    expect(hint.weightKg, closeTo(20 + 2.26796, 1e-6));
  });

  test('bodyweight adds a rep once every set reached the plan', () {
    final pushUp = plan('Push-up', reps: 12);

    final hit = Progression.forExercise([
      done(DateTime(2026, 10, 1), pushUp, const [
        SetEntry(amount: 14),
        SetEntry(amount: 13),
        SetEntry(amount: 12),
      ]),
    ], pushUp)!;
    final missed = Progression.forExercise([
      done(DateTime(2026, 10, 1), pushUp, const [
        SetEntry(amount: 12),
        SetEntry(amount: 10),
        SetEntry(amount: 8),
      ]),
    ], pushUp)!;

    expect(hit.stepUp, isTrue);
    expect(hit.amount, 13);
    expect(hit.weightKg, 0);
    expect(missed.stepUp, isFalse);
    expect(missed.amount, 12);
  });

  test('bodyweight without a step up never drops below what was done', () {
    final pushUp = plan('Push-up', reps: 12);
    final hint = Progression.forExercise([
      done(DateTime(2026, 10, 1), pushUp, sets(1, 15)),
    ], pushUp)!;

    expect(hint.stepUp, isFalse);
    expect(hint.amount, 15);
  });

  test('holds add 5 seconds and keep the load', () {
    final plank = plan('Plank', sets: 2, seconds: 45);
    final hint = Progression.forExercise([
      done(DateTime(2026, 10, 1), plank, sets(2, 45, 5)),
    ], plank)!;

    expect(hint.stepUp, isTrue);
    expect(hint.amount, 50);
    expect(hint.weightKg, 5);
  });

  test('uses the newest session, matching names case-insensitively', () {
    final hint = Progression.forExercise([
      done(DateTime(2026, 10, 1), row, sets(3, 10, 30)),
      done(DateTime(2026, 10, 8), plan(' dumbbell row '), sets(3, 8, 12)),
    ], row)!;

    expect(hint.lastDate, DateTime(2026, 10, 8));
    expect(hint.weightKg, 12);
  });

  test('form checks and timed/rep mismatches are ignored', () {
    final pushUp = plan('Push-up', reps: 12);
    final timedPushUp = plan('Push-up', seconds: 30);

    expect(
      Progression.forExercise([
        done(
          DateTime(2026, 10, 1),
          pushUp,
          sets(1, 20),
          workoutId: WorkoutStats.formCheckId,
        ),
        done(DateTime(2026, 10, 2), timedPushUp, sets(3, 30)),
      ], pushUp),
      isNull,
    );
  });

  testWidgets('active workout prefills from last session and shows hints', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();
    await controller.addSession(
      done(DateTime(2026, 10, 1), row, sets(3, 10, 12)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: FToaster(child: child!),
        ),
        home: ActiveWorkoutPage(
          workout: Workout(
            id: 'w1',
            name: 'Back',
            duration: const Duration(minutes: 5),
            level: 'Beginner',
            category: 'Strength',
            description: '',
            exercises: [row],
          ),
          controller: controller,
        ),
      ),
    );

    expect(find.text('Last time: 3 × 10 @ 12 kg'), findsOneWidget);
    expect(find.byKey(const Key('step-up')), findsOneWidget);
    expect(
      find.text('You hit every rep last time — try 14.5 kg today.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();

    // Later sets follow what was just logged, not the plan's 10 kg.
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();

    final saved = controller.sessions.first;
    expect(saved.exercises.single.performedSets.map((set) => set.weightKg), [
      14.5,
      14.5,
      14.5,
    ]);
  });
}
