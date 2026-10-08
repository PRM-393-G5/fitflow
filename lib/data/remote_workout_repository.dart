import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';
import 'api/api_client.dart';
import 'local_workout_repository.dart';
import 'outbox_sender.dart';
import 'sync_outbox.dart';
import 'sync_merge.dart';

/// Workout data backed by the FitFlow API, local-first.
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
    this._preferences,
    this._outbox, {
    required this._currentUserId,
  }) {
    _sender = OutboxSender(_outbox, _api, currentUserId: _currentUserId);
  }

  static const _cacheKey = 'workouts_remote_v1';

  final ApiClient _api;
  final LocalWorkoutRepository _local;
  final SharedPreferences _preferences;
  final String? Function() _currentUserId;
  final SyncOutbox _outbox;
  late final OutboxSender _sender;

  /// Currently signed-in account id, or null when signed out.
  String? get uid => _currentUserId();

  bool get signedIn => uid != null;

  /// Merges [local] JSON docs (each with an `id`) with the server's
  /// `/api/me/docs/[name]`: remote wins on conflicts, tombstoned ids are
  /// dropped, local-only docs are queued for upload. Writes still pending
  /// in the outbox are newer than the server copy, so they are delivered
  /// first and win over it. Returns the merged docs, or null when signed
  /// out or unreachable (callers keep their local data). With [since]
  /// (`yyyy-mm-dd`) only docs whose id sorts at or after it are fetched,
  /// for date-keyed kinds; [local] must then hold only such docs too.
  Future<List<Map<String, dynamic>>?> syncDocs(
    String name,
    List<Map<String, dynamic>> local, {
    String? since,
  }) async {
    final owner = uid;
    if (owner == null) return null;
    // Deliver this kind's pending writes first so the server copy is
    // current; skip the round trip when there are none.
    if (_outbox.pendingFor(owner, name).isNotEmpty) await _sender.flush();
    final List<Map<String, dynamic>> remote;
    try {
      final json = await _api.get(
        since == null ? 'me/docs/$name' : 'me/docs/$name?since=$since',
      );
      remote = [
        for (final doc in json as List) Map<String, dynamic>.from(doc as Map),
      ];
    } catch (e) {
      // Offline, TLS trouble or an unexpected payload: skip this
      // collection only; the rest of the sync goes on.
      debugPrint('Sync of $name failed: $e');
      return null;
    }
    final result = SyncMerge.mergeDocs(local, remote);
    final merged = _withPending(owner, name, result.merged);
    await _enqueue([
      for (final doc in result.toUpload)
        OutboxEntry(
          owner: owner,
          kind: name,
          id: doc['id'] as String,
          body: doc,
        ),
    ]);
    return merged;
  }

  /// Applies writes the server has not received yet on top of [merged].
  List<Map<String, dynamic>> _withPending(
    String owner,
    String name,
    List<Map<String, dynamic>> merged,
  ) {
    final pending = _outbox.pendingFor(owner, name);
    if (pending.isEmpty) return merged;
    final byId = {for (final doc in merged) doc['id'] as String: doc};
    for (final entry in pending) {
      if (entry.isDelete) {
        byId.remove(entry.id);
      } else {
        byId[entry.id] = {...entry.body!, 'id': entry.id};
      }
    }
    return byId.values.toList();
  }

  /// Queues a doc write and sends it in the background — the UI never
  /// waits on the network; offline it is retried on the next sync.
  void putDoc(String name, String id, Map<String, Object?> json) {
    final owner = uid;
    if (owner == null) return;
    unawaited(
      _enqueue([
        OutboxEntry(
          owner: owner,
          kind: name,
          id: id,
          body: Map<String, dynamic>.from(json),
        ),
      ]),
    );
  }

  /// Queues a delete; the server keeps a tombstone so another device's
  /// merge cannot resurrect the doc.
  void deleteDoc(String name, String id) {
    final owner = uid;
    if (owner == null) return;
    unawaited(_enqueue([OutboxEntry(owner: owner, kind: name, id: id)]));
  }

  Future<void> _enqueue(List<OutboxEntry> entries) async {
    if (entries.isEmpty) return;
    await _outbox.addAll(entries);
    unawaited(_sender.flush());
  }

  /// Tries to deliver every pending write. False when some are still
  /// pending after [timeout] (offline) — signing out then would lose them.
  /// The default leaves room for a large bulk upload on a slow network.
  Future<bool> flushPendingWrites({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!signedIn) return true;
    try {
      return await _sender.flush().timeout(timeout);
    } on TimeoutException {
      return false;
    }
  }

  /// Forgets [owner]'s writes that were never delivered (forced sign-out,
  /// account deletion). Other accounts' queued writes are kept.
  Future<void> discardPendingWrites(String owner) => _outbox.clearOwner(owner);

  /// Pulls the meta blob in the shape AppController merges:
  /// `{...meta, updatedAt}`, or null when never written or signed out.
  /// Throws [ApiException] when unreachable so callers skip the merge.
  Future<Map<String, dynamic>?> pullMeta() async {
    if (!signedIn) return null;
    final json = await _api.get('me/meta');
    final meta = json is Map ? json['meta'] : null;
    if (meta is! Map) return null;
    return {...Map<String, dynamic>.from(meta), 'updatedAt': json['updatedAt']};
  }

  /// Pushes the meta blob; the server keeps it only if [updatedAt] is
  /// newer than its copy (last write wins). Returns the server's newer
  /// blob (same shape as [pullMeta]) when this push lost, so the caller
  /// can adopt it; null when applied or on failure — the next sync then
  /// pushes again.
  Future<Map<String, dynamic>?> pushMeta(
    Map<String, Object?> meta,
    int updatedAt,
  ) async {
    if (!signedIn) return null;
    try {
      final json = await _api.put(
        'me/meta',
        body: {'updatedAt': updatedAt, 'meta': meta},
      );
      if (json is! Map || json['applied'] != false) return null;
      final newer = json['meta'];
      if (newer is! Map) return null;
      return {
        ...Map<String, dynamic>.from(newer),
        'updatedAt': json['updatedAt'],
      };
    } catch (e) {
      debugPrint('Meta push failed: $e');
      return null;
    }
  }

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
    } catch (e) {
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
  Future<void> saveWorkout(Workout workout) async {
    await _local.saveWorkout(workout);
    // Only custom plans sync; templates are the server's.
    if (workout.id.startsWith('custom-')) {
      putDoc('workouts', workout.id, workout.toJson());
    }
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
