import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
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
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true}',
    'sessions_v1': jsonEncode([for (final s in sessions) s.toJson()]),
    ...prefs,
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

    // The page previews 5 sessions; the full, paged history is one tap away.
    final seeAll = find.byKey(const Key('progress-history-all'));
    await tester.scrollUntilVisible(
      seeAll,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('See all (25)'), findsOneWidget);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
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

  testWidgets('form checks alone show records but no workout stats', (
    tester,
  ) async {
    final day = DateTime.now().subtract(const Duration(days: 1));
    await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [
        WorkoutSession(
          id: 'form-1',
          workoutId: 'form-check',
          workoutName: 'Push-up Form Check (15 reps)',
          startedAt: day.subtract(const Duration(minutes: 2)),
          completedAt: day,
          completedSets: 1,
          volumeKg: 0,
          exercises: const [
            Exercise(
              id: 'pushup',
              name: 'Push-up',
              muscleGroup: 'Chest',
              sets: 1,
              reps: 15,
              performedSets: [SetEntry(amount: 15)],
            ),
          ],
        ),
      ],
    );

    expect(find.text('0 weeks'), findsOneWidget); // longest streak
    final records = find.text('Personal records');
    await tester.scrollUntilVisible(
      records,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(records, findsOneWidget);
    expect(find.text('15 reps'), findsOneWidget);
    // The best/longest session tiles need a real workout.
    expect(find.text('best session'), findsNothing);
    expect(find.text('longest session'), findsNothing);
  });

  testWidgets('lift records show heaviest, estimated 1RM and best set', (
    tester,
  ) async {
    final day = DateTime.now().subtract(const Duration(days: 1));
    await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [
        WorkoutSession(
          id: 'bench-day',
          workoutId: 'w1',
          workoutName: 'Upper',
          startedAt: day.subtract(const Duration(minutes: 40)),
          completedAt: day,
          completedSets: 2,
          volumeKg: 1040,
          exercises: const [
            Exercise(
              id: 'bench',
              name: 'Bench Press',
              muscleGroup: 'Chest',
              sets: 2,
              reps: 10,
              performedSets: [
                SetEntry(amount: 10, weightKg: 60), // 1RM 80, volume 600
                SetEntry(amount: 4, weightKg: 70), // heaviest, 1RM ≈ 79.3
                SetEntry(amount: 15, weightKg: 30), // too long to estimate
              ],
            ),
          ],
        ),
      ],
    );

    final tile = find.textContaining('best set 10 × 60 kg');
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tile, findsOneWidget);
    expect(find.textContaining('est. 1RM 80 kg'), findsOneWidget);
    expect(find.text('70 kg'), findsOneWidget);
  });

  testWidgets('a mistyped set can be fixed from session detail', (
    tester,
  ) async {
    final day = DateTime.now().subtract(const Duration(days: 1));
    final controller = await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [
        WorkoutSession(
          id: 'typo',
          workoutId: 'w1',
          workoutName: 'Push day',
          startedAt: day.subtract(const Duration(minutes: 40)),
          completedAt: day,
          completedSets: 3,
          volumeKg: 7200,
          exercises: const [
            Exercise(
              id: 'bench',
              name: 'Bench Press',
              muscleGroup: 'Chest',
              sets: 3,
              reps: 10,
              performedSets: [
                SetEntry(amount: 10, weightKg: 60),
                SetEntry(amount: 10, weightKg: 600), // meant 60
                SetEntry(amount: 10, weightKg: 60),
              ],
            ),
          ],
        ),
        session(3, workoutId: 'form-check', name: 'Squat Form Check (9 reps)'),
      ],
    );

    await tester.scrollUntilVisible(
      find.text('Push day'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Push day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-session')));
    await tester.pumpAndSettle();

    // Invalid input is refused with the field marked.
    await tester.enterText(find.byKey(const Key('edit-amount-0-1')), '0');
    await tester.tap(find.byKey(const Key('save-session-edit')));
    await tester.pumpAndSettle();
    expect(find.text('At least 1'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('edit-amount-0-1')), '10');
    await tester.enterText(find.byKey(const Key('edit-weight-0-1')), '60');
    await tester.tap(find.byKey(const Key('save-session-edit')));
    await tester.pumpAndSettle();

    final saved = controller.sessions.firstWhere((item) => item.id == 'typo');
    expect(saved.exercises.single.performedSets.map((set) => set.weightKg), [
      60,
      60,
      60,
    ]);
    expect(saved.volumeKg, 1800);
    // Back on the detail page, which shows the corrected session.
    expect(find.text('Session detail'), findsOneWidget);
    expect(find.text('1800 kg'), findsOneWidget);

    // Form checks have nothing to edit.
    await tester.tap(find.byType(FHeaderAction).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Squat Form Check'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('Squat Form Check'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-session')), findsNothing);
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

  testWidgets('overview leads with this week and the weight trend', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      sessions: [session(0)],
      prefs: {
        'weekly_goal_v1': 4,
        'body_weights_v1': jsonEncode([
          {
            'date': today.subtract(const Duration(days: 20)).toIso8601String(),
            'weightKg': 74.0,
          },
          {'date': today.toIso8601String(), 'weightKg': 72.5},
        ]),
      },
    );

    expect(find.text(' / 4 sessions'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('progress-week-done'))).data,
      '1',
    );
    expect(find.byKey(const Key('progress-achievements')), findsOneWidget);
    expect(find.byKey(const Key('progress-share')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('progress-weight')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('72.5 kg'), findsOneWidget);
    final since = today.subtract(const Duration(days: 20));
    final dd = since.day.toString().padLeft(2, '0');
    final mm = since.month.toString().padLeft(2, '0');
    expect(find.text('−1.5 kg since $dd/$mm'), findsOneWidget);
    // One session: no "See all" for history.
    expect(find.byKey(const Key('progress-history-all')), findsNothing);
  });

  testWidgets('weight card never shows an old log as a recent trend', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Future<void> pumpWeights(List<(int, double)> daysAgoKg) => pumpPage(
      tester,
      const FScaffold(child: ProgressPage()),
      prefs: {
        'body_weights_v1': jsonEncode([
          for (final (daysAgo, kg) in daysAgoKg)
            {
              'date': today.subtract(Duration(days: daysAgo)).toIso8601String(),
              'weightKg': kg,
            },
        ]),
      },
    );
    Future<String> detail() async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('progress-weight')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      return tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('progress-weight')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .join(' | ');
    }

    // Last weighed four months ago: no trend, just when.
    await pumpWeights([(150, 74), (120, 72.5)]);
    expect(await detail(), contains('logged'));
    expect(await detail(), isNot(contains('since')));

    // A change that rounds to zero reads ±0, not −0.
    await pumpWeights([(10, 72.5), (0, 72.46)]);
    expect(await detail(), contains('±0 kg since'));
  });
}
