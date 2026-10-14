import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/meal_plan.dart';
import 'package:prm/features/nutrition/presentation/nutrition_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Meal meal(String name, int kcal) => Meal(
  label: 'Manual entry',
  items: [MealItem(name: name, kcal: kcal, proteinG: 20)],
);

Future<AppController> pumpNutrition(
  WidgetTester tester,
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true,"goal":"Strength"}',
    ...values,
  });
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences),
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
        home: const FScaffold(child: NutritionPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('shows earlier days and reloads when the user data changes', (
    tester,
  ) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final log = FoodLog()
      ..add(now, meal('Toast', 200))
      ..add(yesterday, meal('Ramen', 600));
    final controller = await pumpNutrition(tester, {
      'food_log_v1': jsonEncode(log.toJson()),
    });

    expect(find.text('Toast'), findsOneWidget);
    expect(find.text('Ramen'), findsNothing);

    // The strip shows each day's kcal.
    final yesterdayCell = find.byKey(
      Key('nutrition-day-${FoodLog.dayKey(yesterday)}'),
    );
    expect(
      find.descendant(of: yesterdayCell, matching: find.text('600')),
      findsOneWidget,
    );
    await tester.tap(yesterdayCell);
    await tester.pumpAndSettle();
    expect(find.text('Ramen'), findsOneWidget);
    expect(find.textContaining('eaten on yesterday'), findsOneWidget);

    // Signing out / switching accounts wipes the keys and bumps dataEpoch.
    await controller.clearLocalData();
    await tester.pumpAndSettle();
    expect(find.text('Ramen'), findsNothing);
    expect(find.text('Toast'), findsNothing);
    expect(find.textContaining('eaten today'), findsOneWidget);
  });

  testWidgets('restores preferences and flags a plan built for an old target', (
    tester,
  ) async {
    final plan = MealPlan(
      date: DateTime.now(),
      targetKcal: 1500,
      meals: [meal('Oatmeal', 400)],
    );
    await pumpNutrition(tester, {
      'body_profile_v1':
          '{"heightCm":175,"age":30,"isMale":true,"activityLevel":1}',
      'body_weights_v1': jsonEncode([
        {'date': DateTime.now().toIso8601String(), 'weightKg': 75.0},
      ]),
      'meal_plan_v1': jsonEncode(
        MealPlanCache(plan: plan, preferences: 'vegan', mealCount: 4).toJson(),
      ),
    });

    // Options stay folded, summarised on their toggle.
    expect(find.textContaining('vegan'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('nutrition-plan-options')));
    await tester.tap(find.byKey(const Key('nutrition-plan-options')));
    await tester.pumpAndSettle();
    expect(find.text('vegan'), findsOneWidget);
    expect(find.byKey(const Key('nutrition-target-changed')), findsOneWidget);
    expect(find.textContaining('Build muscle'), findsOneWidget);
  });

  testWidgets('shows eaten vs target and why a deficit is held back', (
    tester,
  ) async {
    await pumpNutrition(tester, {
      'onboarding_v1': '{"done":true,"goal":"Cardio"}',
      // 45 kg at 165 cm: BMI 16.5, TDEE ≈ 1,643 kcal.
      'body_profile_v1':
          '{"heightCm":165,"age":25,"isMale":false,"activityLevel":1}',
      'body_weights_v1': jsonEncode([
        {'date': DateTime.now().toIso8601String(), 'weightKg': 45.0},
      ]),
      'food_log_v1': jsonEncode(
        (FoodLog()
              ..add(DateTime.now(), meal('Toast', 200))
              ..add(
                DateTime.now().subtract(const Duration(days: 1)),
                meal('Rice', 1900),
              ))
            .toJson(),
      ),
    });

    expect(find.text('/ 1,643 kcal eaten today'), findsOneWidget);
    expect(find.text('20 / 54 g'), findsOneWidget); // maintenance protein
    expect(find.byKey(const Key('nutrition-target-limit')), findsOneWidget);
    expect(find.textContaining('BMI is under 18.5'), findsOneWidget);
    expect(find.byKey(const Key('nutrition-disclaimer')), findsOneWidget);

    // Past days aren't judged against today's target.
    final now = DateTime.now();
    await tester.tap(
      find.byKey(
        Key(
          'nutrition-day-${FoodLog.dayKey(DateTime(now.year, now.month, now.day - 1))}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('kcal eaten on yesterday'), findsOneWidget);
    expect(find.textContaining('/ 1,643'), findsNothing);
  });

  testWidgets('groups the log into meal slots and logs into a chosen slot', (
    tester,
  ) async {
    final log = FoodLog()
      ..add(
        DateTime.now(),
        const Meal(
          label: 'Breakfast',
          items: [MealItem(name: 'Pho', kcal: 450)],
        ),
      )
      ..add(DateTime.now(), meal('Old entry', 300));
    await pumpNutrition(tester, {'food_log_v1': jsonEncode(log.toJson())});

    for (final type in mealTypes) {
      expect(find.text(type), findsOneWidget);
    }
    // Legacy labels land in "Other" with the original label shown.
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Manual entry'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('nutrition-add-Dinner')));
    await tester.tap(find.byKey(const Key('nutrition-add-Dinner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-add-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-name')),
        matching: find.byType(EditableText),
      ),
      'Rice',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-kcal')),
        matching: find.byType(EditableText),
      ),
      '500',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-meal-submit')));
    await tester.pumpAndSettle();

    final saved = FoodLog.decode(
      (await SharedPreferences.getInstance()).getString('food_log_v1'),
    ).mealsOn(DateTime.now());
    expect(saved.last.label, 'Dinner');
    expect(saved.last.items.single.name, 'Rice');
  });

  testWidgets('picks a day from the month calendar', (tester) async {
    final now = DateTime.now();
    final earlier = DateTime(now.year, now.month, now.day - 20);
    final log = FoodLog()..add(earlier, meal('Bun cha', 580));
    await pumpNutrition(tester, {'food_log_v1': jsonEncode(log.toJson())});

    await tester.tap(find.byKey(const Key('nutrition-calendar')));
    await tester.pumpAndSettle();
    if (earlier.month != now.month) {
      await tester.tap(find.byKey(const Key('calendar-prev-month')));
      await tester.pumpAndSettle();
    }
    final cell = find.descendant(
      of: find.byType(FDialog),
      matching: find.byKey(Key('nutrition-day-${FoodLog.dayKey(earlier)}')),
    );
    expect(
      find.descendant(of: cell, matching: find.text('580')),
      findsOneWidget,
    );
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('Bun cha'), findsOneWidget);
  });

  testWidgets('logs several dishes as one meal, re-using recent foods', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final log = FoodLog()
      ..add(
        yesterday,
        const Meal(
          label: 'Lunch',
          items: [MealItem(name: 'Grilled pork', kcal: 320, proteinG: 25)],
        ),
      );
    await pumpNutrition(tester, {'food_log_v1': jsonEncode(log.toJson())});
    await tester.ensureVisible(find.byKey(const Key('nutrition-add-Lunch')));
    await tester.tap(find.byKey(const Key('nutrition-add-Lunch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-add-manual')));
    await tester.pumpAndSettle();

    Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field('log-meal-name'), 'Rice');
    await tester.enterText(field('log-meal-kcal'), '260');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-meal-add-item')));
    await tester.pumpAndSettle();

    // Typing filters recent foods; one tap adds the dish with its macros.
    await tester.enterText(field('log-meal-name'), 'pork');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-Grilled pork')));
    await tester.pumpAndSettle();
    expect(find.text('580 kcal'), findsOneWidget);
    expect(find.text('Log to Lunch'), findsOneWidget);
    await tester.tap(find.byKey(const Key('log-meal-submit')));
    await tester.pumpAndSettle();

    final saved = FoodLog.decode(
      (await SharedPreferences.getInstance()).getString('food_log_v1'),
    ).mealsOn(DateTime.now());
    expect(saved.single.label, 'Lunch');
    expect(saved.single.items.map((item) => item.name), [
      'Rice',
      'Grilled pork',
    ]);
    expect(saved.single.items.last.proteinG, 25);
  });

  testWidgets('a recent food keeps the dish being typed; bad macros show', (
    tester,
  ) async {
    final log = FoodLog()
      ..add(
        DateTime.now().subtract(const Duration(days: 1)),
        const Meal(
          label: 'Lunch',
          items: [MealItem(name: 'Pho', kcal: 450)],
        ),
      );
    await pumpNutrition(tester, {'food_log_v1': jsonEncode(log.toJson())});
    await tester.ensureVisible(find.byKey(const Key('nutrition-log-manual')));
    await tester.tap(find.byKey(const Key('nutrition-log-manual')));
    await tester.pumpAndSettle();

    Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    );
    // A complete dish typed in the form (its name also filters recents).
    await tester.enterText(field('log-meal-name'), 'Pho');
    await tester.enterText(field('log-meal-kcal'), '260');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('recent-Pho')));
    await tester.tap(find.byKey(const Key('recent-Pho')));
    await tester.pumpAndSettle();
    expect(find.text('710 kcal'), findsOneWidget, reason: 'typed + recent');

    await tester.tap(find.byKey(const Key('log-meal-macros')));
    await tester.pumpAndSettle();
    await tester.enterText(field('log-meal-name'), 'Egg');
    await tester.enterText(field('log-meal-kcal'), '70');
    await tester.enterText(find.byType(EditableText).at(2), 'abc');
    await tester.pumpAndSettle();
    // Folding the macros keeps them open while one is invalid.
    await tester.tap(find.byKey(const Key('log-meal-macros')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Macros must be numbers'), findsOneWidget);
  });
}
