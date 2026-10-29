import 'dart:convert';

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:patrol/patrol.dart';
import 'package:prm/domain/body_metrics.dart';
import 'package:prm/domain/meal_plan.dart';
import 'package:prm/features/metrics/presentation/body_metrics_page.dart';
import 'package:prm/features/profile/presentation/profile_page.dart';
import 'package:prm/features/profile/presentation/reminders_page.dart';
import 'package:prm/features/workouts/presentation/weight_units.dart';

import 'support/e2e.dart';

void main() {
  e2eTest('changes goal & level, units and theme from Profile', ($) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    await cloud.keepMeta();
    final controller = controllerOf($);
    await openTab($, 'Profile');

    // Goal & level: shown on Profile and synced to the account.
    await $(const Key('profile-goal')).tap();
    await $(FDialog).$('Stay mobile').tap();
    await $(FDialog).$('Advanced').tap();
    await $(const Key('goal-save')).tap();
    await $.pumpAndTrySettle();
    expect(
      $(const Key('profile-goal')).containing('Stay mobile · Advanced'),
      findsOneWidget,
    );
    await cloud.waitForMeta('the new goal', (meta) {
      final onboarding = meta['onboarding'] as Map?;
      return onboarding?['goal'] == 'Mobility' &&
          onboarding?['level'] == 'Advanced';
    });

    // Pounds: the switch, the latest weigh-in and the weight form follow.
    final units = $(FTile).containing('Metric units');
    await reveal($, units);
    expect(units.containing('Kilograms (kg)'), findsOneWidget);
    await units.$(FSwitch).tap();
    expect(units.containing('Pounds (lb)'), findsOneWidget);
    final weights = controller.weightEntries;
    await reveal($, $(const Key('profile-card')));
    if (weights.isNotEmpty) {
      final lb = WeightUnits.format(weights.last.weightKg, false);
      expect(
        // "172 cm · 22 y · 160.5 lb · Moderate"
        $(const Key('profile-card'))
            .containing(RegExp('(^|· )${RegExp.escape(lb)} lb ·')),
        findsOneWidget,
      );
    }
    await $(const Key('profile-card')).tap();
    await $(BodyMetricsPage).waitUntilVisible();
    if (weights.isNotEmpty) {
      final lb = weights.last.weightKg / BodyMetrics.kgPerLb;
      expect(
        $(const Key('metrics-current'))
            .containing('${lb.toStringAsFixed(1)} lb'),
        findsOneWidget,
      );
    }
    await $(const Key('log-weight')).tap();
    await $('Select').tap();
    expect($('Weight (lb)'), findsOneWidget);
    await $(FDialog).$('Cancel').tap();
    await goBack($);
    await reveal($, units);
    await units.$(FSwitch).tap();
    expect(units.containing('Kilograms (kg)'), findsOneWidget);

    // Theme: Dark and Light override the phone's setting.
    Brightness brightness() =>
        Theme.of($.tester.element(find.byType(ProfilePage))).brightness;
    for (final (mode, expected) in [
      ('Dark', Brightness.dark),
      ('Light', Brightness.light),
      ('System', null),
    ]) {
      await reveal($, $('Theme'));
      await $('Theme').tap();
      // The menu's item, not the tile's current value.
      await $(mode).last.tap();
      await $.pumpAndTrySettle();
      expect(controller.themeMode.name, mode.toLowerCase());
      if (expected != null) expect(brightness(), expected);
    }
  });

  e2eTest('schedules weekly reminders on the chosen days', ($) async {
    await launchSignedIn($);
    final controller = controllerOf($);
    await openTab($, 'Profile');
    final tile = $(FTile).containing('Workout reminders');
    await reveal($, tile);
    expect(tile.containing('Off'), findsOneWidget);

    await tile.tap();
    await $(RemindersPage).waitUntilVisible();
    final enable = $(FTile).containing('Enable reminders').$(FSwitch);
    await enable.tap();
    // Android asks for notification permission the first time.
    await grantPermissionIfAsked($);
    await waitUntil(
      $,
      'reminders to turn on',
      () => controller.reminderEnabled,
      timeout: const Duration(seconds: 10),
    );
    // Mon, Wed and Fri at 18:00 by default; swap Monday for Saturday.
    await _expectReminders($, {1, 3, 5});
    await $(FButton).containing('Mon').tap();
    await $(FButton).containing('Sat').tap();
    await _expectReminders($, {3, 5, 6});
    await goBack($);
    expect(tile.containing('18:00 · Wed, Fri, Sat'), findsOneWidget);

    // Off: nothing stays scheduled.
    await tile.tap();
    await $(RemindersPage).waitUntilVisible();
    await enable.tap();
    await _expectReminders($, {});
    await goBack($);
    expect(tile.containing('Off'), findsOneWidget);
  });

  e2eTest('Sync brings in a meal logged elsewhere; export and import', (
    $,
  ) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    final controller = controllerOf($);
    final dish = uniqueName('E2E remote dish');
    final now = DateTime.now();
    final id = '${FoodLog.dayKey(now)}:e2e${now.millisecondsSinceEpoch}';
    addTearDown(() => cloud.delete('meals', id));
    // Another device logs a lunch after this phone's sign-in sync.
    await cloud.put('meals', id, {
      'label': 'Lunch',
      'items': [
        {'name': dish, 'kcal': 222, 'proteinG': 11, 'carbsG': 22, 'fatG': 3},
      ],
    });
    await openTab($, 'Nutrition');
    expect($(dish), findsNothing);

    await openTab($, 'Profile');
    final sync = $(const Key('profile-sync'));
    await reveal($, sync);
    final syncedBefore = controller.lastSyncedAt;
    await sync.tap();
    await waitUntil(
      $,
      'Sync now',
      () => !controller.syncing && controller.lastSyncedAt != syncedBefore,
    );
    expect(controller.lastSyncFailed, isFalse);
    expect(sync.containing('Synced just now'), findsOneWidget);

    await openTab($, 'Nutrition');
    expect(loggedMeal($, 'Lunch', dish).containing('222 kcal'), findsOneWidget);
    // Removing it here removes it on the server too.
    await openMealActions($, 'Lunch', dish);
    await $(const Key('nutrition-meal-remove')).tap();
    await waitUntilGone($, $(dish), 'the meal to leave the log');
    await cloud.waitForDeleted('meals', id);

    // Export: a FitFlow backup of this account, copied to the clipboard.
    await openTab($, 'Profile');
    await reveal($, $('Export data'));
    await $('Export data').tap();
    expect($(RegExp('"app": "FitFlow"')), findsOneWidget);
    await $(FDialog).$('Copy').tap();
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    final backup = jsonDecode(copied!.text!) as Map<String, dynamic>;
    expect(backup['app'], 'FitFlow');
    expect(backup['sessions'], hasLength(controller.sessions.length));
    await $(FDialog).$('Close').tap();
    await waitUntilGone($, $(FDialog), 'the export dialog to close');

    // Import: anything but a FitFlow export is refused, nothing changes.
    final sessions = controller.sessions.length;
    await $('Import data').tap();
    final field = $(FDialog).$(FTextField);
    await field.enterText('{oops');
    await $(FDialog).$('Import').tap();
    expect($('Not valid JSON.'), findsOneWidget);
    await field.enterText('{"app": "FitFlow"}');
    await $(FDialog).$('Import').tap();
    expect($('Not a FitFlow export.'), findsOneWidget);
    await $(FDialog).$('Cancel').tap();
    expect(controller.sessions, hasLength(sessions));
  });
}

/// Waits until exactly [days] (1 = Monday) have a weekly reminder
/// scheduled on the phone.
Future<void> _expectReminders(PatrolIntegrationTester $, Set<int> days) =>
    waitUntil($, 'weekly reminders on exactly the days $days', () async {
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      final scheduled = {
        for (final request in pending)
          if (request.id >= 1 && request.id <= 7) request.id,
      };
      return scheduled.length == days.length && scheduled.containsAll(days);
    }, timeout: const Duration(seconds: 10));
