import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/workout_app.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browses catalog and starts the main workout flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences),
      preferences,
    );
    await controller.load();

    await tester.pumpWidget(WorkoutApp(controller: controller));
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
