import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/features/achievements/presentation/achievements_page.dart';
import 'package:prm/features/metrics/presentation/body_metrics_page.dart';
import 'package:prm/features/progress/presentation/progress_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutSession session(
  int daysAgo, {
  String workoutId = 'w1',
  String name = 'Legs',
  int sets = 3,
}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo, 9);
  return WorkoutSession(
    id: 'session-$daysAgo-$workoutId',
    workoutId: workoutId,
    workoutName: name,
    startedAt: day.subtract(const Duration(minutes: 30)),
    completedAt: day,
    completedSets: sets,
    volumeKg: 500,
  );
}

Future<AppController> pumpPage(
  WidgetTester tester,
  Widget page, {
  List<WorkoutSession> sessions = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true}',
    'sessions_v1': jsonEncode([for (final s in sessions) s.toJson()]),
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
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('history pages long lists and labels form checks', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [
        session(
          0,
          workoutId: 'form-check',
          name: 'Plank Form Check (45s)',
          sets: 45,
        ),
        for (var i = 1; i <= 24; i++) session(i),
      ],
    );

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.textContaining('45 s hold'),
      300,
      scrollable: scrollable,
    );
    expect(find.textContaining('45 s hold'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('history-show-more')),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Show more (5 left)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-show-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-show-more')), findsNothing);
  });

  testWidgets('session detail deletes after confirmation', (tester) async {
    final controller = await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [session(1)],
    );

    await tester.scrollUntilVisible(
      find.text('Legs'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-session')));
    await tester.pumpAndSettle();

    expect(controller.sessions, isEmpty);
    expect(find.text('Session detail'), findsNothing);
  });

  testWidgets('achievements show progress toward locked badges', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const AchievementsPage(),
      sessions: [session(0), session(1), session(2)],
    );

    expect(find.text('3/5'), findsOneWidget); // Regular
    expect(find.text('Ten tonne club'), findsOneWidget);
  });

  testWidgets('weight log accepts a comma and rejects out-of-range input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The test font renders forui's calendar header wider than on device.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError?.call(details);
      }
    };
    final controller = await pumpPage(tester, const BodyMetricsPage());

    Future<void> enterWeight(String text) async {
      await tester.ensureVisible(find.byKey(const Key('log-weight')));
      await tester.tap(find.byKey(const Key('log-weight')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weight-input')), text);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    await enterWeight('5');
    expect(find.textContaining('between 20 and 400 kg'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.weightEntries, isEmpty);

    await enterWeight('70,5');
    expect(controller.weightEntries.single.weightKg, 70.5);
    expect(find.text('70.5 kg'), findsWidgets);
    FlutterError.onError = onError;
  });
}
