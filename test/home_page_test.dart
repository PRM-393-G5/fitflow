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
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:prm/features/nutrition/presentation/log_meal_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Meal meal(String type, String name, int kcal) => Meal(
  label: type,
  items: [MealItem(name: name, kcal: kcal, proteinG: 20, carbsG: 30)],
);

/// Pumps the whole shell (Home is its first tab) with [log] as the food
/// log; [profile] adds height, age and a weight so there are targets.
Future<AppController> pumpHome(
  WidgetTester tester, {
  FoodLog? log,
  bool profile = false,
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
      ..age = 30;
    await controller.addWeightEntry(70, DateTime.now());
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
      ..add(DateTime.now(), meal('Breakfast', 'Oats', 420))
      ..add(DateTime.now(), meal('Lunch', 'Rice bowl', 820));
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
    final log = FoodLog()..add(DateTime.now(), meal('Lunch', 'Rice', 500));
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
