import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/progression.dart';
import 'package:prm/domain/workout_stats.dart';
import 'package:prm/features/workouts/presentation/active_workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise plan(
  String name, {
  int sets = 3,
  int reps = 10,
  int seconds = 0,
  double kg = 0,
  String muscle = 'x',
}) => Exercise(
  id: name,
  name: name,
  muscleGroup: muscle,
  sets: sets,
  reps: seconds > 0 ? 0 : reps,
  durationSeconds: seconds,
  weightKg: kg,
);

WorkoutSession done(
  DateTime day,
  Exercise exercise,
  List<SetEntry> sets, {
  String workoutId = 'workout',
}) => WorkoutSession(
  id: day.toIso8601String(),
  workoutId: workoutId,
  workoutName: 'Workout',
  startedAt: day,
  completedAt: day,
  completedSets: sets.length,
  volumeKg: 0,
  exercises: [exercise.copyWith(performedSets: sets)],
);

List<SetEntry> sets(int count, int amount, [double kg = 0]) => [
  for (var i = 0; i < count; i++) SetEntry(amount: amount, weightKg: kg),
];

void main() {
  final row = plan('Dumbbell Row', kg: 10);
  // Sessions in the first days of October; "today" is shortly after.
  final today = DateTime(2026, 10, 10);
  DateTime day(int n) => DateTime(2026, 10, n);

  ProgressionHint hint(
    List<WorkoutSession> sessions,
    Exercise planned, {
    String? category,
    bool metric = true,
    DateTime? now,
    int maxAmount = 1 << 30,
    double maxWeightKg = double.infinity,
  }) => Progression.forExercise(
    sessions,
    planned,
    category: category,
    metric: metric,
    now: now ?? today,
    maxAmount: maxAmount,
    maxWeightKg: maxWeightKg,
  )!;

  test('no history gives no hint', () {
    expect(Progression.forExercise(const [], row), isNull);
  });

  group('loaded: double progression with the 2-for-2 rule', () {
    test('every set at the target adds a rep at the same weight', () {
      final result = hint([done(day(1), row, sets(3, 10, 12))], row);

      expect(result.reason, ProgressionReason.building);
      expect(result.weightKg, 12);
      expect(result.amount, 11);
      expect(result.lastSets.length, 3);
    });

    test('reps build up to the top of the range, not beyond', () {
      final result = hint([done(day(1), row, sets(3, 12, 12))], row);

      expect(result.reason, ProgressionReason.building);
      expect(result.amount, 12);
      expect(result.weightKg, 12);
    });

    test('top of the range twice in a row steps the weight up', () {
      final result = hint([
        done(day(4), row, sets(3, 12, 12)),
        done(day(1), row, sets(3, 12, 12)),
      ], row);

      expect(result.stepUp, isTrue);
      expect(result.reason, ProgressionReason.stepUp);
      // 2.5% of 12 kg rounds to one 1 kg dumbbell step.
      expect(result.weightKg, 13);
      expect(result.amount, 10);
    });

    test('steps are 2.5% upper body, 5% lower body, on real loads', () {
      double next(String muscle, double kg, {bool metric = true}) {
        final lift = plan('Lift', reps: 5, kg: kg, muscle: muscle);
        return hint(
          [
            done(day(4), lift, sets(3, 7, kg)),
            done(day(1), lift, sets(3, 7, kg)),
          ],
          lift,
          metric: metric,
        ).weightKg;
      }

      expect(next('Shoulders', 4), 5); // not 6.5 kg (+63%)
      expect(next('Chest', 60), 62.5);
      expect(next('Legs', 100), 105);
      expect(next('Glutes', 18), 19);
      // 60 kg shows as 132.3 lb; the next loadable weight is 135 lb.
      expect(next('Chest', 60, metric: false), closeTo(135 / 2.20462, 1e-9));
    });

    test('missed reps repeat the weight and the plan', () {
      final result = hint([
        done(day(1), row, const [
          SetEntry(amount: 10, weightKg: 12),
          SetEntry(amount: 8, weightKg: 12),
          SetEntry(amount: 7, weightKg: 12),
        ]),
      ], row);

      expect(result.reason, ProgressionReason.repeat);
      expect(result.weightKg, 12);
      expect(result.amount, 10);
    });

    test('skipped sets or a lighter drop set do not progress', () {
      final skipped = hint([done(day(1), row, sets(2, 12, 12))], row);
      final dropSet = hint([
        done(day(1), row, const [
          SetEntry(amount: 12, weightKg: 12),
          SetEntry(amount: 12, weightKg: 12),
          SetEntry(amount: 12, weightKg: 8),
        ]),
      ], row);

      expect(skipped.reason, ProgressionReason.repeat);
      expect(skipped.weightKg, 12);
      expect(dropSet.reason, ProgressionReason.repeat);
      expect(dropSet.weightKg, 12);
    });

    test('warm-up sets do not count as the working weight', () {
      final withWarmUp = [
        const SetEntry(amount: 5, weightKg: 6),
        ...sets(3, 12, 12),
      ];
      final result = hint([
        done(day(4), row, withWarmUp),
        done(day(1), row, withWarmUp),
      ], row);

      expect(result.reason, ProgressionReason.stepUp);
      expect(result.weightKg, 13);
    });

    test('three misses in a row at the same weight deload 10%', () {
      final squat = plan('Squat', kg: 50, muscle: 'Legs');
      final miss = const [
        SetEntry(amount: 10, weightKg: 50),
        SetEntry(amount: 8, weightKg: 50),
        SetEntry(amount: 7, weightKg: 50),
      ];
      final twice = hint([
        done(day(8), squat, miss),
        done(day(5), squat, miss),
      ], squat);
      final thrice = hint([
        done(day(8), squat, miss),
        done(day(5), squat, miss),
        done(day(1), squat, miss),
      ], squat);

      expect(twice.reason, ProgressionReason.repeat);
      expect(twice.weightKg, 50);
      expect(thrice.reason, ProgressionReason.deload);
      expect(thrice.weightKg, 45);
      expect(thrice.amount, 10);
    });

    test('loads of two steps or less are never cut', () {
      final curl = plan('Curl', kg: 2);
      final miss = sets(3, 6, 2);
      final result = hint([
        done(day(8), curl, miss),
        done(day(5), curl, miss),
        done(day(1), curl, miss),
      ], curl);

      expect(result.reason, ProgressionReason.repeat);
      expect(result.weightKg, 2);
    });

    test('a changed target converts the last load with Epley', () {
      final eight = plan('Squat', reps: 8, kg: 50, muscle: 'Legs');
      final twelve = plan('Squat', reps: 12, kg: 50, muscle: 'Legs');
      final five = plan('Squat', reps: 5, kg: 100, muscle: 'Legs');
      final moreReps = hint([
        done(day(8), eight, sets(3, 8, 50)),
        done(day(5), eight, sets(3, 8, 50)),
        done(day(1), eight, sets(3, 8, 50)),
      ], twelve);
      final fewerToMore = hint([
        done(day(8), five, sets(3, 5, 100)),
      ], plan('Squat', reps: 8, kg: 100, muscle: 'Legs'));

      // Past successes are not judged against the new target (no deload).
      expect(moreReps.reason, ProgressionReason.newTarget);
      expect(moreReps.weightKg, 45); // 50 × (1 + 8/30) / (1 + 12/30)
      expect(moreReps.amount, 12);
      expect(fewerToMore.weightKg, 92.5); // 100 × 5 → 92.1 kg × 8
    });

    test('alternating plans follow the session with the same reps', () {
      final heavy = plan('Bench', reps: 5, kg: 80);
      final light = plan('Bench', reps: 12, kg: 50);
      final result = hint([
        done(day(8), heavy, sets(3, 5, 80)),
        done(day(5), light, sets(3, 12, 50)),
      ], light);

      expect(result.lastDate, day(5));
      expect(result.otherTargetSince, isTrue);
      expect(result.weightKg, 50);
      expect(result.reason, ProgressionReason.building);
    });

    test('the same exercise planned twice keeps separate hints', () {
      final heavy = plan('Bench', reps: 5, kg: 80);
      final light = plan('Bench', reps: 12, kg: 50);
      WorkoutSession both(DateTime at) => WorkoutSession(
        id: at.toIso8601String(),
        workoutId: 'workout',
        workoutName: 'Workout',
        startedAt: at,
        completedAt: at,
        completedSets: 6,
        volumeKg: 0,
        exercises: [
          heavy.copyWith(performedSets: sets(3, 5, 80)),
          light.copyWith(performedSets: sets(3, 12, 50)),
        ],
      );
      final history = [both(day(8)), both(day(4))];

      expect(hint(history, light).weightKg, 50);
      expect(hint(history, light).reason, ProgressionReason.building);
      expect(hint(history, heavy).weightKg, 80);
      expect(hint(history, heavy).otherTargetSince, isFalse);
    });

    test('lighter drop sets keep the top load', () {
      final press = plan('Press', kg: 50);
      final result = hint([
        done(day(1), press, const [
          SetEntry(amount: 10, weightKg: 50),
          SetEntry(amount: 8, weightKg: 40),
          SetEntry(amount: 8, weightKg: 40),
        ]),
      ], press);

      expect(result.weightKg, 50);
      expect(result.reason, ProgressionReason.repeat);
    });

    test('an old run never steps up a load not lifted for weeks', () {
      final light = plan('Press', reps: 12, kg: 25);
      final heavy = plan('Press', reps: 5, kg: 40);
      final result = hint(
        [
          done(DateTime(2026, 10, 8), heavy, sets(3, 5, 40)),
          done(DateTime(2026, 5, 4), light, sets(3, 14, 25)),
          done(DateTime(2026, 5, 1), light, sets(3, 14, 25)),
        ],
        light,
        now: DateTime(2026, 10, 10),
      );

      // Trained recently (no comeback), but the 2-for-2 run is stale.
      expect(result.reason, ProgressionReason.building);
      expect(result.weightKg, 25);
    });

    test('breaks count calendar days, not 24-hour periods', () {
      final squat = plan('Squat', kg: 50, muscle: 'Legs');
      final result = hint(
        [done(DateTime(2026, 9, 1, 20), squat, sets(3, 10, 50))],
        squat,
        now: DateTime(2026, 9, 30, 8), // 29 days later, under 29 × 24 h
      );

      expect(result.reason, ProgressionReason.comeback);
    });

    test('a break on a load too light to cut keeps progressing', () {
      final curl = plan('Curl', kg: 2);
      final result = hint(
        [
          done(day(4), curl, sets(3, 12, 2)),
          done(day(1), curl, sets(3, 12, 2)),
        ],
        curl,
        now: day(4).add(const Duration(days: 30)),
      );

      expect(result.reason, ProgressionReason.building);
      expect(result.weightKg, 2);
    });

    test('a break of over four weeks starts 10% lighter, 20% after 12', () {
      final squat = plan('Squat', kg: 50, muscle: 'Legs');
      final history = [done(day(1), squat, sets(3, 10, 50))];
      final fiveWeeks = hint(
        history,
        squat,
        now: day(1).add(const Duration(days: 35)),
      );
      final fourMonths = hint(
        history,
        squat,
        now: day(1).add(const Duration(days: 120)),
      );

      expect(fiveWeeks.reason, ProgressionReason.comeback);
      expect(fiveWeeks.weightKg, 45);
      expect(fiveWeeks.weeksAway, 5);
      expect(fourMonths.weightKg, 40);
    });

    test('a break and misses never stack', () {
      final squat = plan('Squat', kg: 50, muscle: 'Legs');
      final miss = sets(3, 7, 50);
      final result = hint(
        [
          done(day(8), squat, miss),
          done(day(5), squat, miss),
          done(day(1), squat, miss),
        ],
        squat,
        now: day(8).add(const Duration(days: 40)),
      );

      expect(result.reason, ProgressionReason.comeback);
      expect(result.weightKg, 45);
    });

    test('a long gap between sessions ends the 2-for-2 run', () {
      final result = hint(
        [
          done(DateTime(2026, 11, 20), row, sets(3, 12, 12)),
          done(day(1), row, sets(3, 12, 12)),
        ],
        row,
        now: DateTime(2026, 11, 21),
      );

      expect(result.reason, ProgressionReason.building);
      expect(result.weightKg, 12);
    });

    test('a blank weight on a loaded plan suggests the plan load again', () {
      final result = hint([done(day(1), row, sets(3, 10))], row);

      expect(result.reason, ProgressionReason.repeat);
      expect(result.weightKg, 10);
      expect(result.amount, 10);
    });

    test('an exercise done twice in a session uses the fuller entry', () {
      final result = hint([
        WorkoutSession(
          id: 'twice',
          workoutId: 'workout',
          workoutName: 'Workout',
          startedAt: day(1),
          completedAt: day(1),
          completedSets: 4,
          volumeKg: 0,
          exercises: [
            row.copyWith(performedSets: sets(1, 5, 20)),
            row.copyWith(performedSets: sets(3, 10, 12)),
          ],
        ),
      ], row);

      expect(result.weightKg, 12);
      expect(result.reason, ProgressionReason.building);
    });
  });

  test('suggestions stay within the form limits', () {
    final plank = plan('Plank', sets: 1, seconds: 60);
    final held = hint(
      [done(day(1), plank, sets(1, 3600))],
      plank,
      maxAmount: 3600,
    );
    final lift = hint(
      [
        done(day(4), row, sets(3, 12, 999)),
        done(day(1), row, sets(3, 12, 999)),
      ],
      row,
      maxWeightKg: 1000,
    );
    final atCap = hint(
      [
        done(day(4), row, sets(3, 12, 1000)),
        done(day(1), row, sets(3, 12, 1000)),
      ],
      row,
      maxWeightKg: 1000,
    );

    expect(held.amount, 3600);
    expect(held.stepUp, isFalse);
    expect(lift.weightKg, 1000);
    expect(lift.stepUp, isTrue);
    expect(atCap.weightKg, 1000);
    expect(atCap.reason, ProgressionReason.capped);
  });

  group('bodyweight and holds', () {
    final pushUp = plan('Push-up', reps: 12);

    test('bodyweight adds a rep once every set reached the plan', () {
      final hit = hint([
        done(day(1), pushUp, const [
          SetEntry(amount: 14),
          SetEntry(amount: 13),
          SetEntry(amount: 12),
        ]),
      ], pushUp);
      final missed = hint([
        done(day(1), pushUp, const [
          SetEntry(amount: 12),
          SetEntry(amount: 10),
          SetEntry(amount: 8),
        ]),
      ], pushUp);

      expect(hit.stepUp, isTrue);
      expect(hit.amount, 13);
      expect(hit.weightKg, 0);
      expect(missed.reason, ProgressionReason.repeat);
      expect(missed.amount, 12);
    });

    test('bodyweight reps stop at 20 (or the plan, if higher)', () {
      final atCap = hint([done(day(1), pushUp, sets(3, 20))], pushUp);
      final bigPlan = plan('Jumping Jacks', reps: 30);
      final big = hint([done(day(1), bigPlan, sets(3, 30))], bigPlan);

      expect(atCap.reason, ProgressionReason.capped);
      expect(atCap.amount, 20);
      expect(big.reason, ProgressionReason.capped);
      expect(big.amount, 30);
    });

    test('bodyweight without a step up never drops below what was done', () {
      final result = hint([done(day(1), pushUp, sets(1, 15))], pushUp);

      expect(result.stepUp, isFalse);
      expect(result.amount, 15);
    });

    test('holds add 5 seconds up to 60 and keep the load', () {
      final plank = plan('Plank', sets: 2, seconds: 45);
      final step = hint([done(day(1), plank, sets(2, 45, 5))], plank);
      final near = hint([done(day(1), plank, sets(2, 58))], plank);
      final capped = hint([done(day(1), plank, sets(2, 60))], plank);

      expect(step.stepUp, isTrue);
      expect(step.amount, 50);
      expect(step.weightKg, 5);
      expect(near.amount, 60);
      expect(capped.reason, ProgressionReason.capped);
      expect(capped.amount, 60);
    });

    test('a lighter hold set blocks the step up and keeps the top load', () {
      final plank = plan('Plank', sets: 2, seconds: 45);
      final result = hint([
        done(day(1), plank, const [
          SetEntry(amount: 45, weightKg: 10),
          SetEntry(amount: 45, weightKg: 5),
        ]),
      ], plank);

      expect(result.stepUp, isFalse);
      expect(result.amount, 45);
      expect(result.weightKg, 10);
    });
  });

  test('lifts progress in any plan; cardio moves never load up', () {
    final swing = plan('Kettlebell Swing', reps: 5, kg: 16, muscle: 'Legs');
    final jacks = plan('Jumping Jacks', reps: 30, muscle: 'Cardio');

    final lift = hint(
      [
        done(day(4), swing, sets(3, 7, 16)),
        done(day(1), swing, sets(3, 7, 16)),
      ],
      swing,
      category: 'Cardio',
    );
    final cardioMove = hint(
      [done(day(1), jacks, sets(3, 30))],
      jacks,
      category: 'Strength',
    );

    expect(lift.reason, ProgressionReason.stepUp);
    expect(cardioMove.reason, ProgressionReason.maintain);
  });

  test('mobility and cardio plans repeat last time without loading up', () {
    final stretch = plan('Hip Flexor Stretch', sets: 2, seconds: 30);
    final jacks = plan('Jumping Jacks', reps: 30);

    final mobility = hint(
      [done(day(1), stretch, sets(2, 30))],
      stretch,
      category: 'Mobility',
    );
    final cardio = hint(
      [done(day(1), jacks, sets(3, 30))],
      jacks,
      category: 'Cardio',
    );

    expect(mobility.reason, ProgressionReason.maintain);
    expect(mobility.amount, 30);
    expect(cardio.reason, ProgressionReason.maintain);
    expect(cardio.amount, 30);
  });

  test('uses the newest session, matching names case-insensitively', () {
    final result = hint([
      done(day(1), row, sets(3, 10, 30)),
      done(day(8), plan(' dumbbell row '), sets(3, 8, 12)),
    ], row);

    expect(result.lastDate, day(8));
    expect(result.weightKg, 12);
  });

  test('form checks and timed/rep mismatches are ignored', () {
    final pushUp = plan('Push-up', reps: 12);
    final timedPushUp = plan('Push-up', seconds: 30);

    expect(
      Progression.forExercise([
        done(day(1), pushUp, sets(1, 20), workoutId: WorkoutStats.formCheckId),
        done(day(2), timedPushUp, sets(3, 30)),
      ], pushUp),
      isNull,
    );
  });

  Future<AppController> pumpWorkout(
    WidgetTester tester,
    List<WorkoutSession> history,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
    );
    await controller.load();
    for (final session in history) {
      await controller.addSession(session);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: AppTheme.light,
          child: FToaster(child: child!),
        ),
        home: ActiveWorkoutPage(
          workout: Workout(
            id: 'w1',
            name: 'Back',
            duration: const Duration(minutes: 5),
            level: 'Beginner',
            category: 'Strength',
            description: '',
            exercises: [row],
          ),
          controller: controller,
          clock: () => today,
        ),
      ),
    );
    return controller;
  }

  testWidgets('active workout prefills from last session and shows hints', (
    tester,
  ) async {
    final controller = await pumpWorkout(tester, [
      done(day(1), row, sets(3, 10, 12)),
    ]);

    expect(find.text('Last time: 3 × 10 @ 12 kg'), findsOneWidget);
    expect(find.byKey(const Key('step-up')), findsNothing);
    expect(
      find.text('Same weight — aim for 11 reps per set, then it goes up.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();

    // Later sets follow what was just logged, not the plan's 10 kg.
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();

    final saved = controller.sessions.first;
    final performed = saved.exercises.single.performedSets;
    expect(performed.map((set) => set.weightKg), [12, 12, 12]);
    expect(performed.map((set) => set.amount), [11, 11, 11]);
  });

  testWidgets('two sessions at the top of the range suggest more weight', (
    tester,
  ) async {
    await pumpWorkout(tester, [
      done(day(1), row, sets(3, 12, 12)),
      done(day(4), row, sets(3, 12, 12)),
    ]);

    expect(find.byKey(const Key('step-up')), findsOneWidget);
    expect(
      find.text('Top of the rep range twice in a row — try 13 kg today.'),
      findsOneWidget,
    );
  });

  testWidgets('a load far above the best asks before logging', (tester) async {
    final controller = await pumpWorkout(tester, [
      done(day(1), row, sets(3, 10, 60)),
    ]);

    await tester.enterText(find.byKey(const Key('set-weight')), '600');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    expect(find.text('Log 600 kg?'), findsOneWidget);

    // "Fix it" logs nothing and keeps the set open.
    await tester.tap(find.byKey(const Key('fix-heavy-set')));
    await tester.pumpAndSettle();
    expect(find.text('Set 1 of 3'), findsOneWidget);

    // A real jump within 1.25× / +10 kg of the best logs straight away.
    await tester.enterText(find.byKey(const Key('set-weight')), '70');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    expect(find.text('Set 2 of 3'), findsOneWidget);

    // Confirming logs the heavy set as typed.
    await tester.enterText(find.byKey(const Key('set-weight')), '200');
    await tester.tap(find.byKey(const Key('complete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-heavy-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    expect(find.text('Set 3 of 3'), findsOneWidget);
    expect(controller.sessions, hasLength(1)); // not finished yet

    // Leave the workout so its timers stop.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('last-time label names bodyweight sets', (tester) async {
    await pumpWorkout(tester, [
      done(day(1), row, const [
        SetEntry(amount: 10, weightKg: 12),
        SetEntry(amount: 8),
      ]),
    ]);

    expect(find.text('Last time: 10 @ 12 kg, 8 @ bodyweight'), findsOneWidget);
    expect(find.byKey(const Key('step-up')), findsNothing);
  });
}
