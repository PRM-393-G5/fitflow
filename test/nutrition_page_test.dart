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

    await tester.tap(find.byKey(const Key('nutrition-prev-day')));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Ramen'), findsOneWidget);
    expect(find.textContaining('eaten on yesterday'), findsOneWidget);

    // Signing out / switching accounts wipes the keys and bumps dataEpoch.
    await controller.clearLocalData();
    await tester.pumpAndSettle();
    expect(find.text('Ramen'), findsNothing);
    expect(find.text('Toast'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
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

    expect(find.text('vegan'), findsOneWidget);
    expect(find.byKey(const Key('nutrition-target-changed')), findsOneWidget);
    expect(find.textContaining('Build muscle'), findsOneWidget);
  });
}
