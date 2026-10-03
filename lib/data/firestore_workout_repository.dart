import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'local_workout_repository.dart';
import 'sync_merge.dart';

/// Workout templates come from the global `workouts` collection (cached in
/// SharedPreferences, bundled seeds before the first fetch). Per-user data
/// syncs under `users/{uid}`: sessions, custom workouts (`custom-*` ids)
/// and weights merge by id, the meta doc (profile, schedule, onboarding,
/// weekly goal) is last-write-wins.
///
/// The controller drives the merge ([AppController.sync]) so it can apply
/// edits made while the network round trip was in flight.
///
/// Reads and writes never wait for the server: writes land locally first
/// and Firestore's offline queue delivers them later. Deletes are soft
/// (`{deleted: true}` tombstones) so another device's merge cannot
/// resurrect the doc.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository(this._firestore, this._local, this._preferences);

  static const _cacheKey = 'workouts_remote_v1';
  static const _timeout = Duration(seconds: 8);
  static const _batchLimit = 400;

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

  /// Merges [local] JSON docs (each with an `id`) into `users/{uid}/[name]`:
  /// remote wins on conflicts, tombstoned ids are dropped, local-only docs
  /// are uploaded. Returns the merged docs, or null when signed out or
  /// unreachable (callers keep their local data).
  Future<List<Map<String, dynamic>>?> syncDocs(
    String name,
    List<Map<String, dynamic>> local,
  ) async {
    final collection = _userCollection(name);
    if (collection == null) return null;
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await collection.get().timeout(_timeout);
    } catch (_) {
      return null;
    }
    final result = SyncMerge.mergeDocs(local, [
      for (final doc in snapshot.docs) {...doc.data(), 'id': doc.id},
    ]);
    _pushAll(collection, result.toUpload);
    return result.merged;
  }

  /// Uploads docs in batches (Firestore caps a batch at 500 writes).
  void _pushAll(
    CollectionReference<Map<String, dynamic>> collection,
    Iterable<Map<String, dynamic>> docs,
  ) {
    final pending = docs.toList();
    for (var start = 0; start < pending.length; start += _batchLimit) {
      final batch = _firestore.batch();
      for (final doc in pending.skip(start).take(_batchLimit)) {
        batch.set(collection.doc(doc['id'] as String), doc);
      }
      batch.commit().catchError((Object e) {
        debugPrint('Sync upload failed: $e');
      });
    }
  }

  /// Queues a doc write without waiting for the server acknowledgement —
  /// offline, Firestore only completes the future once it reconnects.
  void putDoc(String name, String id, Map<String, Object?> json) {
    _userCollection(name)?.doc(id).set(json).catchError((Object e) {
      debugPrint('Cloud write failed: $e');
    });
  }

  /// Queues a tombstone for [id] (see class docs).
  void deleteDoc(String name, String id) => putDoc(name, id, {'deleted': true});

  List<Workout>? _cachedTemplates() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null) return null;
    final cached = LocalWorkoutRepository.decodeList(raw, Workout.fromJson);
    return cached.isEmpty ? null : cached;
  }

  /// Re-fetches the global templates into the cache; no-op offline.
  Future<void> refreshTemplates() async {
    try {
      final snapshot = await _firestore
          .collection('workouts')
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      final workouts = <Workout>[];
      for (final doc in snapshot.docs) {
        try {
          workouts.add(Workout.fromJson({...doc.data(), 'id': doc.id}));
        } catch (e) {
          debugPrint('Skipping malformed template ${doc.id}: $e');
        }
      }
      if (workouts.isEmpty) return;
      await _preferences.setString(
        _cacheKey,
        jsonEncode(workouts.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      // Offline — keep the cached (or bundled) templates.
    }
  }

  /// Stores merged custom workouts locally (see [AppController.sync]).
  Future<void> storeCustomWorkouts(List<Workout> custom) async {
    final others = (await _local.getSavedWorkouts()).where(
      (item) => !item.id.startsWith('custom-'),
    );
    await _local.overwriteWorkouts([...others, ...custom]);
  }

  /// Stores merged sessions locally (see [AppController.sync]).
  Future<void> storeSessions(List<WorkoutSession> sessions) =>
      _local.overwriteSessions(sessions);

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
          .set({
            ...meta,
            'updatedAt': updatedAt,
            // Weights moved to their own collection; drop the legacy copy
            // so it can't be merged back in later.
            'weights': FieldValue.delete(),
          }, SetOptions(merge: true))
          .timeout(_timeout);
    } catch (_) {}
  }

  /// Waits for queued writes to reach the server. False when they are
  /// still pending after [timeout] (offline) — signing out then would drop
  /// them.
  Future<bool> flushPendingWrites({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!signedIn) return true;
    try {
      await _firestore.waitForPendingWrites().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes everything under `users/{uid}` on the server. Throws when
  /// unreachable so the caller can keep the account intact.
  Future<void> deleteCloudData() async {
    final currentUid = uid;
    if (currentUid == null) return;
    final userDoc = _firestore.collection('users').doc(currentUid);
    for (final name in ['sessions', 'workouts', 'weights']) {
      final snapshot = await userDoc
          .collection(name)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      final docs = snapshot.docs;
      for (var start = 0; start < docs.length; start += _batchLimit) {
        final batch = _firestore.batch();
        for (final doc in docs.skip(start).take(_batchLimit)) {
          batch.delete(doc.reference);
        }
        await batch.commit().timeout(_timeout);
      }
    }
    await userDoc.delete().timeout(_timeout);
  }

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
  Future<void> saveWorkout(Workout workout) async {
    await _local.saveWorkout(workout);
    if (!workout.id.startsWith('custom-')) return;
    putDoc('workouts', workout.id, workout.toJson());
  }

  @override
  Future<void> deleteWorkout(String id) async {
    await _local.deleteWorkout(id);
    if (id.startsWith('custom-')) deleteDoc('workouts', id);
  }

  @override
  Future<List<WorkoutSession>> getRecentSessions() =>
      _local.getRecentSessions();

  @override
  Future<void> saveSession(WorkoutSession session) async {
    await _local.saveSession(session);
    putDoc('sessions', session.id, session.toJson());
  }

  @override
  Future<void> deleteSession(String id) async {
    await _local.deleteSession(id);
    deleteDoc('sessions', id);
  }
}
