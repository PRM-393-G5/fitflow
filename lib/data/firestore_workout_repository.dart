import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'local_workout_repository.dart';

/// Workout templates come from the global `workouts` collection (cached in
/// SharedPreferences). Per-user data syncs under `users/{uid}`: sessions and
/// custom workouts (`custom-*` ids) merge by id, the meta doc (weights,
/// profile, schedule, onboarding, weekly goal) is last-write-wins.
/// Everything stays readable offline; sign-out falls back to local-only.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository(this._firestore, this._local, this._preferences);

  static const _cacheKey = 'workouts_remote_v1';
  static const _timeout = Duration(seconds: 8);

  final FirebaseFirestore _firestore;
  final LocalWorkoutRepository _local;
  final SharedPreferences _preferences;

  /// Currently signed-in user id, or null when signed out.
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  bool get signedIn => uid != null;

  CollectionReference<Map<String, dynamic>>? _userCollection(String name) {
    final currentUid = uid;
    if (currentUid == null) return null;
    return _firestore.collection('users').doc(currentUid).collection(name);
  }

  /// Union of two id-keyed lists; [remote] wins on id conflicts.
  static List<T> mergeById<T>(
    Iterable<T> local,
    Iterable<T> remote,
    String Function(T) idOf,
  ) {
    final byId = {for (final item in remote) idOf(item): item};
    for (final item in local) {
      byId.putIfAbsent(idOf(item), () => item);
    }
    return byId.values.toList();
  }

  /// Docs of a user collection as JSON maps, or null when unreachable.
  Future<List<Map<String, dynamic>>?> _fetchDocs(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      final snapshot = await collection.get().timeout(_timeout);
      return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (_) {
      return null;
    }
  }

  /// Pushes merged docs that exist locally but not remotely.
  // ponytail: one batch caps at 500 writes — a backlog that big never
  // uploads; upgrade path is chunking docs into batches of 500.
  void _pushMissing(
    CollectionReference<Map<String, dynamic>> collection,
    Iterable<({String id, Map<String, Object> json})> docs,
  ) {
    final batch = _firestore.batch();
    var dirty = false;
    for (final doc in docs) {
      batch.set(collection.doc(doc.id), doc.json);
      dirty = true;
    }
    if (dirty) batch.commit().ignore();
  }

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

  /// Merges user-cloud custom workouts with local ones (remote wins on
  /// conflicts), refreshes the local cache and pushes local-only docs.
  Future<List<Workout>> _syncCustomWorkouts(List<Workout> localAll) async {
    final localCustom = localAll
        .where((item) => item.id.startsWith('custom-'))
        .toList();
    final collection = _userCollection('workouts');
    if (collection == null) return localCustom;
    final docs = await _fetchDocs(collection);
    if (docs == null) return localCustom;
    final remote = docs.map(Workout.fromJson).toList();
    final merged = mergeById(localCustom, remote, (item) => item.id);
    for (final workout in merged) {
      await _local.saveWorkout(workout);
    }
    final remoteIds = {for (final item in remote) item.id};
    _pushMissing(
      collection,
      merged
          .where((item) => !remoteIds.contains(item.id))
          .map((item) => (id: item.id, json: item.toJson())),
    );
    return merged;
  }

  /// Pulls the `users/{uid}` meta doc. Null when signed out or absent;
  /// callers must catch failures (offline) and skip syncing.
  Future<Map<String, dynamic>?> pullMeta() async {
    final currentUid = uid;
    if (currentUid == null) return null;
    final doc = await _firestore
        .collection('users')
        .doc(currentUid)
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);
    return doc.data();
  }

  /// Pushes the meta blob; [updatedAt] drives last-write-wins merges.
  Future<void> pushMeta(Map<String, Object?> meta, int updatedAt) async {
    final currentUid = uid;
    if (currentUid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(currentUid)
          .set({...meta, 'updatedAt': updatedAt}, SetOptions(merge: true))
          .timeout(_timeout);
    } catch (_) {}
  }

  /// Drops all locally cached synced data (sessions + custom workouts).
  Future<void> clearLocalData() => _local.clearAll();

  @override
  Future<List<Workout>> getWorkouts() async {
    final remote = await _fetchRemote();
    final local = await _local.getWorkouts();
    if (remote == null || remote.isEmpty) return local;
    return [...remote, ...await _syncCustomWorkouts(local)];
  }

  @override
  Future<Workout?> getWorkout(String id) async {
    for (final workout in await getWorkouts()) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  @override
  Future<void> saveWorkout(Workout workout) async {
    await _local.saveWorkout(workout);
    if (!workout.id.startsWith('custom-')) return;
    try {
      await _userCollection('workouts')?.doc(workout.id).set(workout.toJson());
    } catch (_) {}
  }

  @override
  Future<List<WorkoutSession>> getRecentSessions() async {
    final local = await _local.getRecentSessions();
    final collection = _userCollection('sessions');
    if (collection == null) return local;
    final docs = await _fetchDocs(collection);
    if (docs == null) return local;
    final remote = docs.map(WorkoutSession.fromJson).toList();
    final merged = mergeById(local, remote, (item) => item.id)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    await _local.overwriteSessions(merged);
    final remoteIds = {for (final item in remote) item.id};
    _pushMissing(
      collection,
      merged
          .where((item) => !remoteIds.contains(item.id))
          .map((item) => (id: item.id, json: item.toJson())),
    );
    return merged;
  }

  @override
  Future<void> saveSession(WorkoutSession session) async {
    await _local.saveSession(session);
    try {
      await _userCollection('sessions')?.doc(session.id).set(session.toJson());
    } catch (_) {}
  }
}
