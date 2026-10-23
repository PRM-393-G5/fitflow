import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/form_result.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/squat_form/domain/hands_free_session.dart';
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

  test('matches the arm exercises of an arm day', () {
    for (final (name, exercise) in [
      ('Dumbbell Curl', FormExercise.curl),
      ('Hammer Curl', FormExercise.curl),
      ('Barbell Biceps Curls', FormExercise.curl),
      ('Overhead Triceps Extension', FormExercise.tricepsExtension),
      ('Dumbbell Overhead Tricep Extension', FormExercise.tricepsExtension),
      ('French Press', FormExercise.tricepsExtension),
      ('Bench Dip', FormExercise.dip),
      ('Chair dips', FormExercise.dip),
      ('Dips', FormExercise.dip),
    ]) {
      expect(FormExercise.match(name, timed: false), exercise, reason: name);
    }
    // Still the press, not a triceps extension.
    expect(
      FormExercise.match('Overhead Press', timed: false),
      FormExercise.shoulderPress,
    );
    for (final name in [
      'Leg Curl',
      'Lying Hamstring Curl',
      'Nordic Curl',
      'Wrist Curl',
      'Preacher Curl',
      'Concentration Curl',
      'Incline Dumbbell Curl',
      'Skull Crusher',
      'Lying Triceps Extension',
      'Triceps Pushdown',
      'Leg Extension',
    ]) {
      expect(FormExercise.match(name, timed: false), isNull, reason: name);
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
    HandsFreeLauncher? handsFree,
    List<Exercise> then = const [],
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
            exercises: [planned, ...then],
          ),
          controller: controller,
          launchFormCheck: launch,
          launchHandsFree: handsFree,
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

  testWidgets('a camera count logs the set with its verdict', (tester) async {
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
    // No "Complete set" tap: the counted set is logged and rest starts.
    expect(find.text('1 of 2 sets'), findsOneWidget);
    expect(
      find.text('Logged 14 reps from the camera. Undo to fix it.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('skip-rest')), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    // The next set is prefilled from the one just logged.
    expect(amountText(tester), '14');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();

    final sets = controller.sessions.single.exercises.single.performedSets;
    expect(sets.first.amount, 14);
    // The camera's verdict is saved with the set it counted, only.
    expect(sets.first.form?.reps, hasLength(2));
    expect(sets.last.form, isNull);
  });

  /// Skips the rest after the camera-logged first set, logs the second by
  /// hand and finishes.
  Future<List<SetEntry>> finishAfterCamera(
    WidgetTester tester,
    AppController controller,
  ) async {
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();
    return controller.sessions.single.exercises.single.performedSets;
  }

  /// Undoes the camera-logged set, so its count is back in the field.
  Future<void> undoCameraSet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('undo-set')));
    await tester.pump();
    expect(amountText(tester), '14');
  }

  Future<void> completeAndFinish(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();
  }

  testWidgets('undo and re-log keeps the camera verdict', (tester) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: verdict),
    );
    await undoCameraSet(tester);
    await completeAndFinish(tester);
    final sets = controller.sessions.single.exercises.single.performedSets;
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
    final sets = await finishAfterCamera(tester, controller);
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
    await undoCameraSet(tester);
    await tester.enterText(find.byKey(const Key('set-amount')), '12');
    await tester.enterText(find.byKey(const Key('set-amount')), '14');
    await completeAndFinish(tester);
    final sets = controller.sessions.single.exercises.single.performedSets;
    expect(sets.first.amount, 14);
    expect(sets.first.form, isNull);
  });

  testWidgets('a camera verdict is dropped when the count is fixed', (
    tester,
  ) async {
    final controller = await pumpWorkout(
      tester,
      exercise('Bodyweight Squat', reps: 10),
      launch: (_, _) async => (amount: 14, form: verdict),
    );
    await undoCameraSet(tester);
    await tester.enterText(find.byKey(const Key('set-amount')), '12');
    await completeAndFinish(tester);

    final sets = controller.sessions.single.exercises.single.performedSets;
    expect(sets.first.amount, 12);
    expect(sets.first.form, isNull);
  });

  testWidgets('an invalid weight leaves the count to log by hand', (
    tester,
  ) async {
    await pumpWorkout(
      tester,
      exercise('Dumbbell Curl'),
      launch: (_, _) async => (amount: 11, form: null),
    );
    await tester.enterText(find.byKey(const Key('set-weight')), 'abc');
    await tester.tap(find.byKey(const Key('form-check-set')));
    await tester.pump();

    expect(find.text('0 of 2 sets'), findsOneWidget);
    expect(amountText(tester), '11');
    expect(
      find.text('Counted 11 reps — complete the set to save it.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
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

    expect(find.text('1 of 2 sets'), findsOneWidget);
    expect(
      find.text('Logged a 42s hold from the camera. Undo to fix it.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('arm-day exercises get the camera too', (tester) async {
    for (final (name, expected) in [
      ('Dumbbell Curl', FormExercise.curl),
      ('Overhead Triceps Extension', FormExercise.tricepsExtension),
      ('Bench Dip', FormExercise.dip),
    ]) {
      FormExercise? opened;
      await pumpWorkout(
        tester,
        exercise(name),
        launch: (_, launched) async {
          opened = launched;
          return null;
        },
      );
      expect(find.text('Count with camera'), findsOneWidget, reason: name);
      await tester.tap(find.byKey(const Key('form-check-set')));
      await tester.pump();
      expect(opened, expected, reason: name);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('exercises without an analyzer show no camera button', (
    tester,
  ) async {
    await pumpWorkout(tester, exercise('Dumbbell Bench Press'));

    expect(find.byKey(const Key('form-check-set')), findsNothing);
  });

  group('hands-free', () {
    testWidgets('plans the camera sets up to the first manual exercise', (
      tester,
    ) async {
      List<PlannedSet>? planned;
      await pumpWorkout(
        tester,
        exercise('Dumbbell Curl', reps: 12),
        then: [
          exercise('Bench Dip', reps: 15),
          exercise('Cable Crossover'),
          exercise('Hammer Curl'),
        ],
        handsFree: (_, plan) async {
          planned = plan;
          return null;
        },
      );

      expect(find.text('Hands-free · 4 sets'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hands-free')));
      await tester.pump();

      expect(
        [
          for (final set in planned!)
            '${set.name} ${set.setNumber}/${set.sets}',
        ],
        [
          'Dumbbell Curl 1/2',
          'Dumbbell Curl 2/2',
          'Bench Dip 1/2',
          'Bench Dip 2/2',
        ],
      );
      expect(planned!.first.exercise, FormExercise.curl);
      expect(planned!.first.target, 12);
      expect(planned![2].exercise, FormExercise.dip);
      expect(planned![2].restSeconds, 30);
      // Closed without a set: nothing logged.
      expect(find.text('0 of 8 sets'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('logs every set the camera ran, resting after the last', (
      tester,
    ) async {
      await pumpWorkout(
        tester,
        exercise('Dumbbell Curl', reps: 12),
        then: [exercise('Bench Dip', reps: 15), exercise('Cable Crossover')],
        handsFree: (_, plan) async => [
          (amount: 12, form: verdict),
          (amount: 10, form: null),
          (amount: 15, form: null),
        ],
      );
      await tester.tap(find.byKey(const Key('hands-free')));
      await tester.pump();

      expect(find.text('3 of 6 sets'), findsOneWidget);
      expect(
        find.text('Logged 3 sets hands-free. Undo to fix one.'),
        findsOneWidget,
      );
      // The camera rested between sets; the last one rests here.
      expect(find.byKey(const Key('skip-rest')), findsOneWidget);
      await tester.tap(find.byKey(const Key('skip-rest')));
      await tester.pump();
      expect(find.text('Bench Dip'), findsWidgets);
      expect(find.text('Set 2 of 2'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('saves counts and verdicts, and finishes at the end', (
      tester,
    ) async {
      final controller = await pumpWorkout(
        tester,
        exercise('Hammer Curl', reps: 10),
        handsFree: (_, plan) async => [
          (amount: 10, form: verdict),
          (amount: 8, form: null),
        ],
      );
      await tester.tap(find.byKey(const Key('hands-free')));
      await tester.pumpAndSettle();

      // Every planned set is done: the workout asks to finish.
      await tester.tap(find.text('Finish').last);
      await tester.pumpAndSettle();
      final sets = controller.sessions.single.exercises.single.performedSets;
      expect([for (final set in sets) set.amount], [10, 8]);
      expect(sets.first.form?.reps, hasLength(2));
      expect(sets.last.form, isNull);
    });

    testWidgets('a single set left needs no hands-free', (tester) async {
      await pumpWorkout(
        tester,
        exercise('Dumbbell Curl'),
        then: [exercise('Cable Crossover')],
        launch: (_, _) async => (amount: 10, form: null),
      );
      expect(find.byKey(const Key('hands-free')), findsOneWidget);
      await tester.tap(find.byKey(const Key('form-check-set')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('skip-rest')));
      await tester.pump();
      // One curl set left: counting it is one tap already.
      expect(find.byKey(const Key('hands-free')), findsNothing);
      expect(find.byKey(const Key('form-check-set')), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('uses the edited target and validates weight before opening', (
      tester,
    ) async {
      List<PlannedSet>? planned;
      await pumpWorkout(
        tester,
        exercise('Dumbbell Curl', reps: 10),
        handsFree: (_, plan) async {
          planned = plan;
          return null;
        },
      );

      await tester.enterText(find.byKey(const Key('set-amount')), '14');
      await tester.enterText(find.byKey(const Key('set-weight')), 'abc');
      await tester.tap(find.byKey(const Key('hands-free')));
      await tester.pumpAndSettle();
      // Invalid weight blocks opening the camera and shows the field error.
      expect(planned, isNull);
      expect(find.text('Enter 0 or more'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('set-weight')), '12');
      await tester.tap(find.byKey(const Key('hands-free')));
      await tester.pumpAndSettle();
      expect(planned, isNotNull);
      expect([for (final set in planned!) set.target], [14, 14]);
    });
  });
}
