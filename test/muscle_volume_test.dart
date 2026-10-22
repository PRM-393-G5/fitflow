import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/domain/muscle_volume.dart';
import 'package:prm/domain/workout_stats.dart';

WorkoutSession session(
  DateTime day,
  List<Exercise> exercises, {
  String workoutId = 'workout',
}) => WorkoutSession(
  id: day.toIso8601String(),
  workoutId: workoutId,
  workoutName: 'Workout',
  startedAt: day.subtract(const Duration(minutes: 30)),
  completedAt: day,
  completedSets: 3,
  volumeKg: 0,
  exercises: exercises,
);

Exercise exercise(
  String name, {
  String group = 'Full body',
  int sets = 3,
  int logged = 0,
}) => Exercise(
  id: name,
  name: name,
  muscleGroup: group,
  sets: sets,
  reps: 10,
  performedSets: [for (var i = 0; i < logged; i++) const SetEntry(amount: 10)],
);

MuscleWeights weights(String name, [String group = 'Full body']) =>
    MuscleVolume.weightsOf(exercise(name, group: group));

void main() {
  // Wednesday; the week runs from Monday 2026-10-19.
  final now = DateTime(2026, 10, 21, 18);

  group('muscles from the exercise name', () {
    test('main movers count fully, helpers by half', () {
      expect(weights('Dumbbell Bench Press'), {
        Muscle.chest: 1,
        Muscle.triceps: .5,
        Muscle.deltoids: .5,
      });
      expect(weights('Romanian Deadlift', 'Legs'), {
        Muscle.hamstrings: 1,
        Muscle.glutes: 1,
        Muscle.lowerBack: .5,
      });
      expect(weights('Lat Pulldown'), {Muscle.upperBack: 1, Muscle.biceps: .5});
    });

    test('specific names win over the generic words inside them', () {
      expect(weights('Lying Leg Curl'), {Muscle.hamstrings: 1});
      expect(weights('Biceps Curl'), {Muscle.biceps: 1, Muscle.forearms: .5});
      expect(weights('Leg Extension'), {Muscle.quadriceps: 1});
      expect(weights('Cable Triceps Extension'), {Muscle.triceps: 1});
      expect(weights('Upright Row').keys, contains(Muscle.trapezius));
    });

    test('presses, hip extensions and cardio rowers', () {
      expect(weights('Incline Dumbbell Press').keys.first, Muscle.chest);
      expect(weights('Hip Extension').keys.first, Muscle.glutes);
      expect(weights('Rowing Machine', 'Cardio'), isEmpty);
    });

    test('keywords match word starts only', () {
      // "row" inside "narrow" is not a row.
      expect(weights('Narrow-grip Bench Press').keys.first, Muscle.chest);
      // "chin" inside "machine" is not a chin-up.
      expect(weights('Machine Fly').keys.first, Muscle.chest);
    });

    test('falls back to the muscle group, mobility trains nothing', () {
      expect(weights('Kettlebell Swing', 'Glutes'), {
        Muscle.glutes: 1,
        Muscle.hamstrings: .5,
      });
      expect(weights('Thoracic Rotation', 'Back'), isEmpty);
      expect(weights('Burpees'), isEmpty);
      expect(weights('High Knees', 'Cardio'), isEmpty);
    });
  });

  test('sums logged sets this week and compares with last week', () {
    final weeks = MuscleVolume.weekly([
      session(DateTime(2026, 10, 19, 9), [
        exercise('Bench Press', logged: 4),
        exercise('Push-up', logged: 2),
      ]),
      session(DateTime(2026, 10, 21, 9), [exercise('Bench Press', logged: 2)]),
      // Last week (Sunday before) and two weeks ago.
      session(DateTime(2026, 10, 18, 9), [exercise('Bench Press', logged: 5)]),
      session(DateTime(2026, 10, 8, 9), [exercise('Bench Press', logged: 9)]),
    ], now: now);

    final chest = weeks[Muscle.chest]!;
    expect(chest.sets, 8);
    expect(chest.previous, 5);
    expect(chest.change, 3);
    expect(chest.missing, 2);
    // The same lift on two days is one row; most sets first.
    expect(chest.exercises, [
      (exercise: 'Bench Press', sets: 6.0, primary: true),
      (exercise: 'Push-up', sets: 2.0, primary: true),
    ]);
    expect(weeks[Muscle.triceps]!.sets, 4);
    expect(weeks[Muscle.triceps]!.exercises.first.primary, isFalse);
    expect(weeks[Muscle.calves]!.sets, 0);
  });

  test('legacy sessions use the plan; form checks are skipped', () {
    final weeks = MuscleVolume.weekly([
      session(DateTime(2026, 10, 20, 9), [
        // Planned 5, only 2 done.
        exercise('Calf Raise', sets: 5, logged: 2),
      ]),
      // Recorded before per-set logging.
      session(DateTime(2026, 10, 20, 8), [exercise('Plank', sets: 4)]),
      session(DateTime(2026, 10, 20, 10), [
        exercise('Squat', logged: 3),
      ], workoutId: WorkoutStats.formCheckId),
    ], now: now);

    expect(weeks[Muscle.calves]!.sets, 2);
    expect(weeks[Muscle.abs]!.sets, 4);
    expect(weeks[Muscle.quadriceps]!.sets, 0);
  });

  test('in a logged session, an exercise without sets was not done', () {
    final weeks = MuscleVolume.weekly([
      session(DateTime(2026, 10, 20, 9), [
        exercise('Bench Press', logged: 3),
        exercise('Calf Raise', sets: 4),
      ]),
    ], now: now);

    expect(weeks[Muscle.chest]!.sets, 3);
    expect(weeks[Muscle.calves]!.sets, 0);
  });

  test('a plan counts its planned sets, main movers first', () {
    final planned = MuscleVolume.planned([
      exercise('Bench Press', sets: 4),
      exercise('Overhead Press', sets: 3),
      exercise('Cat-Cow', sets: 2),
    ]);

    expect(planned.keys, {Muscle.chest, Muscle.deltoids, Muscle.triceps});
    expect(MuscleVolume.isPrimary(planned[Muscle.chest]!), isTrue);
    expect(MuscleVolume.isPrimary(planned[Muscle.triceps]!), isFalse);
    expect(planned[Muscle.deltoids], [
      (exercise: 'Overhead Press', sets: 3.0, primary: true),
      (exercise: 'Bench Press', sets: 2.0, primary: false),
    ]);
    expect(MuscleVolume.planned([exercise('Burpees')]), isEmpty);
  });

  test('levels follow the 10-20 weekly sets range', () {
    expect(MuscleVolume.level(0), VolumeLevel.none);
    expect(MuscleVolume.level(9.5), VolumeLevel.low);
    expect(MuscleVolume.level(10), VolumeLevel.optimal);
    expect(MuscleVolume.level(20), VolumeLevel.optimal);
    expect(MuscleVolume.level(20.5), VolumeLevel.high);
    expect(MuscleVolume.format(12), '12');
    expect(MuscleVolume.format(7.5), '7.5');
    expect(MuscleVolume.sets(1), '1 set');
    expect(MuscleVolume.sets(.5), '0.5 sets');
  });
}
