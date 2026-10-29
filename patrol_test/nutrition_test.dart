import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:patrol/patrol.dart';
import 'package:prm/core/formatting.dart';
import 'package:prm/domain/meal_plan.dart';
import 'package:prm/features/nutrition/presentation/log_meal_page.dart';

import 'support/e2e.dart';

typedef _Totals = ({int kcal, double proteinG, double carbsG, double fatG});

void main() {
  e2eTest('logs a two-dish meal with macros; the day totals follow', ($) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    final oats = uniqueName('E2E oats');
    final eggs = uniqueName('E2E eggs');
    await openTab($, 'Nutrition');
    final before = _today($);

    await _openLogMeal($, 'Breakfast');
    final submit = $(const Key('log-meal-submit'));
    expect(submit.containing('Log to Breakfast'), findsOneWidget);
    // Nothing to log until a dish has a name and 1–10000 kcal.
    expect(isEnabled($, submit), isFalse);
    await $(const Key('log-meal-name')).enterText(oats);
    expect(isEnabled($, submit), isFalse);
    await $(const Key('log-meal-kcal')).enterText('0');
    expect(isEnabled($, submit), isFalse);
    await $(const Key('log-meal-kcal')).enterText('300');
    expect(isEnabled($, submit), isTrue);
    // A macro that is not a number blocks logging and says why.
    await $(const Key('log-meal-macros')).tap();
    await _macro($, 'Protein g').enterText('abc');
    expect($(_macroError), findsOneWidget);
    expect(isEnabled($, submit), isFalse);
    await _enterMacros($, protein: '10', carbs: '50', fat: '5');
    expect($(_macroError), findsNothing);
    await $(const Key('log-meal-add-item')).tap();

    // A second dish; the footer adds both up.
    await $(const Key('log-meal-name')).enterText(eggs);
    await $(const Key('log-meal-kcal')).enterText('150');
    await _enterMacros($, protein: '12', carbs: '1', fat: '10');
    expect(_footer($, '450 kcal'), findsOneWidget);
    expect($('2 dishes · P 22g · C 51g · F 15g'), findsOneWidget);
    await submit.tap();
    await waitUntilGone($, $(LogMealPage), 'the meal form to close');

    // One Breakfast entry with both dishes; the day grew by the meal.
    expect(
      loggedMeal($, 'Breakfast', oats).containing(eggs).containing('450 kcal'),
      findsOneWidget,
    );
    await _expectTotals($, before, kcal: 450, protein: 22, carbs: 51, fat: 15);

    final meal = await cloud.waitForDoc(
      'meals',
      'the "$oats" meal',
      (doc) => jsonEncode(doc).contains(oats),
    );
    final id = meal['id'] as String;
    addTearDown(() => cloud.delete('meals', id));
    expect(meal['label'], 'Breakfast');
    expect(meal['items'], [
      {'name': oats, 'kcal': 300, 'proteinG': 10, 'carbsG': 50, 'fatG': 5},
      {'name': eggs, 'kcal': 150, 'proteinG': 12, 'carbsG': 1, 'fatG': 10},
    ]);

    await openMealActions($, 'Breakfast', oats);
    await $(const Key('nutrition-meal-remove')).tap();
    await waitUntilGone($, $(oats), 'the meal to leave the log');
    await _expectTotals($, before);
    await cloud.waitForDeleted('meals', id);
  });

  e2eTest('edits a logged meal: portion, slot, and logs it again from '
      'recent foods', ($) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    final soup = uniqueName('E2E soup');
    await openTab($, 'Nutrition');
    final before = _today($);

    await _openLogMeal($, 'Breakfast');
    await $(const Key('log-meal-name')).enterText(soup);
    await $(const Key('log-meal-kcal')).enterText('200');
    await $(const Key('log-meal-macros')).tap();
    await _enterMacros($, protein: '10', carbs: '20', fat: '6');
    await $(const Key('log-meal-submit')).tap();
    await waitUntilGone($, $(LogMealPage), 'the meal form to close');
    final logged = await cloud.waitForDoc(
      'meals',
      'the "$soup" meal',
      (doc) => jsonEncode(doc).contains(soup),
    );
    final id = logged['id'] as String;
    addTearDown(() => cloud.delete('meals', id));

    // 1½ portions: calories and macros scale together.
    await openMealActions($, 'Breakfast', soup);
    await $(const Key('nutrition-meal-edit')).tap();
    await $(FDialog).$('1½×').tap();
    expect($(FDialog).$(FTextField).containing('300'), findsOneWidget);
    await $(FDialog).$('Save').tap();
    await $.pumpAndTrySettle();
    expect(
      loggedMeal($, 'Breakfast', soup).containing('300 kcal'),
      findsOneWidget,
    );
    await _expectTotals($, before, kcal: 300, protein: 15, carbs: 30, fat: 9);
    await cloud.waitForDoc(
      'meals',
      'the 1½ portion',
      (doc) =>
          doc['id'] == id &&
          _item(doc)['kcal'] == 300 &&
          _item(doc)['proteinG'] == 15,
    );

    // Moved to Lunch: the same entry, not a copy.
    await openMealActions($, 'Breakfast', soup);
    await $(const Key('meal-type-Lunch')).tap();
    await $.pumpAndTrySettle();
    expect(loggedMeal($, 'Breakfast', soup), findsNothing);
    expect(loggedMeal($, 'Lunch', soup), findsOneWidget);
    await cloud.waitForDoc(
      'meals',
      'the move to Lunch',
      (doc) => doc['id'] == id && doc['label'] == 'Lunch',
    );

    // Recent foods log it again in one tap, at its edited size.
    await _openLogMeal($, 'Dinner');
    await $(const Key('log-meal-name')).enterText(soup);
    await $(Key('recent-$soup')).scrollTo();
    await $(Key('recent-$soup')).tap();
    expect(_footer($, '300 kcal'), findsOneWidget);
    await $(const Key('log-meal-submit')).tap();
    await waitUntilGone($, $(LogMealPage), 'the meal form to close');
    expect(loggedMeal($, 'Dinner', soup), findsOneWidget);
    expect(loggedMeal($, 'Lunch', soup), findsOneWidget);
    await _expectTotals($, before, kcal: 600, protein: 30, carbs: 60, fat: 18);
    final again = await cloud.waitForDoc(
      'meals',
      'the Dinner "$soup"',
      (doc) =>
          doc['id'] != id &&
          doc['label'] == 'Dinner' &&
          jsonEncode(doc).contains(soup),
    );
    final againId = again['id'] as String;
    addTearDown(() => cloud.delete('meals', againId));
    expect(_item(again)['kcal'], 300);

    for (final (type, mealId) in [('Lunch', id), ('Dinner', againId)]) {
      await openMealActions($, type, soup);
      await $(const Key('nutrition-meal-remove')).tap();
      await waitUntilGone($, loggedMeal($, type, soup), 'the $type "$soup"');
      await cloud.waitForDeleted('meals', mealId);
    }
    await _expectTotals($, before);
  });
}

const _macroError = 'Macros must be numbers between 0 and 1000 g.';

/// Opens the manual meal form from slot [type]'s "+".
Future<void> _openLogMeal(PatrolIntegrationTester $, String type) async {
  await reveal($, $(Key('nutrition-add-$type')));
  await $(Key('nutrition-add-$type')).tap();
  await $(const Key('slot-add-manual')).tap();
  await $(LogMealPage).waitUntilVisible();
}

/// The meal form's macro field labelled [label] ("Protein g"…).
PatrolFinder _macro(PatrolIntegrationTester $, String label) =>
    $(FTextField).containing(label);

Future<void> _enterMacros(
  PatrolIntegrationTester $, {
  required String protein,
  required String carbs,
  required String fat,
}) async {
  await _macro($, 'Protein g').enterText(protein);
  await _macro($, 'Carbs g').enterText(carbs);
  await _macro($, 'Fat g').enterText(fat);
}

/// The meal form's footer showing [text] next to the log button.
PatrolFinder _footer(PatrolIntegrationTester $, String text) =>
    $(Row).containing(const Key('log-meal-submit')).containing(text);

/// The first dish of a meal document, as the API returns it.
Map<String, dynamic> _item(Map<String, dynamic> doc) =>
    Map<String, dynamic>.from((doc['items'] as List).first as Map);

/// Today's totals as the app holds them.
_Totals _today(PatrolIntegrationTester $) =>
    FoodLog.totals(controllerOf($).foodLog.mealsOn(DateTime.now()));

/// Checks the day card shows [before] plus [kcal] and the macros.
Future<void> _expectTotals(
  PatrolIntegrationTester $,
  _Totals before, {
  int kcal = 0,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) async {
  await reveal($, $(const Key('nutrition-eaten')));
  expect(
    $(Row)
        .containing(const Key('nutrition-eaten'))
        .containing(thousands(before.kcal + kcal)),
    findsOneWidget,
    reason: 'kcal eaten today',
  );
  for (final (label, grams) in [
    ('Protein', before.proteinG + protein),
    ('Carbs', before.carbsG + carbs),
    ('Fat', before.fatG + fat),
  ]) {
    expect(
      $(const Key('nutrition-macros'))
          .$(Column)
          .containing(label)
          .containing(RegExp('^${grams.round()}( / \\d+)? g\$')),
      findsOneWidget,
      reason: '$label eaten today',
    );
  }
}
