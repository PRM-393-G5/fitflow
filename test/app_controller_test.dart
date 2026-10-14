import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/data/reminder_service.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const plan = Workout(
  id: 'custom-legs',
  name: 'Legs',
  duration: Duration(minutes: 20),
  level: 'Beginner',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(id: 'squat', name: 'Squat', muscleGroup: 'Legs', sets: 3, reps: 8),
  ],
);

WorkoutSession session(String id) => WorkoutSession(
  id: id,
  workoutId: plan.id,
  workoutName: plan.name,
  startedAt: DateTime(2026, 4, 1, 10),
  completedAt: DateTime(2026, 4, 1, 10, 30),
  completedSets: 3,
  volumeKg: 0,
);

Future<AppController> controllerWith(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences, templates: const []),
    preferences,
  );
  await controller.load();
  return controller;
}

void main() {
  test('a malformed record does not reset settings', () async {
    final controller = await controllerWith({
      'theme_mode': 'dark',
      'unit_system': false,
      'sessions_v1': '[{"id": "broken"}]',
    });
    expect(controller.error, isNull);
    expect(controller.useMetric, isFalse);
    expect(controller.sessions, isEmpty);
  });

  test('a typed age grows with the years since it was entered', () async {
    final now = DateTime.now();
    final controller = await controllerWith({
      'body_profile_v1': jsonEncode({
        'heightCm': 170,
        'age': 17,
        'ageSetAt': DateTime(
          now.year - 2,
          now.month,
          now.day,
        ).toIso8601String(),
      }),
    });

    expect(controller.age, 19);

    await controller.saveBodyProfile(
      heightCm: 170,
      age: 19,
      isMale: false,
      activityLevel: 1,
    );
    final saved = jsonDecode(
      controller.preferences.getString('body_profile_v1')!,
    ) as Map<String, dynamic>;
    expect(saved['age'], 19);
    expect(saved['ageSetAt'], isNotNull);
  });

  test('clearing data resets in-memory user state', () async {
    final controller = await controllerWith({
      'body_profile_v1': jsonEncode({'heightCm': 180, 'age': 30}),
      'onboarding_v1': jsonEncode({'done': true, 'goal': 'Strength'}),
      'schedule_v1': jsonEncode({'1': 'custom-legs'}),
      'food_log_v1': '{}',
    });
    expect(controller.heightCm, 180);
    final epoch = controller.dataEpoch;

    await controller.clearLocalData();

    expect(controller.heightCm, isNull);
    expect(controller.onboardingDone, isFalse);
    expect(controller.goal, isNull);
    expect(controller.schedule, isEmpty);
    expect(controller.dataEpoch, greaterThan(epoch));
    expect(controller.preferences.getString('food_log_v1'), isNull);
  });

  test('deleting a plan clears schedule days that used it', () async {
    final controller = await controllerWith({});
    await controller.saveWorkout(plan);
    await controller.setScheduleDay(1, plan.id);
    await controller.setScheduleDay(2, AppController.restDay);

    await controller.deleteWorkout(plan.id);

    expect(controller.workouts, isEmpty);
    expect(controller.schedule, {2: AppController.restDay});
  });

  test('rest day suggests no workout', () async {
    final controller = await controllerWith({});
    await controller.saveWorkout(plan);
    await controller.setScheduleDay(
      DateTime.now().weekday,
      AppController.restDay,
    );
    expect(controller.suggestedWorkout(), isNull);
  });

  test('one weight entry per calendar day', () async {
    final controller = await controllerWith({});
    await controller.addWeightEntry(70, DateTime(2026, 5, 1, 8));
    await controller.addWeightEntry(71, DateTime(2026, 5, 1, 21));
    expect(controller.weightEntries.single.weightKg, 71);
    expect(controller.weightEntries.single.id, '2026-05-01');
  });

  test('export round-trips through import', () async {
    final source = await controllerWith({});
    await source.setMetric(false);
    await source.saveWorkout(plan);
    await source.addSession(session('s1'));
    await source.addWeightEntry(70, DateTime(2026, 5, 1));
    await source.saveBodyProfile(
      heightCm: 175,
      age: 28,
      isMale: false,
      activityLevel: 2,
    );
    final json = source.exportJson();

    final target = await controllerWith({});
    final count = await target.importJson(json);

    expect(count, 3);
    expect(target.sessions.single.id, 's1');
    expect(target.workouts.single.id, plan.id);
    expect(target.weightEntries.single.weightKg, 70);
    expect(target.heightCm, 175);
    expect(target.isMale, isFalse);
    expect(target.useMetric, isFalse);
  });

  test('import rejects non-FitFlow JSON', () async {
    final controller = await controllerWith({});
    expect(
      () => controller.importJson('{"hello": 1}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => controller.importJson('not json'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rapid reminder day toggles compose', () async {
    final controller = await controllerWith({});
    await Future.wait([
      controller.toggleReminderDay(2),
      controller.toggleReminderDay(4),
      controller.toggleReminderDay(1),
    ]);
    expect(controller.reminderDays, {2, 3, 4, 5});
  });

  test('reminder next instance keeps wall-clock time across DST', () {
    tzdata.initializeTimeZones();
    final berlin = tz.getLocation('Europe/Berlin');
    // Friday before the 2026-03-29 spring-forward change.
    final now = tz.TZDateTime(berlin, 2026, 3, 27, 12);
    final next = ReminderService.nextInstance(now, DateTime.monday, 18, 0);
    expect(next.day, 30);
    expect(next.hour, 18);
    expect(next.minute, 0);
  });
}
