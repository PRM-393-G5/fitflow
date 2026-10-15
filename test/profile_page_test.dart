import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/profile/presentation/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppController> pumpProfile(
  WidgetTester tester,
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true,"goal":"Strength","level":"Intermediate"}',
    ...prefs,
  });
  final preferences = await SharedPreferences.getInstance();
  const plan = Workout(
    id: 'upper',
    name: 'Upper',
    exercises: [
      Exercise(id: 'bench', name: 'Bench', muscleGroup: 'Chest', sets: 3),
    ],
    duration: Duration(minutes: 40),
    level: 'Intermediate',
    category: 'Strength',
    description: '',
  );
  final controller = AppController(
    LocalWorkoutRepository(preferences, templates: const [plan]),
    preferences,
  );
  await controller.load();
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: FToaster(child: child!),
        ),
        home: const FScaffold(child: ProfilePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('groups settings and shows the values set', (tester) async {
    await pumpProfile(tester, {
      'body_profile_v1':
          '{"heightCm":172,"age":22,"isMale":true,"activityLevel":2}',
      'body_weights_v1': jsonEncode([
        {'date': DateTime(2026, 10, 16).toIso8601String(), 'weightKg': 72.5},
      ]),
      'schedule_v1': '{"1":"upper","3":"upper","2":"rest"}',
      'reminder_v1': '{"enabled":true,"minutes":1080,"days":[5,1,3]}',
    });

    for (final label in ['TRAINING', 'PREFERENCES', 'DATA', 'ACCOUNT']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('172 cm · 22 y · 72.5 kg · Moderate'), findsOneWidget);
    expect(find.text('Build muscle · Intermediate'), findsOneWidget);
    expect(find.text('2 workout days · Mon, Wed'), findsOneWidget);
    expect(find.text('18:00 · Mon, Wed, Fri'), findsOneWidget);
    expect(find.text('Guest · data stays on this device'), findsOneWidget);
  });

  testWidgets('edits goal and level in place', (tester) async {
    final controller = await pumpProfile(tester, {});
    expect(find.text('Off'), findsOneWidget, reason: 'reminders off');
    expect(find.text('No plan assigned yet'), findsOneWidget);
    expect(find.text('Add height, age and weight'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lose fat'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(controller.goal, 'Cardio');
    expect(controller.level, 'Advanced');
    expect(find.text('Lose fat · Advanced'), findsOneWidget);
  });

  testWidgets('the goal picker skips calorie targets under 18', (tester) async {
    await pumpProfile(tester, {
      'body_profile_v1':
          '{"heightCm":160,"age":16,"isMale":false,"activityLevel":1}',
    });

    await tester.tap(find.byKey(const Key('profile-goal')));
    await tester.pumpAndSettle();

    expect(find.text('Plans and suggestions follow these.'), findsOneWidget);
  });

  test('relative sync times', () {
    final now = DateTime(2026, 10, 16, 12);
    expect(ProfilePage.ago(now, now: now), 'just now');
    expect(
      ProfilePage.ago(now.subtract(const Duration(minutes: 5)), now: now),
      '5 min ago',
    );
    expect(
      ProfilePage.ago(now.subtract(const Duration(hours: 3)), now: now),
      '3 h ago',
    );
    expect(ProfilePage.ago(DateTime(2026, 10, 2), now: now), 'on 02/10');
    expect(ProfilePage.ago(DateTime(2025, 10, 16), now: now), 'on 16/10/2025');
  });
}
