import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/meal_plan.dart';

Meal meal(String name, int kcal, {double protein = 0}) => Meal(
  label: 'Manual entry',
  items: [MealItem(name: name, kcal: kcal, proteinG: protein)],
);

void main() {
  test('keeps each day separate across midnight', () {
    final log = FoodLog();
    final lateNight = DateTime(2026, 4, 8, 23, 50);
    final nextMorning = DateTime(2026, 4, 9, 0, 10);

    log.add(lateNight, meal('Noodles', 500));
    log.add(nextMorning, meal('Toast', 200));

    expect(
      log.mealsOn(DateTime(2026, 4, 8)).single.items.single.name,
      'Noodles',
    );
    expect(log.mealsOn(DateTime(2026, 4, 9)).single.items.single.name, 'Toast');
    expect(log.mealsOn(DateTime(2026, 4, 10)), isEmpty);
  });

  test('prunes days older than the retention window', () {
    final now = DateTime(2026, 4, 30, 9);
    final log = FoodLog()
      ..add(DateTime(2026, 4, 1), meal('Kept', 100)) // 30th day back
      ..add(DateTime(2026, 3, 31), meal('Dropped', 100))
      ..add(now, meal('Today', 100));

    log.prune(now);

    expect(log.days.keys, containsAll(['2026-04-01', '2026-04-30']));
    expect(log.days.containsKey('2026-03-31'), isFalse);
  });

  test('round-trips history and reads the legacy one-day format', () {
    final log = FoodLog()
      ..add(DateTime(2026, 4, 8), meal('Phở bò', 450, protein: 30))
      ..add(DateTime(2026, 4, 9), meal('Salad', 250));
    final decoded = FoodLog.decode(jsonEncode(log.toJson()));
    expect(decoded.days.length, 2);
    expect(decoded.mealsOn(DateTime(2026, 4, 8)).single.proteinG, 30);

    final legacy = FoodLog.decode(
      jsonEncode({
        'date': DateTime(2026, 4, 7, 12).toIso8601String(),
        'meals': [meal('Rice', 300).toJson()],
      }),
    );
    expect(legacy.mealsOn(DateTime(2026, 4, 7)).single.kcal, 300);

    expect(
      FoodLog.decode('{"days": {"bad": 1, "2026-04-01": "x"}}').days,
      isEmpty,
    );
    expect(FoodLog.decode('garbage').days, isEmpty);
  });

  test('edits, removals, and totals', () {
    final day = DateTime(2026, 4, 8);
    final log = FoodLog()
      ..add(day, meal('Eggs', 150, protein: 12))
      ..add(day, meal('Oats', 300, protein: 10));

    log.replace(day, 0, log.mealsOn(day).first.withKcal(300));
    final totals = FoodLog.totals(log.mealsOn(day));
    expect(totals.kcal, 600);
    expect(totals.proteinG, closeTo(34, 0.01));

    log.removeAt(day, 0);
    log.removeAt(day, 0);
    expect(log.days, isEmpty);
  });
}
