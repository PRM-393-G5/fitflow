import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/features/nutrition/presentation/nutrition_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppController> controllerWith({double? heightCm, int? age}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_v1': '{"done":true,"goal":"Strength"}',
  });
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences),
    preferences,
  );
  await controller.load();
  controller
    ..heightCm = heightCm
    ..age = age;
  return controller;
}

void main() {
  test(
    'asks for the body profile until height, age and weight are set',
    () async {
      final controller = await controllerWith(heightCm: 175, age: 30);

      final day = todayTargets(controller);

      expect(day.missing, NoTargets.profile);
      expect(day.targets, isNull);
      expect(day.tdee, isNull);
    },
  );

  test('sets no targets under 18, even with a full profile', () async {
    final controller = await controllerWith(heightCm: 165, age: 16);
    await controller.addWeightEntry(55, DateTime.now());

    final day = todayTargets(controller);

    expect(day.missing, NoTargets.minor);
    expect(day.targets, isNull);
  });

  test('derives TDEE and daily targets from a full adult profile', () async {
    final controller = await controllerWith(heightCm: 175, age: 30);
    await controller.addWeightEntry(70, DateTime.now());

    final day = todayTargets(controller);

    expect(day.missing, isNull);
    expect(day.tdee, greaterThan(1500));
    expect(day.targets!.kcal, greaterThan(0));
    expect(day.targets!.proteinG, greaterThan(0));
  });
}
