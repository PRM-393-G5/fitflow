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

    final eggs = log.entriesOn(day).first;
    final before = log.entriesOn(day).last;
    expect(log.replace(eggs.id, eggs.meal.withKcal(300))?.id, eggs.id);
    final totals = FoodLog.totals(log.mealsOn(day));
    expect(totals.kcal, 600);
    expect(totals.proteinG, closeTo(34, 0.01));
    // Untouched entries keep their identity (sync relies on it).
    expect(identical(log.entriesOn(day).last, before), isTrue);

    expect(log.remove(eggs.id), isNotNull);
    expect(log.remove(eggs.id), isNull, reason: 'already gone');
    expect(log.replace(eggs.id, eggs.meal), isNull);
    log.remove(before.id);
    expect(log.days, isEmpty);
  });

  test('entry ids are day-prefixed, unique and in logging order', () {
    final day = DateTime(2026, 4, 8);
    final at = DateTime(2026, 4, 8, 12);
    final log = FoodLog();
    final first = log.add(day, meal('Eggs', 150), now: at);
    final second = log.add(day, meal('Oats', 300), now: at);
    expect(first.id, startsWith('2026-04-08:'));
    expect(second.id, isNot(first.id));
    expect(FoodEntry.isId(first.id) && FoodEntry.isId(second.id), isTrue);
    expect(log.mealsOn(day).map((m) => m.items.single.name), ['Eggs', 'Oats']);

    final decoded = FoodLog.decode(jsonEncode(log.toJson()));
    expect(decoded.entriesOn(day).map((e) => e.id), [first.id, second.id]);
  });

  test('older formats get per-device ids in logging order', () {
    final raw = jsonEncode({
      'version': 2,
      'days': {
        '2026-04-08': [
          for (var i = 0; i < 11; i++) meal('Dish $i', 100).toJson(),
          {'label': 'Lunch', 'items': <Object>[]},
        ],
      },
    });
    expect(FoodLog.isCurrentFormat(raw), isFalse);
    final log = FoodLog.decode(raw, nonce: 'phone');
    final ids = log.entries.map((e) => e.id).toList();
    expect(ids.first, '2026-04-08:0-phone-0000');
    expect(ids, hasLength(11), reason: 'a meal without dishes is dropped');
    // 11+ meals keep their order (zero-padded index).
    expect(log.mealsOn(DateTime(2026, 4, 8)).last.items.single.name, 'Dish 10');
    // Another device's old log never produces the same ids.
    final other = FoodLog.decode(raw, nonce: 'tablet');
    expect(
      other.entries.map((e) => e.id).toSet().intersection(ids.toSet()),
      isEmpty,
    );
    expect(FoodLog.isCurrentFormat(jsonEncode(log.toJson())), isTrue);
  });

  test('picks the meal slot from the time of day', () {
    DateTime at(int h, int m) => DateTime(2026, 10, 16, h, m);
    expect(defaultMealType(at(7, 30)), 'Breakfast');
    expect(defaultMealType(at(10, 59)), 'Breakfast');
    expect(defaultMealType(at(11, 0)), 'Lunch');
    expect(defaultMealType(at(15, 30)), 'Snack');
    expect(defaultMealType(at(18, 0)), 'Dinner');
    expect(defaultMealType(at(23, 59)), 'Dinner');
  });

  test('maps labels to slots, unknown ones to Other', () {
    Meal labeled(String label) => Meal(label: label, items: const []);
    expect(mealTypeOf(labeled('Lunch')), 'Lunch');
    expect(mealTypeOf(labeled(' snack ')), 'Snack');
    expect(mealTypeOf(labeled('Manual entry')), otherMealType);
    expect(mealTypeOf(labeled('Detected dishes')), otherMealType);
  });
}
