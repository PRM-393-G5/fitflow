/// Merge rules shared by the cloud repositories (Firestore today, the
/// FitFlow API next): documents merge by id, the server copy wins.
class SyncMerge {
  const SyncMerge._();

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

  /// Applies local changes made while a sync was in flight to its result:
  /// [merged] was computed from [before]; [after] is the local state now.
  /// Items added or edited since (a different object than in [before])
  /// keep the local copy; items deleted since are dropped; untouched items
  /// take the merged copy (or disappear if the cloud tombstoned them).
  static List<T> reconcile<T>(
    List<T> merged,
    List<T> before,
    List<T> after,
    String Function(T) idOf,
  ) {
    final beforeById = {for (final item in before) idOf(item): item};
    final afterById = {for (final item in after) idOf(item): item};
    final result = <String, T>{};
    for (final item in merged) {
      final id = idOf(item);
      if (beforeById.containsKey(id) && !afterById.containsKey(id)) continue;
      result[id] = item;
    }
    for (final MapEntry(key: id, value: item) in afterById.entries) {
      final previous = beforeById[id];
      if (previous == null || !identical(previous, item)) result[id] = item;
    }
    return result.values.toList();
  }

  /// Merges [local] JSON docs (each with an `id`) with the server's
  /// [remote] docs, where `{id, deleted: true}` marks a tombstone: remote
  /// wins on conflicts and tombstoned ids are dropped. Returns the merged
  /// docs and the ones the server does not have yet.
  static ({
    List<Map<String, dynamic>> merged,
    List<Map<String, dynamic>> toUpload,
  })
  mergeDocs(
    List<Map<String, dynamic>> local,
    Iterable<Map<String, dynamic>> remote,
  ) {
    final deleted = <String>{};
    final live = <Map<String, dynamic>>[];
    for (final doc in remote) {
      if (doc['deleted'] == true) {
        deleted.add(doc['id'] as String);
      } else {
        live.add(doc);
      }
    }
    final merged = mergeById(
      local.where((item) => !deleted.contains(item['id'])),
      live,
      (item) => item['id'] as String,
    );
    final remoteIds = {for (final item in live) item['id']};
    return (
      merged: merged,
      toUpload: merged
          .where((item) => !remoteIds.contains(item['id']))
          .toList(),
    );
  }
}
