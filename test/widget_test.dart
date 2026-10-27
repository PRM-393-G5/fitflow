import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:prm/features/workouts/presentation/schedule_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browses catalog and starts the main workout flow', (
    tester,
  ) async {
    const workout = Workout(
      id: 'w1',
      name: 'Full Body Foundation',
      duration: Duration(minutes: 30),
      level: 'Beginner',
      category: 'Strength',
      description: '',
      exercises: [
        Exercise(
          id: 'squat',
          name: 'Bodyweight Squat',
          muscleGroup: 'Legs',
          sets: 3,
          reps: 10,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_v1': '{"done":true}',
      'workouts_v1': jsonEncode([workout.toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child!),
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to move?'), findsOneWidget);

    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Full Body Foundation'), findsOneWidget);

    await tester.tap(find.text('Full Body Foundation'));
    await tester.pumpAndSettle();
    // The muscle map sits above the exercise list.
    expect(find.text('Muscles worked'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bodyweight Squat'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Bodyweight Squat'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('start-workout')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect(find.text('Set 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.byKey(const Key('skip-rest')), findsOneWidget);
    // Flush the short FTappable press timers (100 ms) left after the tap.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('nutrition tab logs a manual meal for today', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child!),
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nutrition'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('nutrition-log-manual')));
    await tester.tap(find.byKey(const Key('nutrition-log-manual')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-name')),
        matching: find.byType(EditableText),
      ),
      'Phở bò',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-kcal')),
        matching: find.byType(EditableText),
      ),
      '450',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-meal-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Phở bò'), findsOneWidget);
    expect(find.textContaining('450'), findsWidgets);
    expect(find.textContaining('eaten today'), findsOneWidget);
    expect(preferences.getString('food_log_v1'), contains('Phở bò'));
  });

  testWidgets("workouts shows today's slot of the weekly schedule", (
    tester,
  ) async {
    const workout = Workout(
      id: 'w1',
      name: 'Leg Day',
      duration: Duration(minutes: 30),
      level: 'Beginner',
      category: 'Strength',
      description: '',
      exercises: [],
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_v1': '{"done":true}',
      'workouts_v1': jsonEncode([workout.toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();
    final weekday = DateTime.now().weekday;

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child!),
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    final today = find.byKey(const Key('workouts-today'));
    expect(
      find.text('Today · ${SchedulePage.dayNames[weekday - 1]}'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: today, matching: find.text('Nothing planned')),
      findsOneWidget,
    );

    await controller.setScheduleDay(weekday, workout.id);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: today, matching: find.text('Leg Day')),
      findsOneWidget,
    );

    await controller.setScheduleDay(weekday, AppController.restDay);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: today, matching: find.text('Rest day')),
      findsOneWidget,
    );
  });

  testWidgets('filters plans by muscle group', (tester) async {
    Workout plan(String id, String name, String exercise) => Workout(
      id: id,
      name: name,
      duration: const Duration(minutes: 30),
      level: 'Beginner',
      category: 'Strength',
      description: '',
      exercises: [
        Exercise(
          id: '$id-1',
          name: exercise,
          muscleGroup: '',
          sets: 3,
          reps: 10,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_v1': '{"done":true}',
      'workouts_v1': jsonEncode([
        plan('legs', 'Leg Day', 'Goblet Squat').toJson(),
        plan('arms', 'Arm Day', 'Biceps Curl').toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child!),
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Leg Day'), findsOneWidget);
    expect(find.text('Arm Day'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-workout-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Show 2 plans'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-Arms')));
    await tester.pumpAndSettle();
    expect(find.text('Show 1 plan'), findsOneWidget);
    // Nothing is an advanced arms plan: the button says so.
    await tester.tap(find.byKey(const Key('filter-Advanced')));
    await tester.pumpAndSettle();
    expect(find.text('No plans match'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-Advanced')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-workout-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Leg Day'), findsNothing);
    expect(find.text('Arm Day'), findsOneWidget);
    expect(find.text('1 of 2 plans • Arms'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-workout-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Leg Day'), findsOneWidget);
  });
}
