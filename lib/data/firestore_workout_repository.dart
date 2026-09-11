import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'local_workout_repository.dart';

/// Workout templates come from Firestore and are cached in SharedPreferences.
/// Custom workouts (`custom-*` ids) and sessions stay local-only.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository(this._firestore, this._local, this._preferences);

  static const _cacheKey = 'workouts_remote_v1';
  static const _timeout = Duration(seconds: 8);

  final FirebaseFirestore _firestore;
  final LocalWorkoutRepository _local;
  final SharedPreferences _preferences;

  Future<List<Workout>?> _fetchRemote() async {
    try {
      final snapshot = await _firestore
          .collection('workouts')
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      final workouts = snapshot.docs
          .map((doc) => Workout.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
      await _preferences.setString(
        _cacheKey,
        jsonEncode(workouts.map((item) => item.toJson()).toList()),
      );
      return workouts;
    } catch (_) {
      final raw = _preferences.getString(_cacheKey);
      if (raw == null) return null;
      try {
        return (jsonDecode(raw) as List)
            .map((item) => Workout.fromJson(item as Map<String, dynamic>))
            .toList();
      } on FormatException {
        return null;
      }
    }
  }

  @override
  Future<List<Workout>> getWorkouts() async {
    final remote = await _fetchRemote();
    final local = await _local.getWorkouts();
    if (remote == null || remote.isEmpty) return local;
    return [
      ...remote,
      ...local.where((item) => item.id.startsWith('custom-')),
    ];
  }

  @override
  Future<Workout?> getWorkout(String id) async {
    for (final workout in await getWorkouts()) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  @override
  Future<void> saveWorkout(Workout workout) => _local.saveWorkout(workout);

  @override
  Future<List<WorkoutSession>> getRecentSessions() =>
      _local.getRecentSessions();

  @override
  Future<void> saveSession(WorkoutSession session) =>
      _local.saveSession(session);
}
