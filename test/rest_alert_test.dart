import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/data/reminder_service.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gym_ux_test.dart' show launchPage;

/// Records timer alerts instead of talking to the notification plugin.
class _FakeReminders extends ReminderService {
  final scheduled = <({DateTime at, String title, String body})>[];
  int cancels = 0;

  @override
  Future<void> reschedule({
    required bool enabled,
    required int minutes,
    required Set<int> days,
  }) async {}

  @override
  Future<void> scheduleTimerAlert(
    DateTime at, {
    required String title,
    required String body,
  }) async => scheduled.add((at: at, title: title, body: body));

  @override
  Future<void> cancelTimerAlert() async => cancels++;

  int permissionAsks = 0;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return true;
  }
}

const _plan = Workout(
  id: 'w-rest',
  name: 'Rest Plan',
  duration: Duration(minutes: 20),
  level: 'Beginner',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(
      id: 'bench',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      sets: 3,
      reps: 8,
      restSeconds: 90,
      weightKg: 40,
    ),
  ],
);

void main() {
  testWidgets('a rest running in the background is announced on time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
    final preferences = await SharedPreferences.getInstance();
    final reminders = _FakeReminders();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
      reminders: reminders,
    );
    await controller.load();
    final now = DateTime(2026, 10, 23, 18);

    await launchPage(
      tester,
      controller,
      () => ActiveWorkoutPage(
        workout: _plan,
        controller: controller,
        clock: () => now,
      ),
    );
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(reminders.permissionAsks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(reminders.scheduled, hasLength(1));
    final alert = reminders.scheduled.single;
    expect(alert.at, now.add(const Duration(seconds: 90)));
    expect(alert.title, 'Rest is over');
    expect(alert.body, 'Next: Bench Press, set 2');

    // Back in the app the in-app countdown takes over again.
    final before = reminders.cancels;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(reminders.cancels, before + 1);

    // Leaving the workout drops any alert still pending.
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    Navigator.of(tester.element(find.byType(ActiveWorkoutPage))).pop();
    await tester.pumpAndSettle();
    expect(reminders.cancels, greaterThan(before + 1));
  });

  testWidgets('nothing is announced when no timer is running', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
    final preferences = await SharedPreferences.getInstance();
    final reminders = _FakeReminders();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
      reminders: reminders,
    );
    await controller.load();

    await launchPage(
      tester,
      controller,
      () => ActiveWorkoutPage(workout: _plan, controller: controller),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(reminders.scheduled, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
