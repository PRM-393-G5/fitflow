import 'dart:convert';

import 'package:clock/clock.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/meal_plan.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/features/metrics/presentation/body_metrics_page.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:prm/features/nutrition/presentation/log_meal_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Meal meal(String type, String name, int kcal) => Meal(
  label: type,
  items: [MealItem(name: name, kcal: kcal, proteinG: 20, carbsG: 30)],
);

/// Pumps the whole shell (Home is its first tab) with [log] as the food
/// log; [profile] adds height, [age] and a weight so there are targets
/// (none under 18).
Future<AppController> pumpHome(
  WidgetTester tester, {
  FoodLog? log,
  bool profile = false,
  int age = 30,
  List<Workout> workouts = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true,"goal":"Strength"}',
    if (log != null) 'food_log_v1': jsonEncode(log.toJson()),
    if (workouts.isNotEmpty)
      'workouts_v1': jsonEncode([for (final w in workouts) w.toJson()]),
  });
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences, templates: const []),
    preferences,
  );
  await controller.load();
  if (profile) {
    controller
      ..heightCm = 175
      ..age = age;
    await controller.addWeightEntry(70, clock.now());
  }
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
  return controller;
}

Finder inNutrition(Finder finder) => find.descendant(
  of: find.byKey(const Key('home-nutrition')),
  matching: finder,
);

void main() {
  testWidgets('shows what was eaten today, per meal', (tester) async {
    final log = FoodLog()
      ..add(clock.now(), meal('Breakfast', 'Oats', 420))
      ..add(clock.now(), meal('Lunch', 'Rice bowl', 820));
    await pumpHome(tester, log: log);

    expect(inNutrition(find.text('1,240')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-meal-Breakfast')),
        matching: find.text('420 kcal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home-meal-Dinner')),
        matching: find.text('Add'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asks for the body profile when there is no target', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(
      find.byKey(const Key('home-nutrition-profile-needed')),
      findsOneWidget,
    );
    expect(inNutrition(find.textContaining('kcal to go')), findsNothing);
  });

  testWidgets('measures today against the calorie target', (tester) async {
    final log = FoodLog()..add(clock.now(), meal('Lunch', 'Rice', 500));
    await pumpHome(tester, log: log, profile: true);

    expect(
      find.byKey(const Key('home-nutrition-profile-needed')),
      findsNothing,
    );
    expect(inNutrition(find.textContaining('kcal to go')), findsOneWidget);
  });

  testWidgets('a meal tile opens the log page for that meal', (tester) async {
    await pumpHome(tester);

    final tile = find.byKey(const Key('home-meal-Dinner'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final page = tester.widget<LogMealPage>(find.byType(LogMealPage));
    expect(page.type, 'Dinner');
  });

  testWidgets('"See all" switches to the Nutrition tab', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-open-nutrition')));
    await tester.pumpAndSettle();

    // The Nutrition page's own summary is now on screen.
    expect(find.byKey(const Key('nutrition-eaten')).hitTestable(), findsOne);
  });

  testWidgets('greets by the time of day', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 12, 8)), () async {
      await pumpHome(tester);
      expect(find.text('Good morning'), findsOneWidget);
    });
    await withClock(Clock.fixed(DateTime(2026, 11, 12, 20)), () async {
      await pumpHome(tester);
      expect(find.text('Good evening'), findsOneWidget);
    });
  });

  testWidgets('puts nutrition first and training in one compact card', (
    tester,
  ) async {
    await pumpHome(tester, workouts: const [_workout]);

    final nutrition = tester.getTopLeft(
      find.byKey(const Key('home-nutrition')),
    );
    final training = tester.getTopLeft(find.byKey(const Key('home-training')));
    expect(nutrition.dy, lessThan(training.dy));

    final card = find.byKey(const Key('home-training'));
    expect(
      find.descendant(of: card, matching: find.text('Full Body Foundation')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('home-quick-start')),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Edit weekly schedule'), findsOneWidget);
    // Week progress, streak, minutes and the form check sit in one row
    // of chips instead of separate cards.
    expect(find.byKey(const Key('home-weekly-goal')), findsOneWidget);
    expect(find.byKey(const Key('home-streak')), findsOneWidget);
    expect(find.byKey(const Key('home-minutes')), findsOneWidget);
    expect(find.byKey(const Key('open-squat-form-check-home')), findsOneWidget);
    expect(find.text('Today’s workout'), findsNothing);
  });

  testWidgets('a meal saved from its tile is logged to today', (tester) async {
    final controller = await pumpHome(tester);

    final tile = find.byKey(const Key('home-meal-Dinner'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(LogMealPage)))
        .pop(meal('Dinner', 'Pho', 550));
    await tester.pumpAndSettle();

    expect(controller.foodLog.mealsOn(clock.now()).single.label, 'Dinner');
    expect(
      find.descendant(of: tile, matching: find.text('550 kcal')),
      findsOneWidget,
    );
  });

  testWidgets('meal tiles can be opened by a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester);

    await tester.ensureVisible(find.byKey(const Key('home-meal-Dinner')));
    tester.semantics.tap(find.semantics.byLabel('Log Dinner'));
    await tester.pumpAndSettle();

    expect(find.byType(LogMealPage), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the profile prompt opens body metrics', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-nutrition-profile-needed')));
    await tester.pumpAndSettle();

    expect(find.byType(BodyMetricsPage), findsOneWidget);
  });

  testWidgets('under 18 shows what was eaten without a target', (tester) async {
    final log = FoodLog()..add(clock.now(), meal('Lunch', 'Rice', 500));
    await pumpHome(tester, log: log, profile: true, age: 16);

    expect(inNutrition(find.text('500')), findsOneWidget);
    expect(inNutrition(find.text('kcal eaten')), findsOneWidget);
    expect(inNutrition(find.textContaining('kcal to go')), findsNothing);
    expect(
      find.byKey(const Key('home-nutrition-profile-needed')),
      findsNothing,
    );
  });

  testWidgets('a rest day links nowhere and offers no Start', (tester) async {
    final controller = await pumpHome(tester, workouts: const [_workout]);
    await controller.setScheduleDay(clock.now().weekday, AppController.restDay);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-rest-day')), findsOneWidget);
    expect(find.byKey(const Key('home-view-details')), findsNothing);
    expect(find.byKey(const Key('home-quick-start')), findsNothing);
  });

  testWidgets('after today'
      's workout the plan can be opened again', (tester) async {
    final controller = await pumpHome(tester, workouts: const [_workout]);
    final now = clock.now();
    await controller.addSession(
      WorkoutSession(
        id: 's1',
        workoutId: _workout.id,
        workoutName: _workout.name,
        startedAt: now,
        completedAt: now,
        completedSets: 3,
        volumeKg: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-done-today')), findsOneWidget);
    expect(find.byKey(const Key('home-quick-start')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Train again')), findsOneWidget);
  });

  testWidgets('Start is disabled for a plan without sets', (tester) async {
    await pumpHome(tester, workouts: [_workout.copyWith(exercises: const [])]);

    final start = tester.widget<FButton>(
      find.byKey(const Key('home-quick-start')),
    );
    expect(start.onPress, isNull);
  });

  testWidgets('the week chip picks a goal when there is no schedule', (
    tester,
  ) async {
    await pumpHome(tester, workouts: const [_workout]);

    final chip = find.byKey(const Key('home-weekly-goal'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('4 workouts per week'), findsOneWidget);
  });

  testWidgets('moves to the new day when the app resumes after midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 12, 23, 50);
    await withClock(Clock(() => now), () async {
      final log = FoodLog()..add(now, meal('Dinner', 'Pho', 550));
      await pumpHome(tester, log: log);
      final tile = find.byKey(const Key('home-meal-Dinner'));
      expect(
        find.descendant(of: tile, matching: find.text('550 kcal')),
        findsOneWidget,
      );

      now = DateTime(2026, 11, 13, 7);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: tile, matching: find.text('Add')),
        findsOneWidget,
      );
    });
  });
}

const _workout = Workout(
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
