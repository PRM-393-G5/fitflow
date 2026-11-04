import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/body_metrics.dart';
import 'package:prm/domain/models/body_weight_entry.dart';
import 'package:prm/features/metrics/presentation/body_metrics_page.dart';

import 'support/e2e.dart';

void main() {
  e2eTest('logs today\'s weight, syncs it, and deletes it', ($) async {
    await launchSignedIn($);
    final cloud = Cloud($);
    // One entry per day: logging replaces today's real weigh-in, so keep
    // it and put it back at the end.
    final today = BodyWeightEntry(date: DateTime.now(), weightKg: 0).id;
    final original = await cloud.doc('weights', today);
    addTearDown(() async {
      if (original != null) await cloud.put('weights', today, original);
    });

    await openTab($, 'Progress');
    await $(const Key('progress-weight')).scrollTo();
    await $(const Key('progress-weight')).tap();
    await $(BodyMetricsPage).waitUntilVisible();

    await $(const Key('log-weight')).tap();
    await $('Pick a date').waitUntilVisible();
    await $('Select').tap(); // today is preselected
    await $(const Key('weight-input')).waitUntilVisible();
    final metric = $('Weight (kg)').exists;
    await $(const Key('weight-input')).enterText('88.8');
    await $('Save').tap();
    final row = $(Key('weight-entry-$today'));
    await row.scrollTo();
    expect(row.containing(metric ? '88.8 kg' : '88.8 lb'), findsOneWidget);

    // The new value, not the weigh-in it replaced.
    final kg = metric ? 88.8 : 88.8 * BodyMetrics.kgPerLb;
    await cloud.waitForDoc(
      'weights',
      'today\'s 88.8 weight',
      (doc) =>
          doc['id'] == today &&
          ((doc['weightKg'] as num).toDouble() - kg).abs() < 0.01,
    );

    await row.tap();
    await $(const Key('confirm-delete-weight')).tap();
    await waitUntilGone($, row, 'the weight entry to go');
    await cloud.waitForDeleted('weights', today);
  });
}
