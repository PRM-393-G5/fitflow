import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:patrol/patrol.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/formatting.dart';
import 'package:prm/core/widgets/app_sheet.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/onboarding/presentation/onboarding_page.dart';
import 'package:prm/features/workouts/presentation/schedule_page.dart';
import 'package:prm/features/workouts/presentation/workout_detail_page.dart';

import 'support/e2e.dart';

/// A built-in plan every account has (served by `GET /templates`).
const _plan = 'Full Body Foundation';

void main() {
  e2eTest('a new account answers onboarding, and Home follows its goal', (
    $,
  ) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    await cloud.keepMeta();
    // Make the account look new: onboarding not done, no week planned.
    await cloud.putMeta({
      ...?await cloud.meta(),
      'onboarding': {'done': false, 'goal': null, 'level': null},
      'schedule': <String, String>{},
    });
    await signOut($);
    await signIn($, skipOnboarding: false);
    await $(OnboardingPage).waitUntilVisible();

    // Both answers are needed to start.
    final start = $(FButton).containing('Start training');
    expect(isEnabled($, start), isFalse);
    await $('Build muscle').tap();
    expect(isEnabled($, start), isFalse);
    await $('Intermediate').tap();
    expect(isEnabled($, start), isTrue);
    await start.tap();
    await waitUntilGone($, $(OnboardingPage), 'onboarding to close');

    // Home features a strength plan, at the chosen level when one exists.
    final workouts = controllerOf($).workouts;
    await openTab($, 'Home');
    final shown = await _openHomePlan($);
    expect(shown.category, 'Strength');
    if (workouts.any(
      (w) => w.category == 'Strength' && w.level == 'Intermediate',
    )) {
      expect(shown.level, 'Intermediate');
    }
    await goBack($);

    await openTab($, 'Profile');
    expect(
      $(const Key('profile-goal')).containing('Build muscle · Intermediate'),
      findsOneWidget,
    );
    await cloud.waitForMeta('the onboarding answers', (meta) {
      final onboarding = meta['onboarding'] as Map?;
      return onboarding?['done'] == true &&
          onboarding?['goal'] == 'Strength' &&
          onboarding?['level'] == 'Intermediate';
    });
  });

  e2eTest('plans the week: a plan today, rest tomorrow, then rest today', (
    $,
  ) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    await cloud.keepMeta();
    final controller = controllerOf($);
    final plan = controller.workouts.firstWhere((w) => w.name == _plan);
    final today = DateTime.now().weekday;
    final tomorrow = today % 7 + 1;
    final todayName = SchedulePage.dayNames[today - 1];
    final tomorrowName = SchedulePage.dayNames[tomorrow - 1];

    // From the Workouts tab's "Today" slot, start from an empty week.
    await openTab($, 'Workouts');
    await $(const Key('workouts-open-schedule')).tap();
    await $(SchedulePage).waitUntilVisible();
    for (final day in controller.schedule.keys.toList()..sort()) {
      await _setDay($, day, const Key('schedule-unassigned'));
    }
    expect(controller.schedule, isEmpty);

    await _setDay($, today, Key('schedule-pick-${plan.id}'));
    await _setDay($, tomorrow, const Key('schedule-rest'));
    expect(_day($, '$todayName, today: $_plan'), findsOneWidget);
    expect(_day($, '$tomorrowName: Rest day'), findsOneWidget);
    await goBack($);

    // Every place that shows today agrees.
    await reveal($, $(const Key('workouts-today')));
    expect($(const Key('workouts-today')).containing(_plan), findsOneWidget);
    await openTab($, 'Home');
    expect((await _openHomePlan($)).id, plan.id);
    await goBack($);
    // One planned day makes the weekly goal 1.
    expect($(RegExp(r'^\d+/1$')), findsOneWidget);
    await openTab($, 'Profile');
    expect(
      $(FTile)
          .containing('Weekly schedule')
          .containing('1 workout day · ${weekdayNames[today - 1]}'),
      findsOneWidget,
    );
    await cloud.waitForMeta(
      'the new week',
      (meta) =>
          _sameSchedule(meta['schedule'], {
            '$today': plan.id,
            '$tomorrow': AppController.restDay,
          }) &&
          meta['weeklyGoal'] == 1,
    );

    // Today becomes a rest day, from Home's schedule shortcut.
    await openTab($, 'Home');
    await $(find.bySemanticsLabel('Edit weekly schedule')).tap();
    await $(SchedulePage).waitUntilVisible();
    await _setDay($, today, const Key('schedule-rest'));
    expect(_day($, '$todayName, today: Rest day'), findsOneWidget);
    await goBack($);
    // A workout already done today keeps Home on "Done today".
    if (!$(const Key('home-done-today')).exists) {
      expect($(const Key('home-rest-day')), findsOneWidget);
    }
    await openTab($, 'Workouts');
    expect(
      $(const Key('workouts-today')).containing('Rest day'),
      findsOneWidget,
    );
    await cloud.waitForMeta(
      'today as a rest day',
      (meta) => _sameSchedule(meta['schedule'], {
        '$today': AppController.restDay,
        '$tomorrow': AppController.restDay,
      }),
    );
  });
}

/// Taps the day row for [weekday] on the schedule page and picks [choice]
/// (a plan, rest day or "Not planned") in its sheet.
Future<void> _setDay(PatrolIntegrationTester $, int weekday, Key choice) async {
  await reveal($, $(Key('schedule-day-$weekday')));
  await $(Key('schedule-day-$weekday')).tap();
  // Scroll the sheet, not the page under it.
  await $(choice).scrollTo(
    view: find
        .descendant(
          of: find.byType(AppSheet),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await $(choice).tap();
  await waitUntilGone($, $(AppSheet), 'the day sheet to close');
}

/// A day row of the schedule page, by what it reads out
/// ("Monday, today: Rest day").
PatrolFinder _day(PatrolIntegrationTester $, String label) =>
    $(find.bySemanticsLabel(label));

/// Opens the plan featured on Home ("View details", or "Train again"
/// after today's workout) and returns it.
Future<Workout> _openHomePlan(PatrolIntegrationTester $) async {
  await reveal($, $(const Key('home-view-details')));
  await $(const Key('home-view-details')).tap();
  await $(WorkoutDetailPage).waitUntilVisible();
  return $.tester
      .widget<WorkoutDetailPage>(find.byType(WorkoutDetailPage))
      .workout;
}

bool _sameSchedule(Object? schedule, Map<String, String> expected) =>
    schedule is Map &&
    schedule.length == expected.length &&
    expected.entries.every((entry) => schedule[entry.key] == entry.value);
