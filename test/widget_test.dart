import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browses catalog and starts the main workout flow', (
    tester,
  ) async {
    const workout = Workout(
      id: 'w1',
      name: 'Full Body Foundation',
      duration: Duration(minutes: 30),
      level: 'Beginner',
      category: 'Strength',
      description: '',
      exercises: [
        Exercise(
          id: 'squat',
          name: 'Bodyweight Squat',
          muscleGroup: 'Legs',
          sets: 3,
          reps: 10,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_v1': '{"done":true}',
      'workouts_v1': jsonEncode([workout.toJson()]),
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
        child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to move?'), findsOneWidget);

    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Full Body Foundation'), findsOneWidget);

    await tester.tap(find.text('Full Body Foundation'));
    await tester.pumpAndSettle();
    expect(find.text('Bodyweight Squat'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('start-workout')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect(find.text('Set 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.byKey(const Key('skip-rest')), findsOneWidget);
  });
}
