import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/onboarding/presentation/onboarding_page.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:prm/features/workouts/presentation/weight_units.dart';
import 'package:prm/features/workouts/presentation/workout_builder_page.dart';
import 'package:prm/features/workouts/presentation/workout_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Workout plan({
  String id = 'w1',
  int sets = 1,
  int reps = 10,
  int rest = 0,
  double weightKg = 0,
}) => Workout(
  id: id,
  name: 'Legs',
  duration: const Duration(minutes: 5),
  level: 'Beginner',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(
      id: 'squat',
      name: 'Squat',
      muscleGroup: 'Legs',
      sets: sets,
      reps: reps,
      restSeconds: rest,
      weightKg: weightKg,
    ),
  ],
);

Future<AppController> makeController({
  bool metric = true,
  List<Workout> saved = const [],
}) async {
  SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences, templates: const []),
    preferences,
  );
  await controller.load();
  await controller.setMetric(metric);
  for (final workout in saved) {
    await controller.saveWorkout(workout);
  }
  return controller;
}

/// Pumps a launcher that pushes [page], so pages can pop back to it.
Future<void> launch(
  WidgetTester tester,
  AppController controller,
  Widget Function() page,
) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: FToaster(child: child!),
        ),
        home: Builder(
          builder: (context) => Center(
            child: FButton(
              key: const Key('launch'),
              mainAxisSize: .min,
              onPress: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('launch')));
  await tester.pumpAndSettle();
}

Future<void> confirmFinish(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Finish workout?'), findsOneWidget);
  await tester.tap(find.text('Finish').last);
  await tester.pumpAndSettle();
}

/// Lets toast auto-dismiss timers run out before the test ends.
Future<void> flushToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  group('active workout', () {
    testWidgets('records real elapsed time from when the page opened', (
      tester,
    ) async {
      final controller = await makeController();
      final opened = DateTime(2026, 10, 9, 8);
      var now = opened;
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: plan(),
          controller: controller,
          clock: () => now,
        ),
      );

      now = opened.add(const Duration(minutes: 25));
      await tester.tap(find.byKey(const Key('complete-set')));
      await confirmFinish(tester);

      final saved = controller.sessions.single;
      expect(saved.startedAt, opened);
      expect(saved.completedAt, now);
      expect(saved.durationMinutes, 25);
      await flushToasts(tester);
    });

    testWidgets('finishing with no completed sets discards without saving', (
      tester,
    ) async {
      final controller = await makeController();
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(workout: plan(), controller: controller),
      );

      await tester.tap(find.byKey(const Key('finish-header')));
      await tester.pumpAndSettle();
      expect(find.text('Discard workout?'), findsOneWidget);
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();

      expect(find.byType(ActiveWorkoutPage), findsNothing);
      expect(controller.sessions, isEmpty);
      expect(await controller.repository.getRecentSessions(), isEmpty);
    });

    testWidgets('zero rest advances at once and the plan caps the sets', (
      tester,
    ) async {
      final controller = await makeController();
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(workout: plan(sets: 2), controller: controller),
      );

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pump();
      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(find.text('1 of 2 sets'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();

      // No way to log a 3rd set of a 2-set plan; only Finish or Undo.
      expect(find.byKey(const Key('complete-set')), findsNothing);
      expect(find.byKey(const Key('finish-workout')), findsOneWidget);
      expect(find.text('2 of 2 sets'), findsOneWidget);

      await tester.tap(find.byKey(const Key('undo-set')));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(find.text('1 of 2 sets'), findsOneWidget);
    });

    testWidgets('rejects zero reps', (tester) async {
      final controller = await makeController();
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(workout: plan(), controller: controller),
      );

      await tester.enterText(find.byKey(const Key('set-amount')), '0');
      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();

      expect(find.text('Enter at least 1 rep'), findsOneWidget);
      expect(find.text('0 of 1 sets'), findsOneWidget);
    });

    testWidgets('weight is entered in lb and stored in kg', (tester) async {
      final controller = await makeController(metric: false);
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: plan(sets: 2, weightKg: 20),
          controller: controller,
        ),
      );

      expect(find.text('Weight (lb)'), findsOneWidget);
      expect(find.text('44.1'), findsOneWidget);
      // Set 1 untouched: keeps the exact plan kg, no rounding drift.
      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pump();
      // Set 2: comma decimal in lb.
      await tester.enterText(find.byKey(const Key('set-weight')), '50,5');
      await tester.tap(find.byKey(const Key('complete-set')));
      await confirmFinish(tester);

      final sets = controller.sessions.single.exercises.single.performedSets;
      expect(sets[0].weightKg, 20);
      expect(sets[1].weightKg, closeTo(50.5 / WeightUnits.lbPerKg, 1e-9));
      await flushToasts(tester);
    });

    testWidgets('finishing mid-hold logs the seconds held so far', (
      tester,
    ) async {
      final controller = await makeController();
      final opened = DateTime(2026, 10, 9, 8);
      var now = opened;
      const plank = Exercise(
        id: 'plank',
        name: 'Plank',
        muscleGroup: 'Core',
        sets: 2,
        reps: 0,
        durationSeconds: 60,
      );
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: const Workout(
            id: 'w-plank',
            name: 'Core',
            duration: Duration(minutes: 5),
            level: 'Beginner',
            category: 'Core',
            description: '',
            exercises: [plank],
          ),
          controller: controller,
          clock: () => now,
        ),
      );

      await tester.tap(find.byKey(const Key('start-hold')));
      await tester.pump();
      now = opened.add(const Duration(seconds: 25));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('finish-header')));
      await confirmFinish(tester);

      final sets = controller.sessions.single.exercises.single.performedSets;
      expect(sets.single.amount, 25);
      await flushToasts(tester);
    });

    testWidgets('caps reps and weight with field errors', (tester) async {
      final controller = await makeController(metric: false);
      await launch(
        tester,
        controller,
        () => ActiveWorkoutPage(workout: plan(), controller: controller),
      );

      await tester.enterText(find.byKey(const Key('set-amount')), '1001');
      await tester.enterText(find.byKey(const Key('set-weight')), '1e308');
      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();
      expect(find.text('Max 1000 reps'), findsOneWidget);
      expect(find.text('Max 2204.6 lb'), findsOneWidget);
      expect(find.text('0 of 1 sets'), findsOneWidget);

      // The displayed limit itself is accepted.
      await tester.enterText(find.byKey(const Key('set-amount')), '1000');
      await tester.enterText(find.byKey(const Key('set-weight')), '2204.6');
      await tester.tap(find.byKey(const Key('complete-set')));
      await confirmFinish(tester);
      final set = controller.sessions.single.exercises.single.performedSets;
      expect(set.single.amount, 1000);
      expect(set.single.weightKg, lessThanOrEqualTo(WeightUnits.maxKg));
      await flushToasts(tester);
    });
  });

  group('builder', () {
    testWidgets('editing keeps the workout id', (tester) async {
      final original = plan(id: 'custom-1', weightKg: 20);
      final controller = await makeController(saved: [original]);
      await launch(
        tester,
        controller,
        () => WorkoutBuilderPage(initial: original),
      );

      expect(find.text('Edit workout'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('builder-name')), 'Leg Day');
      await tester.tap(find.byKey(const Key('save-custom-workout')));
      await tester.pumpAndSettle();

      final saved = controller.workouts.single;
      expect(saved.id, 'custom-1');
      expect(saved.name, 'Leg Day');
      expect(saved.exercises.single.id, 'squat');
      expect(saved.exercises.single.weightKg, 20);
      expect(
        (await controller.repository.getWorkouts()).single.name,
        'Leg Day',
      );
      expect(find.byType(WorkoutBuilderPage), findsNothing);
    });

    testWidgets('shows field errors instead of silently defaulting', (
      tester,
    ) async {
      final controller = await makeController();
      await launch(tester, controller, () => const WorkoutBuilderPage());

      await tester.enterText(find.byKey(const Key('builder-name')), 'Push');
      await tester.enterText(
        find.byKey(const Key('builder-exercise-name-0')),
        'Bench',
      );
      await tester.enterText(find.byKey(const Key('builder-sets-0')), '0');
      await tester.tap(find.byKey(const Key('save-custom-workout')));
      await tester.pumpAndSettle();

      expect(find.text('1–20'), findsOneWidget);
      expect(controller.workouts, isEmpty);
      await flushToasts(tester);
    });

    testWidgets('rejects weights above the cap', (tester) async {
      final controller = await makeController();
      await launch(tester, controller, () => const WorkoutBuilderPage());

      await tester.enterText(find.byKey(const Key('builder-name')), 'Push');
      await tester.enterText(
        find.byKey(const Key('builder-exercise-name-0')),
        'Bench',
      );
      await tester.enterText(find.byKey(const Key('builder-weight-0')), '1001');
      await tester.tap(find.byKey(const Key('save-custom-workout')));
      await tester.pumpAndSettle();

      expect(find.text('Max 1000 kg'), findsOneWidget);
      expect(controller.workouts, isEmpty);
      await flushToasts(tester);
    });

    testWidgets('stores lb weight as kg and supports timed rows', (
      tester,
    ) async {
      final controller = await makeController(metric: false);
      await launch(tester, controller, () => const WorkoutBuilderPage());

      await tester.enterText(find.byKey(const Key('builder-name')), 'Push');
      await tester.enterText(
        find.byKey(const Key('builder-exercise-name-0')),
        'Plank',
      );
      await tester.tap(find.byKey(const Key('builder-timed-0')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('builder-seconds-0')), '40');
      await tester.enterText(find.byKey(const Key('builder-weight-0')), '22,5');
      await tester.tap(find.byKey(const Key('save-custom-workout')));
      await tester.pumpAndSettle();

      final workout = controller.workouts.single;
      final exercise = workout.exercises.single;
      expect(workout.id, startsWith('custom-'));
      expect(exercise.isTimed, isTrue);
      expect(exercise.durationSeconds, 40);
      expect(exercise.weightKg, closeTo(22.5 / WeightUnits.lbPerKg, 1e-9));
    });

    testWidgets('asks before discarding unsaved changes', (tester) async {
      final controller = await makeController();
      await launch(tester, controller, () => const WorkoutBuilderPage());

      await tester.enterText(find.byKey(const Key('builder-name')), 'Draft');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('discard-workout-changes')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutBuilderPage), findsNothing);
      expect(controller.workouts, isEmpty);
    });
  });

  testWidgets('custom workouts can be deleted from details', (tester) async {
    final custom = plan(id: 'custom-1');
    final controller = await makeController(
      saved: [
        custom,
        plan(id: 't1'),
      ],
    );
    await controller.setScheduleDay(1, 'custom-1');
    await launch(tester, controller, () => WorkoutDetailPage(workout: custom));

    await tester.tap(find.byKey(const Key('delete-workout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-workout')));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutDetailPage), findsNothing);
    expect(controller.workouts.map((item) => item.id), ['t1']);
    expect(controller.schedule, isEmpty);
  });

  testWidgets('templates have no edit/delete actions', (tester) async {
    final controller = await makeController(saved: [plan(id: 't1')]);
    await launch(
      tester,
      controller,
      () => WorkoutDetailPage(workout: controller.workouts.single),
    );

    expect(find.byKey(const Key('edit-workout')), findsNothing);
    expect(find.byKey(const Key('delete-workout')), findsNothing);
  });

  testWidgets('back on onboarding counts as skip', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();
    await launch(tester, controller, () => const OnboardingPage());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsNothing);
    expect(controller.onboardingDone, isTrue);
    expect(controller.goal, isNull);
  });
}
