import '../models/workout.dart';
import '../models/workout_session.dart';

abstract interface class WorkoutRepository {
  Future<List<Workout>> getWorkouts();
  Future<Workout?> getWorkout(String id);
  Future<void> saveWorkout(Workout workout);
  Future<List<WorkoutSession>> getRecentSessions();
  Future<void> saveSession(WorkoutSession session);
}
