import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'api/api_client.dart';
import 'local_workout_repository.dart';

/// Workout data backed by the FitFlow API (replaces
/// FirestoreWorkoutRepository, with the same local-first behaviour).
///
/// Templates come from `GET /api/templates` (cached in SharedPreferences,
/// bundled seeds before the first fetch). Per-user data syncs through
/// `/api/me/docs/{sessions,workouts,weights}` and `/api/me/meta`. Reads
/// never wait for the network: writes land locally first and are sent in
/// the background.
class RemoteWorkoutRepository implements WorkoutRepository {
  RemoteWorkoutRepository(
    this._api,
    this._local,
    this._preferences, {
    required this._currentUserId,
  });

  static const _cacheKey = 'workouts_remote_v1';

  final ApiClient _api;
  final LocalWorkoutRepository _local;
  final SharedPreferences _preferences;
  final String? Function() _currentUserId;

  /// Currently signed-in account id, or null when signed out.
  String? get uid => _currentUserId();

  bool get signedIn => uid != null;

  List<Workout>? _cachedTemplates() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null) return null;
    final cached = LocalWorkoutRepository.decodeList(raw, Workout.fromJson);
    return cached.isEmpty ? null : cached;
  }

  /// Re-fetches the public templates into the cache; no-op offline.
  Future<void> refreshTemplates() async {
    try {
      final json = await _api.get('templates', auth: false);
      if (json is! List) return;
      final workouts = <Workout>[];
      for (final item in json) {
        try {
          workouts.add(Workout.fromJson(item as Map<String, dynamic>));
        } catch (e) {
          debugPrint('Skipping malformed template: $e');
        }
      }
      if (workouts.isEmpty) return;
      await _preferences.setString(
        _cacheKey,
        jsonEncode(workouts.map((item) => item.toJson()).toList()),
      );
    } on ApiException catch (e) {
      // Offline or server trouble — keep the cached (or bundled) templates.
      debugPrint('Template refresh failed: $e');
    }
  }

  /// Stores merged custom workouts locally (see AppController.sync).
  Future<void> storeCustomWorkouts(List<Workout> custom) async {
    final others = (await _local.getSavedWorkouts()).where(
      (item) => !item.id.startsWith('custom-'),
    );
    await _local.overwriteWorkouts([...others, ...custom]);
  }

  /// Stores merged sessions locally (see AppController.sync).
  Future<void> storeSessions(List<WorkoutSession> sessions) =>
      _local.overwriteSessions(sessions);

  /// Drops all locally cached synced data (sessions + custom workouts).
  Future<void> clearLocalData() => _local.clearAll();

  @override
  Future<List<Workout>> getWorkouts() async {
    final saved = await _local.getSavedWorkouts();
    final templates = _cachedTemplates() ?? _local.templates;
    final custom = saved.where((item) => item.id.startsWith('custom-'));
    return [...templates, ...custom];
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
  Future<void> deleteWorkout(String id) => _local.deleteWorkout(id);

  @override
  Future<List<WorkoutSession>> getRecentSessions() =>
      _local.getRecentSessions();

  @override
  Future<void> saveSession(WorkoutSession session) =>
      _local.saveSession(session);

  @override
  Future<void> deleteSession(String id) => _local.deleteSession(id);
}
