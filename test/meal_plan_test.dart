import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/meal_plan.dart';

Map<String, dynamic> plan({List<Map<String, dynamic>>? meals}) => {
  'meals': meals ?? [meal()],
  'totalKcal': 2000,
  'note': 'Stay hydrated.',
};

Map<String, dynamic> meal({List<Map<String, dynamic>>? items}) => {
  'label': 'Breakfast',
  'items': items ?? [item()],
};

Map<String, dynamic> item({
  int kcal = 400,
  double proteinG = 25,
  double carbsG = 40,
  double fatG = 15,
}) => {
  'name': 'Oatmeal',
  'kcal': kcal,
  'proteinG': proteinG,
  'carbsG': carbsG,
  'fatG': fatG,
};

void main() {
  test('parses a valid plan', () {
    final parsed = AiMealParser.parse(plan(), targetKcal: 2000);

    expect(parsed.meals.single.label, 'Breakfast');
    expect(parsed.meals.single.items.single.name, 'Oatmeal');
    expect(parsed.meals.single.items.single.kcal, 400);
    expect(parsed.targetKcal, 2000);
    expect(parsed.totalKcal, 400);
    expect(parsed.note, 'Stay hydrated.');
  });

  test('drops empty meals, throws when nothing remains', () {
    final parsed = AiMealParser.parse(
      plan(
        meals: [
          meal(items: []),
          meal(),
        ],
      ),
      targetKcal: 2000,
    );
    expect(parsed.meals.single.label, 'Breakfast');

    expect(
      () => AiMealParser.parse(plan(meals: []), targetKcal: 2000),
      throwsFormatException,
    );
  });

  test('clamps out-of-range numbers', () {
    final parsed = AiMealParser.parse(
      plan(
        meals: [
          meal(items: [item(kcal: 9999, proteinG: 1000, fatG: -3)]),
        ],
      ),
      targetKcal: 2000,
    );
    final parsedItem = parsed.meals.single.items.single;

    expect(parsedItem.kcal, 1500);
    expect(parsedItem.proteinG, 300);
    expect(parsedItem.fatG, 0);
  });

  test('plan JSON round-trips', () {
    final original = AiMealParser.parse(plan(), targetKcal: 2000);
    final decoded = MealPlan.fromJson(original.toJson());

    expect(decoded.meals.single.items.single.kcal, 400);
    expect(decoded.targetKcal, 2000);
  });

  test('target calories adjust by goal', () {
    expect(NutritionTargets.targetKcal(tdee: 2400, goal: 'Strength'), 2700);
    expect(NutritionTargets.targetKcal(tdee: 2400, goal: 'Cardio'), 2000);
    expect(NutritionTargets.targetKcal(tdee: 2400, goal: 'Mobility'), 2400);
    expect(NutritionTargets.targetKcal(tdee: 1000, goal: 'Cardio'), 1200);
  });

  test('protein target scales with weight and goal', () {
    expect(NutritionTargets.proteinG(weightKg: 80, goal: 'Strength'), 144);
    expect(NutritionTargets.proteinG(weightKg: 80, goal: 'Cardio'), 112);
    expect(NutritionTargets.proteinG(weightKg: 80, goal: null), 96);
  });

  test('photo analysis parses dishes into a meal', () {
    final parsed = AiMealParser.parsePhoto({
      'dishes': [item(kcal: 350)],
      'note': 'Portions are approximate.',
    });

    expect(parsed.meal.label, 'Detected dishes');
    expect(parsed.meal.items.single.kcal, 350);
    expect(parsed.note, 'Portions are approximate.');
  });

  test('photo analysis with no dishes throws', () {
    expect(
      () => AiMealParser.parsePhoto({'dishes': [], 'note': ''}),
      throwsFormatException,
    );
  });

  test('macro split stays inside the calorie target', () {
    const target = 2000;
    const protein = 150;
    final fat = NutritionTargets.fatG(target);
    final carbs = NutritionTargets.carbsG(
      targetKcal: target,
      proteinG: protein,
    );
    final kcal = protein * 4 + carbs * 4 + fat * 9;

    expect((kcal - target).abs(), lessThan(50));
  });

  test('meal split sums to 100% with and without a snack', () {
    for (final meals in [3, 4]) {
      final split = AiMealPrompt.split(meals);
      expect(split.length, meals);
      expect(split.values.fold(0, (a, b) => a + b), 100);
    }
    expect(
      AiMealPrompt.user(targetKcal: 2000, proteinG: 120, meals: 3),
      contains('Lunch 40% (~800 kcal)'),
    );
  });

  test('malformed AI and cached JSON raise FormatException, not TypeError', () {
    expect(
      () => AiMealParser.parse({'meals': 'oops'}, targetKcal: 2000),
      throwsFormatException,
    );
    expect(
      () => AiMealParser.parsePhoto({'dishes': 42}),
      throwsFormatException,
    );
    expect(
      () => MealPlan.fromJson({'date': 7, 'meals': []}),
      throwsFormatException,
    );
    final meal = Meal.fromJson({
      'label': 'Lunch',
      'items': [
        {'kcal': 300},
        {'name': 'Rice', 'kcal': 'many'},
      ],
    });
    expect(meal.items.single.name, 'Rice');
    expect(meal.items.single.kcal, 0);
  });

  test('plan cache keeps settings and reads the legacy bare-plan format', () {
    final original = AiMealParser.parse(plan(), targetKcal: 2000);
    final legacy = MealPlanCache.decode(jsonEncode(original.toJson()));
    expect(legacy.plan!.targetKcal, 2000);
    expect(legacy.mealCount, 3);

    final cache = MealPlanCache(
      plan: original,
      preferences: 'vegetarian',
      mealCount: 4,
    );
    final decoded = MealPlanCache.decode(jsonEncode(cache.toJson()));
    expect(decoded.plan!.meals.single.label, 'Breakfast');
    expect(decoded.preferences, 'vegetarian');
    expect(decoded.mealCount, 4);

    expect(MealPlanCache.decode('not json').plan, isNull);
    expect(MealPlanCache.decode('[1, 2]').mealCount, 3);
  });

  test('portion edits rescale kcal and macros', () {
    const meal = Meal(
      label: 'Lunch',
      items: [
        MealItem(name: 'Rice', kcal: 200, carbsG: 44),
        MealItem(name: 'Chicken', kcal: 165, proteinG: 31),
      ],
    );

    final doubled = meal.withKcal(730);
    expect(doubled.kcal, 730);
    expect(doubled.proteinG, closeTo(62, 0.01));
    expect(doubled.carbsG, closeTo(88, 0.01));
    expect(meal.withKcal(101).kcal, 101);

    const empty = Meal(
      label: 'x',
      items: [MealItem(name: 'Tea', kcal: 0)],
    );
    expect(empty.withKcal(30).kcal, 30);
  });
}
