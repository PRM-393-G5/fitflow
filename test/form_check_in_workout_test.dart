import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise exercise(String name, {int reps = 10, int seconds = 0}) => Exercise(
  id: name,
  name: name,
  muscleGroup: 'x',
  sets: 2,
  reps: seconds > 0 ? 0 : reps,
  durationSeconds: seconds,
  restSeconds: 30,
);

void main() {
  test('matches plan exercises the analyzers can count', () {
    expect(
      FormExercise.match('Bodyweight Squat', timed: false),
      FormExercise.squat,
    );
    expect(
      FormExercise.match('Goblet Squat', timed: false),
      FormExercise.squat,
    );
    expect(FormExercise.match('Push-up', timed: false), FormExercise.pushup);
    expect(FormExercise.match('push ups', timed: false), FormExercise.pushup);
    expect(FormExercise.match('Pushup', timed: false), FormExercise.pushup);
    expect(FormExercise.match('Plank', timed: true), FormExercise.plank);
    expect(
      FormExercise.match('Shoulder Press', timed: false),
      FormExercise.shoulderPress,
    );
    expect(
      FormExercise.match('Dumbbell Overhead Press', timed: false),
      FormExercise.shoulderPress,
    );
    for (final name in ['Shoulder-Press', 'shoulderpress', 'OHP']) {
      expect(
        FormExercise.match(name, timed: false),
        FormExercise.shoulderPress,
        reason: name,
      );
    }
  });

  test('leaves out variants and kinds the analyzers cannot judge', () {
    expect(FormExercise.match('Bulgarian Split Squat', timed: false), isNull);
    expect(FormExercise.match('Side Plank', timed: true), isNull);
    expect(FormExercise.match('Plank', timed: false), isNull);
    expect(FormExercise.match('Squat hold', timed: true), isNull);
    expect(FormExercise.match('Dumbbell Bench Press', timed: false), isNull);
    expect(FormExercise.match('Shoulder Press', timed: true), isNull);
  });

  Future<AppController> pumpWorkout(
    WidgetTester tester,
    Exercise planned, {
    FormCheckLauncher? launch,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();
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
            name: 'Test',
            duration: const Duration(minutes: 5),
            level: 'Beginner',
            category: 'Strength',
            description: '',
            exercises: [planned],
          ),
          controller: controller,
          launchFormCheck: launch,
        ),
      ),
    );
    return controller;
  }

  String amountText(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('set-amount')),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  testWidgets('camera count fills the set, which the user then logs', (
    tester,
  ) async {
    FormExercise? opened;
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat'),
      launch: (_, exercise) async {
        opened = exercise;
        return 14;
      },
    );

    expect(find.text('Count with camera'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();

    expect(opened, FormExercise.squat);
    expect(amountText(tester), '14');
    expect(
      find.text('Counted 14 reps — complete the set to save it.'),
      findsOneWidget,
    );
    // Counting alone does not log a set.
    expect(find.text('0 of 2 sets'), findsOneWidget);

    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();

    final saved = controller.sessions.single;
    expect(saved.exercises.single.performedSets.first.amount, 14);
  });

  testWidgets('nothing counted keeps the prefilled amount', (tester) async {
    await pumpWorkout(
      tester,
      exercise('Push-up', reps: 12),
      launch: (_, _) async => null,
    );

    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();

    expect(amountText(tester), '12');
    await tester.pumpAndSettle();
  });

  testWidgets('planks time the hold with the camera', (tester) async {
    await pumpWorkout(
      tester,
      exercise('Plank', seconds: 30),
      launch: (_, _) async => 42,
    );

    expect(find.text('Time hold with camera'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();

    expect(amountText(tester), '42');
    await tester.pumpAndSettle();
  });

  testWidgets('exercises without an analyzer show no camera button', (
    tester,
  ) async {
    await pumpWorkout(tester, exercise('Dumbbell Bench Press'));

    expect(find.byKey(const Key('form-check-set')), findsNothing);
  });
}
