import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/body_metrics.dart';
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

/// Plain targets of [kcal], for prompt wording tests.
DailyTargets fixed(int kcal, {TargetPhase phase = TargetPhase.maintenance}) => (
  kcal: kcal,
  proteinG: 120,
  fatG: NutritionTargets.fatG(kcal),
  carbsG: NutritionTargets.carbsG(targetKcal: kcal, proteinG: 120),
  phase: phase,
  limit: null,
  safetyMinKcal: 1500,
  minMenuKcal: (kcal * 0.9).round(),
  maxMenuKcal: (kcal * 1.1).round(),
);

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

  group('daily targets', () {
    // TDEE for the profile, so each case starts from the real number.
    DailyTargets daily({
      required String? goal,
      required double kg,
      required double cm,
      required int age,
      bool male = true,
      int activity = 2,
    }) => NutritionTargets.daily(
      tdee: BodyMetrics.tdee(
        weightKg: kg,
        heightCm: cm,
        age: age,
        isMale: male,
        activityLevel: activity,
      ),
      goal: goal,
      weightKg: kg,
      heightCm: cm,
      age: age,
      isMale: male,
    );

    test('adjust by a share of TDEE, not a flat amount', () {
      // 80 kg, 180 cm, 30 y, moderate: TDEE ≈ 2,759 kcal.
      final lose = daily(goal: 'Cardio', kg: 80, cm: 180, age: 30);
      final build = daily(goal: 'Strength', kg: 80, cm: 180, age: 30);
      final keep = daily(goal: 'Mobility', kg: 80, cm: 180, age: 30);

      expect(lose.kcal, 2345); // −15%
      expect(build.kcal, 3035); // +10%
      expect(keep.kcal, 2759);
      expect(lose.limit, isNull);
      expect(lose.phase, TargetPhase.deficit);
      expect(build.phase, TargetPhase.surplus);
      expect(keep.phase, TargetPhase.maintenance);
      // A big TDEE caps the deficit at 500 kcal.
      expect(
        NutritionTargets.daily(
          tdee: 3600,
          goal: 'Cardio',
          weightKg: 100,
          heightCm: 190,
          age: 30,
          isMale: true,
        ).kcal,
        3100,
      );
    });

    test('no deficit for an underweight BMI', () {
      // 45 kg, 165 cm: BMI 16.5. TDEE ≈ 1,643 kcal (light activity).
      final lose = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );
      final build = daily(
        goal: 'Strength',
        kg: 45,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );

      expect(lose.kcal, 1643);
      expect(lose.limit, TargetLimit.underweight);
      // No deficit means no deficit-level protein either: 1.2 × 45.
      expect(lose.proteinG, 54);
      // Gaining is still fine.
      expect(build.kcal, 1808);
      expect(build.limit, isNull);
      expect(build.proteinG, 72); // 1.6 × 45
    });

    test('no targets under 18', () {
      // Callers check BodyMetrics.adultFormulasApply first; asking anyway
      // is a bug, not a silent null.
      for (final goal in ['Cardio', 'Strength', 'Mobility', null]) {
        expect(
          () => daily(goal: goal, kg: 50, cm: 160, age: 17, male: false),
          throwsArgumentError,
        );
      }
      expect(
        daily(goal: 'Cardio', kg: 50, cm: 160, age: 18, male: false).kcal,
        greaterThan(0),
      );
    });

    test('a deficit stops at the floor, or never starts', () {
      // 70 y man, 60 kg, 175 cm, sedentary: TDEE ≈ 1,619; −15% would be
      // 1,376, so the deficit stops at 1,500 — 119 kcal under.
      final man = daily(goal: 'Cardio', kg: 60, cm: 175, age: 70, activity: 0);
      // 57 kg at 170 cm (BMI 19.7): TDEE 1,545, 45 kcal above his floor —
      // the deficit shrinks to those 45 kcal, protein barely above
      // maintenance.
      final close = daily(
        goal: 'Cardio',
        kg: 57,
        cm: 170,
        age: 70,
        activity: 0,
      );
      // 60 y woman, 45 kg, 150 cm: TDEE ≈ 1,112, under her 1,200 floor —
      // the target is held at the floor, with no deficit.
      final woman = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 150,
        age: 60,
        male: false,
        activity: 0,
      );

      expect(man.kcal, 1500);
      expect(man.limit, TargetLimit.floor);
      expect(man.phase, TargetPhase.deficit);
      // 1.2 g/kg + 0.6 × 119/300 ≈ 1.44 g/kg.
      expect(man.proteinG, 86);
      expect(close.kcal, 1500);
      expect(close.limit, TargetLimit.floor);
      expect(close.phase, TargetPhase.deficit);
      expect(close.proteinG, 74); // 1.29 g/kg
      expect(woman.kcal, 1200);
      expect(woman.limit, TargetLimit.lowMaintenance);
      expect(woman.phase, TargetPhase.maintenance);
      expect(woman.proteinG, 54); // 1.2 × 45
    });

    test('nothing jumps as maintenance crosses the floor', () {
      DailyTargets at(double tdee) => NutritionTargets.daily(
        tdee: tdee,
        goal: 'Cardio',
        weightKg: 60,
        heightCm: 175,
        age: 40,
        isMale: true,
      );

      // The floor, where −15% meets the floor, and where −15% meets the
      // 500 kcal cap.
      for (final edge in [1500.0, 1500 / 0.85, 500 / 0.15]) {
        final below = at(edge - 0.1);
        final above = at(edge + 0.1);
        expect((above.kcal - below.kcal).abs(), lessThanOrEqualTo(1));
        expect((above.proteinG - below.proteinG).abs(), lessThanOrEqualTo(1));
      }
    });

    test('menus must total within ±10%, never under a safe minimum', () {
      final lose = daily(goal: 'Cardio', kg: 80, cm: 180, age: 30);
      final keep = daily(goal: 'Mobility', kg: 80, cm: 180, age: 30);
      final floor = daily(
        goal: 'Cardio',
        kg: 60,
        cm: 175,
        age: 70,
        activity: 0,
      );
      final underweight = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );

      expect((lose.minMenuKcal, lose.maxMenuKcal), (2111, 2580));
      expect((keep.minMenuKcal, keep.maxMenuKcal), (2483, 3035));
      // At the floor the target itself is the minimum.
      expect((floor.minMenuKcal, floor.maxMenuKcal), (1500, 1650));
      // A ruled-out deficit can't come back through the menu.
      expect(underweight.minMenuKcal, underweight.kcal);
    });

    test('an underweight BMI never gets a deficit menu, whatever the goal', () {
      // 45 kg, 165 cm: BMI 16.5, TDEE ≈ 1,643.
      for (final goal in ['Mobility', null, 'Strength']) {
        final targets = daily(
          goal: goal,
          kg: 45,
          cm: 165,
          age: 25,
          male: false,
          activity: 1,
        );
        expect(targets.minMenuKcal, 1643, reason: '$goal');
      }
    });

    test('a maintenance estimate under the floor is lifted to it', () {
      // 60 y woman, 45 kg, 150 cm: maintenance ≈ 1,112 is below 1,200, so
      // the target — and the menu minimum — is 1,200, whatever the goal.
      for (final goal in ['Mobility', 'Cardio', null]) {
        final targets = daily(
          goal: goal,
          kg: 45,
          cm: 150,
          age: 60,
          male: false,
          activity: 0,
        );
        expect(targets.kcal, 1200, reason: goal);
        expect(targets.limit, TargetLimit.lowMaintenance, reason: goal);
        expect(targets.minMenuKcal, 1200, reason: goal);
      }
    });

    test('protein follows the phase and is capped at BMI 25 weight', () {
      expect(daily(goal: 'Cardio', kg: 80, cm: 180, age: 30).proteinG, 144);
      expect(daily(goal: 'Strength', kg: 80, cm: 180, age: 30).proteinG, 128);
      expect(daily(goal: null, kg: 80, cm: 180, age: 30).proteinG, 96);
      // 130 kg at 180 cm (BMI 40) counts as 81 kg, the BMI-25 weight.
      expect(daily(goal: 'Cardio', kg: 130, cm: 180, age: 30).proteinG, 146);
    });

    test('nothing clamps a surplus below maintenance', () {
      // A big athlete's TDEE is above the old 5,000 kcal ceiling.
      final build = NutritionTargets.daily(
        tdee: 5026,
        goal: 'Strength',
        weightKg: 150,
        heightCm: 200,
        age: 22,
        isMale: true,
      );

      expect(build.kcal, 5326);
      expect(build.limit, isNull);
    });

    test('macros add up to the calorie target, however large', () {
      for (final targets in [
        daily(goal: 'Cardio', kg: 80, cm: 180, age: 30),
        // ≈ 6,235 kcal: carbs past the old 1,000 g cap.
        daily(goal: 'Strength', kg: 200, cm: 195, age: 20, activity: 4),
      ]) {
        final kcal =
            targets.proteinG * 4 + targets.carbsG * 4 + targets.fatG * 9;
        expect((kcal - targets.kcal).abs(), lessThan(10));
      }
    });

    test('the prompt reads the goal through the targets', () {
      String prompt(String goal, DailyTargets targets) =>
          AiMealPrompt.user(targets: targets, meals: 3, goal: goal);
      final underweight = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );
      DailyTargets lowMaintenance(String goal) =>
          daily(goal: goal, kg: 45, cm: 150, age: 60, male: false, activity: 0);
      final floor = daily(
        goal: 'Cardio',
        kg: 60,
        cm: 175,
        age: 70,
        activity: 0,
      );

      // Fat loss without a deficit is maintenance, never "Lose fat".
      for (final targets in [underweight, lowMaintenance('Cardio')]) {
        expect(
          prompt('Cardio', targets),
          allOf(contains('no calorie deficit'), isNot(contains('Lose fat'))),
        );
      }
      // Other goals keep their label when held at the floor.
      expect(
        prompt('Strength', lowMaintenance('Strength')),
        allOf(
          contains('User goal: Build muscle'),
          isNot(contains('no calorie deficit')),
        ),
      );
      expect(prompt('Cardio', floor), contains('do not go below the target'));
    });

    test('the deficit tapers in across BMI 18.5–19.5', () {
      // Woman, 165 cm, 25 y, light activity: BMI 18.5 is ≈ 50.37 kg.
      DailyTargets at(double kg) => daily(
        goal: 'Cardio',
        kg: kg,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );
      final below = at(50.3);
      final above = at(50.4);
      final full = at(53.2); // BMI 19.5+

      expect(below.limit, TargetLimit.underweight);
      expect(below.phase, TargetPhase.maintenance);
      // A 0.1 kg weigh-in no longer swings the target by ~250 kcal.
      expect((above.kcal - below.kcal).abs(), lessThan(20));
      expect((above.proteinG - below.proteinG).abs(), lessThanOrEqualTo(1));
      expect(full.limit, isNull);
      expect(full.phase, TargetPhase.deficit);
    });

    test('an underweight reason survives being lifted to the floor', () {
      // 40 kg, 160 cm (BMI 15.6), 50 y, sedentary: TDEE ≈ 1,187 < 1,200.
      final targets = daily(
        goal: 'Cardio',
        kg: 40,
        cm: 160,
        age: 50,
        male: false,
        activity: 0,
      );

      expect(targets.kcal, 1200);
      expect(targets.limit, TargetLimit.underweight);
    });

    test('a saved menu is unsafe only when under the new minimum', () {
      final lose = daily(goal: 'Cardio', kg: 80, cm: 180, age: 30);
      MealPlan menu(int kcal) => MealPlan(
        date: DateTime(2026, 10, 21),
        targetKcal: lose.kcal,
        meals: [
          Meal(
            label: 'Day',
            items: [MealItem(name: 'Food', kcal: kcal)],
          ),
        ],
      );
      final underweight = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 165,
        age: 25,
        male: false,
        activity: 1,
      );

      // A drift keeps the menu, even one now under the new −10% leeway
      // (the minimum that matters is the safety one); a deficit menu under
      // a no-deficit minimum does not.
      expect(menu(2345).unsafeFor(lose), isFalse);
      expect(menu(2096).unsafeFor(lose), isFalse);
      expect(menu(1400).unsafeFor(underweight), isTrue);
    });

    test('a saved menu is outdated when kcal, protein or goal change', () {
      // At maintenance either way, so the kcal match; protein, goal and
      // limit don't.
      final lose = daily(
        goal: 'Cardio',
        kg: 45,
        cm: 150,
        age: 60,
        male: false,
        activity: 0,
      );
      final keep = daily(
        goal: 'Mobility',
        kg: 45,
        cm: 150,
        age: 60,
        male: false,
        activity: 0,
      );
      final saved = MealPlan(
        date: DateTime(2026, 10, 21),
        targetKcal: lose.kcal,
        meals: const [],
      ).forTargets(lose, 'Cardio');
      final restored = MealPlan.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
      );

      expect(lose.kcal, keep.kcal);
      expect(restored.goal, 'Cardio');
      expect(restored.outdatedFor(lose, 'Cardio'), isFalse);
      expect(restored.outdatedFor(keep, 'Mobility'), isTrue);
      // Older saved menus only knew their kcal.
      expect(
        MealPlan(
          date: DateTime(2026, 10, 21),
          targetKcal: keep.kcal,
          meals: const [],
        ).outdatedFor(keep, 'Mobility'),
        isFalse,
      );
    });
  });

  test('a menu a little out of range is scaled; far off is rejected', () {
    final json = plan(
      meals: [
        meal(items: [item(kcal: 400)]),
        meal(items: [item(kcal: 600)]),
      ],
    );

    // 1,000 kcal against 1,100–1,210: portions scale up 10%.
    final up = AiMealParser.parse(
      json,
      targetKcal: 1100,
      minKcal: 1100,
      maxKcal: 1210,
    );
    expect(up.totalKcal, 1100);
    expect(up.meals.first.kcal, 440); // proportions kept
    // Over the range scales down; inside it is left alone.
    expect(
      AiMealParser.parse(
        json,
        targetKcal: 900,
        minKcal: 810,
        maxKcal: 990,
      ).totalKcal,
      900,
    );
    expect(
      AiMealParser.parse(
        json,
        targetKcal: 1050,
        minKcal: 945,
        maxKcal: 1155,
      ).totalKcal,
      1000,
    );
    // Per-meal rounding can't leave the total under a minimum equal to
    // the target: the last meal takes the drift.
    final threeMeals = plan(
      meals: [
        meal(items: [item(kcal: 400)]),
        meal(items: [item(kcal: 400)]),
        meal(items: [item(kcal: 399)]),
      ],
    );
    expect(
      AiMealParser.parse(
        threeMeals,
        targetKcal: 1200,
        minKcal: 1200,
        maxKcal: 1320,
      ).totalKcal,
      1200,
    );
    // ×1.5 would make "2 eggs" a different dish: rejected for a retry.
    expect(
      () => AiMealParser.parse(
        json,
        targetKcal: 1500,
        minKcal: 1500,
        maxKcal: 1650,
      ),
      throwsFormatException,
    );
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
      AiMealPrompt.user(targets: fixed(2000), meals: 3),
      contains('Lunch 40% (~800 kcal)'),
    );
    // The model gets the goal's label, not the workout category it is
    // stored as.
    expect(
      AiMealPrompt.user(
        targets: fixed(2000, phase: TargetPhase.deficit),
        meals: 3,
        goal: 'Cardio',
      ),
      allOf(contains('User goal: Lose fat'), isNot(contains('Cardio'))),
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
