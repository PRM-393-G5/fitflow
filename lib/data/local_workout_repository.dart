import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'seed_workouts.dart';

class LocalWorkoutRepository implements WorkoutRepository {
  LocalWorkoutRepository(this.preferences);

  static const _workoutsKey = 'workouts_v1';
  static const _sessionsKey = 'sessions_v1';
  final SharedPreferences preferences;

  @override
  Future<List<Workout>> getWorkouts() async {
    final raw = preferences.getString(_workoutsKey);
    if (raw == null) {
      await preferences.setString(
        _workoutsKey,
        jsonEncode(seedWorkouts.map((item) => item.toJson()).toList()),
      );
      return List.of(seedWorkouts);
    }
    try {
      return (jsonDecode(raw) as List)
          .map((item) => Workout.fromJson(item as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return List.of(seedWorkouts);
    }
  }

  @override
  Future<Workout?> getWorkout(String id) async {
    final workouts = await getWorkouts();
    for (final workout in workouts) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  @override
  Future<void> saveWorkout(Workout workout) async {
    final workouts = await getWorkouts();
    final index = workouts.indexWhere((item) => item.id == workout.id);
    if (index < 0) {
      workouts.add(workout);
    } else {
      workouts[index] = workout;
    }
    await preferences.setString(
      _workoutsKey,
      jsonEncode(workouts.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<List<WorkoutSession>> getRecentSessions() async {
    final raw = preferences.getString(_sessionsKey);
    if (raw == null) return [];
    try {
      final sessions = (jsonDecode(raw) as List)
          .map((item) => WorkoutSession.fromJson(item as Map<String, dynamic>))
          .toList();
      sessions.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      return sessions;
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> saveSession(WorkoutSession session) async {
    final sessions = await getRecentSessions();
    sessions.removeWhere((item) => item.id == session.id);
    sessions.insert(0, session);
    await preferences.setString(
      _sessionsKey,
      jsonEncode(sessions.map((item) => item.toJson()).toList()),
    );
  }
}
