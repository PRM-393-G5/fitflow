import '../models/workout.dart';
import '../models/workout_session.dart';

/// Reads are local and fast (on-device data plus cached templates); a
/// cloud-backed implementation merges with the server separately, in the
/// background, so nothing here blocks on the network.
abstract interface class WorkoutRepository {
  Future<List<Workout>> getWorkouts();
  Future<Workout?> getWorkout(String id);
  Future<void> saveWorkout(Workout workout);
  Future<void> deleteWorkout(String id);
  Future<List<WorkoutSession>> getRecentSessions();
  Future<void> saveSession(WorkoutSession session);
  Future<void> deleteSession(String id);
}
