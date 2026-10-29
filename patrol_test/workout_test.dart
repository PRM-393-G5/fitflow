import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:prm/features/progress/presentation/session_detail_page.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';

import 'support/e2e.dart';

/// A built-in plan every account has (served by `GET /templates`).
const _plan = 'Full Body Foundation';

void main() {
  e2eTest('logs a workout, syncs it, and deletes it from history', ($) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    final before = {for (final doc in await cloud.docs('sessions')) doc['id']};

    await openTab($, 'Workouts');
    await $(const Key('workout-search')).enterText(_plan);
    await $.pumpAndTrySettle();
    await $(_plan).last.tap();
    await $(const Key('start-workout')).scrollTo();
    await $(const Key('start-workout')).tap();
    await $(ActiveWorkoutPage).waitUntilVisible();

    await $(const Key('complete-set')).tap();
    // The first rest asks for notification permission (rest-over alerts).
    await grantPermissionIfAsked($);
    expect($(RegExp(r'^1 of \d+ sets$')), findsOneWidget);

    await $(const Key('finish-header')).tap();
    await $('Finish workout?').waitUntilVisible();
    await $('Finish').last.tap();
    await waitUntilGone($, $(ActiveWorkoutPage), 'the workout to close');

    // The session reached the server…
    final session = await cloud.waitForDoc(
      'sessions',
      'the new $_plan session',
      (doc) => !before.contains(doc['id']) && doc['workoutName'] == _plan,
    );
    final id = session['id'] as String;
    addTearDown(() => cloud.delete('sessions', id));
    expect(session['completedSets'], 1);

    // …and tops the history, newest first.
    await openTab($, 'Progress');
    await $(const Key('progress-tab-history')).tap();
    await $(_plan).first.tap();
    await $(SessionDetailPage).waitUntilVisible();
    // The newest entry is this test's session, not a real one.
    final completedAt = DateTime.parse(session['completedAt'] as String);
    expect($(_dateTime(completedAt)), findsOneWidget);
    expect($(FTile).containing('Sets completed').containing('1'), findsOne);

    await $(const Key('delete-session')).tap();
    await $(const Key('confirm-delete-session')).tap();
    await waitUntilGone($, $(SessionDetailPage), 'the session to close');
    await cloud.waitForDeleted('sessions', id);
  });
}

/// The session detail's "dd/mm/yyyy hh:mm" stamp, in local time.
String _dateTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
