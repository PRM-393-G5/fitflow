import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists workouts and completed sessions across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWorkoutRepository(preferences);

    await repository.saveWorkout(
      const Workout(
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
      ),
    );
    final workouts = await repository.getWorkouts();
    expect(workouts.single.name, 'Full Body Foundation');
    expect(workouts.single.exercises, isNotEmpty);

    final completedAt = DateTime(2026, 4, 1, 11);
    await repository.saveSession(
      WorkoutSession(
        id: 'session-1',
        workoutId: workouts.first.id,
        workoutName: workouts.first.name,
        startedAt: completedAt.subtract(const Duration(minutes: 30)),
        completedAt: completedAt,
        completedSets: 12,
        volumeKg: 960,
      ),
    );

    final reloaded = LocalWorkoutRepository(preferences);
    final sessions = await reloaded.getRecentSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.workoutName, workouts.first.name);
    expect(sessions.single.volumeKg, 960);
  });
}
