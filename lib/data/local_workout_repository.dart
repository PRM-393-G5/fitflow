import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'seed_workouts.dart';

class LocalWorkoutRepository implements WorkoutRepository {
  LocalWorkoutRepository(this.preferences, {this.templates = seedWorkouts});

  static const _workoutsKey = 'workouts_v1';
  static const _sessionsKey = 'sessions_v1';
  final SharedPreferences preferences;

  /// Bundled plans, shown until (or instead of) cloud templates.
  final List<Workout> templates;

  /// Decodes a stored JSON list item by item — one malformed record is
  /// dropped instead of failing the whole list.
  static List<T> decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];
    try {
      final items = jsonDecode(raw);
      if (items is! List) return [];
      final result = <T>[];
      for (final item in items) {
        try {
          result.add(fromJson(item as Map<String, dynamic>));
        } catch (e) {
          debugPrint('Skipping malformed record: $e');
        }
      }
      return result;
    } on FormatException {
      return [];
    }
  }

  /// Workouts the user saved on this device (custom plans, AI plans).
  Future<List<Workout>> getSavedWorkouts() async =>
      decodeList(preferences.getString(_workoutsKey), Workout.fromJson);

  @override
  Future<List<Workout>> getWorkouts() async {
    final saved = await getSavedWorkouts();
    final savedIds = {for (final item in saved) item.id};
    return [
      ...templates.where((item) => !savedIds.contains(item.id)),
      ...saved,
    ];
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
    final workouts = await getSavedWorkouts();
    final index = workouts.indexWhere((item) => item.id == workout.id);
    if (index < 0) {
      workouts.add(workout);
    } else {
      workouts[index] = workout;
    }
    await overwriteWorkouts(workouts);
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final workouts = await getSavedWorkouts();
    workouts.removeWhere((item) => item.id == id);
    await overwriteWorkouts(workouts);
  }

  /// Replaces all saved workouts — used by cloud sync merges.
  Future<void> overwriteWorkouts(List<Workout> workouts) async {
    await preferences.setString(
      _workoutsKey,
      jsonEncode(workouts.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<List<WorkoutSession>> getRecentSessions() async {
    final sessions = decodeList(
      preferences.getString(_sessionsKey),
      WorkoutSession.fromJson,
    );
    sessions.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return sessions;
  }

  @override
  Future<void> saveSession(WorkoutSession session) async {
    final sessions = await getRecentSessions();
    sessions.removeWhere((item) => item.id == session.id);
    sessions.insert(0, session);
    await overwriteSessions(sessions);
  }

  @override
  Future<void> deleteSession(String id) async {
    final sessions = await getRecentSessions();
    sessions.removeWhere((item) => item.id == id);
    await overwriteSessions(sessions);
  }

  /// Replaces all stored sessions — used by cloud sync merges.
  Future<void> overwriteSessions(List<WorkoutSession> sessions) async {
    await preferences.setString(
      _sessionsKey,
      jsonEncode(sessions.map((item) => item.toJson()).toList()),
    );
  }

  /// Removes all stored workouts and sessions — used when the signed-in
  /// account changes so the previous account's data can't leak across.
  Future<void> clearAll() async {
    await preferences.remove(_workoutsKey);
    await preferences.remove(_sessionsKey);
  }
}
