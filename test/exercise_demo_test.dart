import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/domain/exercise_motions.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/motion_rig.dart';
import 'package:prm/features/exercise_demo/presentation/anatomy_figure.dart';
import 'package:prm/features/exercise_demo/presentation/exercise_demo.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:prm/features/workouts/presentation/workout_detail_page.dart';

import 'workouts_flow_test.dart' show launch, makeController, plan;

const _mixed = Workout(
  id: 'mixed',
  name: 'Mixed',
  duration: Duration(minutes: 20),
  level: 'Beginner',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(
      id: 'squat',
      name: 'Goblet Squat',
      muscleGroup: 'Legs',
      sets: 3,
      reps: 10,
    ),
    Exercise(
      id: 'row',
      name: 'Dumbbell Row',
      muscleGroup: 'Back',
      sets: 3,
      reps: 12,
    ),
  ],
);

Future<void> pumpDemo(WidgetTester tester, {bool reduceMotion = false}) =>
    tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
        ),
        home: Center(
          child: SizedBox(
            width: 320,
            height: 240,
            child: ExerciseDemo(motion: ExerciseMotions.bundled.first),
          ),
        ),
      ),
    );

String cue(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('exercise-demo-cue'))).data!;

void main() {
  testWidgets('details open the demo of exercises that have one', (
    tester,
  ) async {
    final controller = await makeController(saved: [_mixed]);
    await launch(
      tester,
      controller,
      () => const WorkoutDetailPage(workout: _mixed),
    );

    // No demo for rows: the tile does nothing.
    await tester.tap(find.byKey(const Key('exercise-tile-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-demo-sheet')), findsNothing);

    await tester.tap(find.byKey(const Key('exercise-tile-squat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-demo-sheet')), findsOneWidget);
    final muscles = find.byKey(const Key('exercise-demo-muscles'));
    for (final label in ['Glutes', 'Quads', 'Adductors']) {
      expect(
        find.descendant(of: muscles, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.text('Keep your chest up'), findsOneWidget);
    expect(find.textContaining('AI camera'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Demo of Squat')), findsOneWidget);

    // Seen from the side first; a squat can be turned to the back.
    AnatomyPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<AnatomyPainter>()
        .single;
    expect(painter().angle, MotionAngle.side);
    await tester.tap(find.byKey(const Key('demo-angle-back')));
    await tester.pumpAndSettle();
    expect(painter().angle, MotionAngle.back);

    await tester.ensureVisible(find.byKey(const Key('exercise-demo-done')));
    await tester.tap(find.byKey(const Key('exercise-demo-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-demo-sheet')), findsNothing);
  });

  testWidgets('rest shows a demo of the next exercise', (tester) async {
    final workout = plan(sets: 2, rest: 30);
    final controller = await makeController(saved: [workout]);
    await launch(
      tester,
      controller,
      () => ActiveWorkoutPage(workout: workout, controller: controller),
    );

    expect(find.byKey(const Key('up-next-demo')), findsNothing);
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('up-next-demo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('up-next-demo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-demo-sheet')), findsOneWidget);
  });

  testWidgets('every bundled motion paints from every angle it offers', (
    tester,
  ) async {
    for (final motion in ExerciseMotions.bundled) {
      for (final angle in MotionRig.angles(motion)) {
        for (final at in [0.0, .3, .6]) {
          await tester.pumpWidget(
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(
                  painter: AnatomyPainter(
                    motion: motion,
                    progress: AlwaysStoppedAnimation(at),
                    angle: angle,
                    worked: motion.muscles,
                    body: const Color(0xFFE9ECF1),
                    muscle: const Color(0xFFC6CCD6),
                    workedColor: workedMuscleColor,
                    outline: const Color(0xFFB8C0CC),
                    floor: const Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '${motion.id} $angle');
        }
      }
    }
  });

  group('playing', () {
    setUp(() => ExerciseDemo.autoplay = true);
    tearDown(() => ExerciseDemo.autoplay = false);

    testWidgets('loops through the cues', (tester) async {
      await pumpDemo(tester);
      expect(cue(tester), 'Sit back and down');

      // Past the stand (400 ms) and the way down (1200 ms).
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(cue(tester), 'Drive up through your heels');

      // Round the loop (2750 ms) and back to the start.
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(cue(tester), 'Sit back and down');
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('holds the bottom of the move under reduce motion', (
      tester,
    ) async {
      await pumpDemo(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(cue(tester), 'Drive up through your heels');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
