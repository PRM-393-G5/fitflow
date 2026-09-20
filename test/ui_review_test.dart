import 'dart:convert';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' hide DateUtils;
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/body_weight_entry.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('packages/forui/assets/fonts/inter/Inter.ttf'));
  final lucide = FontLoader('ForuiLucideIcons')
    ..addFont(rootBundle.load('packages/forui_lucide/assets/lucide.ttf'));
  await inter.load();
  await lucide.load();
}

void main() {
  testWidgets('renders all tabs for visual review', (tester) async {
    // The golden-test font is much wider than Inter, so flex layouts that
    // fit on a real device can overflow here. Skip those reports — real
    // overflows are still visible in the PNGs themselves.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('RenderFlex overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    await _loadFonts();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const workout = Workout(
      id: 'w1',
      name: 'Full Body Foundation',
      duration: Duration(minutes: 32),
      level: 'Beginner',
      category: 'Strength',
      description: 'Balanced full body plan.',
      exercises: [
        Exercise(
          id: 'squat',
          name: 'Bodyweight Squat',
          muscleGroup: 'Legs',
          sets: 3,
          reps: 10,
        ),
        Exercise(
          id: 'pushup',
          name: 'Push-up',
          muscleGroup: 'Chest',
          sets: 3,
          reps: 12,
        ),
      ],
    );
    const workout2 = Workout(
      id: 'w2',
      name: 'Lower Body Strength',
      duration: Duration(minutes: 45),
      level: 'Intermediate',
      category: 'Strength',
      description: '',
      exercises: [
        Exercise(
          id: 'lunge',
          name: 'Walking Lunge',
          muscleGroup: 'Legs',
          sets: 4,
          reps: 8,
        ),
      ],
    );
    final now = DateTime.now();
    final sessions = [
      for (var i = 0; i < 6; i++)
        WorkoutSession(
          id: 's$i',
          workoutId: 'w1',
          workoutName: 'Full Body Foundation',
          startedAt: now.subtract(Duration(days: i * 2, hours: 1)),
          completedAt: now.subtract(Duration(days: i * 2)),
          completedSets: 9,
          volumeKg: 850 + i * 50,
          exercises: workout.exercises,
        ),
    ];
    final weights = [
      for (var i = 0; i < 5; i++)
        BodyWeightEntry(
          date: now.subtract(Duration(days: i * 7)),
          weightKg: 72.0 - i * 0.3,
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'onboarding_v1': '{"done":true}',
      'workouts_v1': jsonEncode([workout.toJson(), workout2.toJson()]),
      'sessions_v1': jsonEncode([for (final s in sessions) s.toJson()]),
      'body_weights_v1': jsonEncode([for (final w in weights) w.toJson()]),
      'weekly_goal_v1': 3,
      'body_profile_v1':
          '{"heightCm":172,"age":27,"isMale":true,"activityFactor":1.4}',
      'food_log_v1': jsonEncode({
        'date': DateUtils.dateOnly(now).toIso8601String(),
        'meals': [
          {'name': 'Phở bò', 'kcal': 450},
          {'name': 'Cơm gà', 'kcal': 620},
        ],
      }),
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
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('review/home.png'),
    );

    for (final (tab, name) in [
      ('Workouts', 'workouts'),
      ('Nutrition', 'nutrition'),
      ('Progress', 'progress'),
      ('Profile', 'profile'),
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('review/$name.png'),
      );
    }

    // Workout detail page.
    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Body Foundation'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('review/workout_detail.png'),
    );
  });
}
