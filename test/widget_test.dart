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
      LocalWorkoutRepository(preferences, templates: const []),
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
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to move?'), findsOneWidget);

    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Full Body Foundation'), findsOneWidget);

    await tester.tap(find.text('Full Body Foundation'));
    await tester.pumpAndSettle();
    // The muscle map sits above the exercise list.
    expect(find.text('Muscles worked'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bodyweight Squat'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
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
    // Flush the short FTappable press timers (100 ms) left after the tap.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('nutrition tab logs a manual meal for today', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_v1': '{"done":true}'});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
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
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nutrition'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('nutrition-log-manual')));
    await tester.tap(find.byKey(const Key('nutrition-log-manual')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-name')),
        matching: find.byType(EditableText),
      ),
      'Phở bò',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('log-meal-kcal')),
        matching: find.byType(EditableText),
      ),
      '450',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-meal-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Phở bò'), findsOneWidget);
    expect(find.textContaining('450'), findsWidgets);
    expect(find.textContaining('eaten today'), findsOneWidget);
    expect(preferences.getString('food_log_v1'), contains('Phở bò'));
  });
}
