import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/exercise_catalog.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/home/presentation/home_page.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:prm/features/workouts/presentation/workout_builder_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const twoExercisePlan = Workout(
  id: 'w-gym',
  name: 'Full Gym Session',
  duration: Duration(minutes: 30),
  level: 'Intermediate',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(
      id: 'squat',
      name: 'Barbell Back Squat',
      muscleGroup: 'Legs',
      sets: 2,
      reps: 8,
      restSeconds: 0,
      weightKg: 60,
    ),
    Exercise(
      id: 'bench',
      name: 'Barbell Bench Press',
      muscleGroup: 'Chest',
      sets: 2,
      reps: 10,
      restSeconds: 0,
      weightKg: 50,
    ),
  ],
);

Future<AppController> makeController({
  Map<String, Object> initialPrefs = const {'onboarding_v1': '{"done":true}'},
  List<Workout> saved = const [],
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences, templates: const []),
    preferences,
  );
  await controller.load();
  for (final workout in saved) {
    await controller.saveWorkout(workout);
  }
  return controller;
}

Future<void> launchPage(
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
              onPress: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => page())),
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

Future<void> flushToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  group('auto-save & resume active workout', () {
    testWidgets(
      'auto-saves progress after each set and resumes across app restart',
      (tester) async {
        final started = DateTime(2026, 10, 23, 9, 0);
        var now = started;
        final controller = await makeController(saved: [twoExercisePlan]);

        await launchPage(
          tester,
          controller,
          () => ActiveWorkoutPage(
            workout: twoExercisePlan,
            controller: controller,
            clock: () => now,
          ),
        );

        // Log Set 1 of Squat (8 × 60 kg).
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();

        expect(controller.activeDraft, isNotNull);
        expect(controller.activeDraft!.completedSets, 1);
        expect(controller.activeDraft!.totalSets, 4);
        expect(controller.activeDraft!.startedAt, started);

        // Simulate app process killed and restarted from SharedPreferences.
        final reloaded = AppController(
          LocalWorkoutRepository(controller.preferences, templates: const []),
          controller.preferences,
        );
        await reloaded.load();
        expect(reloaded.activeDraft, isNotNull);
        expect(reloaded.activeDraft!.workout.name, 'Full Gym Session');
        expect(reloaded.activeDraft!.completedSets, 1);

        // HomePage shows the Resume card and resumes into ActiveWorkoutPage.
        await tester.pumpWidget(
          AppScope(
            key: UniqueKey(),
            controller: reloaded,
            child: MaterialApp(
              theme: AppTheme.light.toApproximateMaterialTheme(),
              builder: (context, child) => FTheme(
                data: AppTheme.light,
                child: FToaster(child: child!),
              ),
              home: const FScaffold(child: HomePage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('resume-workout-card')), findsOneWidget);
        expect(find.text('1 of 4 sets logged'), findsOneWidget);

        await tester.tap(find.byKey(const Key('resume-workout')));
        await tester.pumpAndSettle();

        // Resumed right at Set 2 of Squat!
        expect(find.text('Barbell Back Squat'), findsOneWidget);
        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(find.text('1 of 4 sets'), findsOneWidget);

        // Complete the remaining 3 sets and finish.
        now = started.add(const Duration(minutes: 35));
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish').last);
        await tester.pumpAndSettle();

        expect(reloaded.activeDraft, isNull);
        expect(reloaded.sessions, hasLength(1));
        expect(reloaded.sessions.single.completedSets, 4);
        expect(reloaded.sessions.single.startedAt, started);
        await flushToasts(tester);
      },
    );

    testWidgets('undoing back to 0 sets or discarding clears the draft', (
      tester,
    ) async {
      final controller = await makeController(saved: [twoExercisePlan]);
      await launchPage(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: twoExercisePlan,
          controller: controller,
        ),
      );

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();
      expect(controller.activeDraft, isNotNull);

      await tester.tap(find.byKey(const Key('undo-set')));
      await tester.pumpAndSettle();
      expect(controller.activeDraft, isNull);
    });
  });

  group('mid-workout flexibility (switch, skip, add set)', () {
    testWidgets(
      'switching to a later exercise wraps around to finish earlier ones',
      (tester) async {
        final controller = await makeController();
        await launchPage(
          tester,
          controller,
          () => ActiveWorkoutPage(
            workout: twoExercisePlan,
            controller: controller,
          ),
        );

        // Squat rack is busy! Switch to Exercise 2 (Barbell Bench Press).
        expect(find.text('Barbell Back Squat'), findsOneWidget);
        await tester.tap(find.byKey(const Key('switch-exercise')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pick-exercise-1')));
        await tester.pumpAndSettle();

        expect(find.text('Barbell Bench Press'), findsOneWidget);
        expect(find.text('Set 1 of 2'), findsOneWidget);

        // Complete both sets of Barbell Bench Press.
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();
        expect(find.text('Set 2 of 2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();

        // Automatically wraps around to Barbell Back Squat Set 1 of 2!
        expect(find.text('Barbell Back Squat'), findsOneWidget);
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(find.text('2 of 4 sets'), findsOneWidget);

        // Complete both sets of Squat to finish.
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('complete-set')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish').last);
        await tester.pumpAndSettle();

        expect(controller.sessions.single.completedSets, 4);
        await flushToasts(tester);
      },
    );

    testWidgets('skipping an exercise adjusts total sets and advances', (
      tester,
    ) async {
      final controller = await makeController();
      await launchPage(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: twoExercisePlan,
          controller: controller,
        ),
      );

      // Skip Barbell Back Squat completely.
      await tester.tap(find.byKey(const Key('skip-exercise')));
      await tester.pump();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('0 of 2 sets'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish').last);
      await tester.pumpAndSettle();

      final saved = controller.sessions.single;
      expect(saved.completedSets, 2);
      expect(saved.exercises.single.name, 'Barbell Bench Press');
      await flushToasts(tester);
    });

    testWidgets('adding sets mid-workout or at the end logs extra sets', (
      tester,
    ) async {
      final controller = await makeController();
      const singleSetPlan = Workout(
        id: 'w-single',
        name: 'Quick',
        duration: Duration(minutes: 5),
        level: 'Beginner',
        category: 'Strength',
        description: '',
        exercises: [
          Exercise(
            id: 'squat',
            name: 'Bodyweight Squat',
            muscleGroup: 'Legs',
            sets: 1,
            reps: 10,
            restSeconds: 0,
          ),
        ],
      );
      await launchPage(
        tester,
        controller,
        () => ActiveWorkoutPage(
          workout: singleSetPlan,
          controller: controller,
        ),
      );

      // Add a 2nd set while on Set 1.
      await tester.tap(find.byKey(const Key('add-set')));
      await tester.pump();
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.text('0 of 2 sets'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();

      // Dismiss finish dialog ("Keep going") and add a 3rd set from the Done view.
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('All sets complete'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-set')));
      await tester.pump();
      expect(find.text('Set 3 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish').last);
      await tester.pumpAndSettle();

      expect(controller.sessions.single.completedSets, 3);
      await flushToasts(tester);
    });
  });

  group('exercise catalog & builder autocomplete', () {
    test('catalog matches queries, muscle groups, camera support and custom lifts', () {
      final legs = ExerciseCatalog.suggestions(muscleGroup: 'Legs');
      expect(legs, isNotEmpty);
      expect(legs.every((item) => item.muscleGroup == 'Legs'), isTrue);
      // Camera-supported squats rank first.
      expect(legs.first.hasCameraCheck, isTrue);

      final bench = ExerciseCatalog.suggestions(query: 'bench');
      expect(
        bench.map((item) => item.name),
        containsAll(['Barbell Bench Press', 'Dumbbell Bench Press', 'Bench Dip']),
      );

      // User's custom exercises are included in suggestions.
      const customWorkout = Workout(
        id: 'custom-1',
        name: 'Custom',
        duration: Duration(minutes: 10),
        level: 'Beginner',
        category: 'Strength',
        description: '',
        exercises: [
          Exercise(
            id: 'c1',
            name: 'Zercher Squat',
            muscleGroup: 'Legs',
            sets: 3,
            reps: 8,
          ),
        ],
      );
      final zercher = ExerciseCatalog.suggestions(
        query: 'zercher',
        workouts: [customWorkout],
      );
      expect(zercher.single.name, 'Zercher Squat');
    });

    testWidgets(
      'tapping a suggestion in WorkoutBuilderPage fills name, muscle group and mode',
      (tester) async {
        final controller = await makeController();
        await launchPage(tester, controller, () => const WorkoutBuilderPage());

        await tester.enterText(
          find.byKey(const Key('builder-name')),
          'Core & Legs',
        );
        await tester.enterText(
          find.byKey(const Key('builder-exercise-name-0')),
          'plank',
        );
        await tester.pump();

        // Tap the "Plank" suggestion chip.
        final chip = find.byKey(const Key('builder-suggest-0-Plank'));
        expect(chip, findsOneWidget);
        await tester.tap(chip);
        await tester.pump();

        // Timed mode ("Seconds") and Core muscle group are automatically selected!
        expect(find.byKey(const Key('builder-seconds-0')), findsOneWidget);

        await tester.tap(find.byKey(const Key('save-custom-workout')));
        await tester.pumpAndSettle();

        final saved = controller.workouts.single.exercises.single;
        expect(saved.name, 'Plank');
        expect(saved.muscleGroup, 'Core');
        expect(saved.isTimed, isTrue);
        expect(saved.durationSeconds, 30);
      },
    );
  });
}
