import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/form_result.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:prm/features/workouts/presentation/set_input.dart';
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

/// A two-rep squat verdict, one rep clean.
const verdict = FormResult(
  exercise: 'squat',
  reps: [
    FormRep(number: 1, faults: []),
    FormRep(number: 2, faults: ['heelsUp']),
  ],
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
      FormExercise.match('Squat to Overhead Press', timed: false),
      FormExercise.squat,
    );
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
    for (final name in [
      'Single-arm Dumbbell Shoulder Press',
      'One Arm Overhead Press',
      'Machine Shoulder Press',
      'Seated Dumbbell Shoulder Press',
      'Alternating Dumbbell Shoulder Press',
      '1-arm Overhead Press',
    ]) {
      expect(FormExercise.match(name, timed: false), isNull, reason: name);
    }
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
        return (amount: 14, form: verdict);
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
    final sets = saved.exercises.single.performedSets;
    expect(sets.first.amount, 14);
    // The camera's verdict is saved with the set it counted, only.
    expect(sets.first.form?.reps, hasLength(2));
    expect(sets.last.form, isNull);
  });

  Future<List<SetEntry>> finish(
    WidgetTester tester,
    AppController controller,
  ) async {
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();
    return controller.sessions.single.exercises.single.performedSets;
  }

  testWidgets('a later camera run without a verdict replaces the earlier', (
    tester,
  ) async {
    var runs = 0;
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: runs++ == 0 ? verdict : null),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('form-check-set')));
      await tester.pump();
    }
    final sets = await finish(tester, controller);
    expect(sets.first.amount, 14);
    expect(sets.first.form, isNull);
  });

  testWidgets('undo and re-log keeps the camera verdict', (tester) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: verdict),
    );
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('undo-set')));
    await tester.pump();
    final sets = await finish(tester, controller);
    expect(sets.first.amount, 14);
    expect(sets.first.form?.reps, hasLength(2));
  });

  testWidgets('a count over the set limit is clamped without its verdict', (
    tester,
  ) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: SetInput.maxReps + 5, form: verdict),
    );
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();
    final sets = await finish(tester, controller);
    expect(sets.first.amount, SetInput.maxReps);
    expect(sets.first.form, isNull);
  });

  testWidgets('editing away from the camera count and back drops it', (
    tester,
  ) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: verdict),
    );
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('set-amount')), '12');
    await tester.enterText(find.byKey(const Key('set-amount')), '14');
    final sets = await finish(tester, controller);
    expect(sets.first.amount, 14);
    expect(sets.first.form, isNull);
  });

  testWidgets('a camera verdict is dropped when the count is edited', (
    tester,
  ) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: verdict),
    );
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('set-amount')), '12');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();

    final sets = controller.sessions.single.exercises.single.performedSets;
    expect(sets.first.amount, 12);
    expect(sets.first.form, isNull);
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
      launch: (_, _) async => (amount: 42, form: null),
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
