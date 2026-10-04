import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'sync_outbox.dart';

/// Delivers [SyncOutbox] writes to the API, one request at a time and in
/// queue order (so a delete never overtakes the save before it).
/// Consecutive saves of one kind go out as a single bulk request.
///
/// Delivery stops at the first transient failure (offline, 5xx, 429, an
/// expired session) and resumes on the next [flush]; a write the server
/// rejects as invalid (other 4xx) is dropped so it cannot block the rest.
class OutboxSender {
  OutboxSender(this._outbox, this._api, {required this._currentUserId});

  /// The API accepts at most 500 documents per bulk upload.
  static const batchLimit = 500;

  final SyncOutbox _outbox;
  final ApiClient _api;
  final String? Function() _currentUserId;

  Future<bool>? _running;

  /// Sends what can be sent. True when nothing of the current account is
  /// left pending. Concurrent calls share one run.
  Future<bool> flush() =>
      _running ??= _flush().whenComplete(() => _running = null);

  Future<bool> _flush() async {
    final owner = _currentUserId();
    if (owner == null) return true;
    // Another account's writes must never go out with this session.
    await _outbox.dropOthers(owner);
    while (true) {
      if (_currentUserId() != owner) return false; // switched mid-flush
      final group = _nextGroup(owner);
      if (group.isEmpty) return true;
      try {
        await _send(group);
        await _outbox.remove(group);
      } on ApiException catch (e) {
        if (_isTransient(e)) {
          debugPrint('Outbox paused: $e');
          return false;
        }
        debugPrint('Outbox dropped ${group.length} rejected write(s): $e');
        await _outbox.remove(group);
      } catch (e) {
        debugPrint('Outbox paused: $e');
        return false;
      }
    }
  }

  /// The first pending entry, plus following saves of the same kind.
  List<OutboxEntry> _nextGroup(String owner) {
    final pending = [
      for (final entry in _outbox.entries)
        if (entry.owner == owner) entry,
    ];
    if (pending.isEmpty) return const [];
    final first = pending.first;
    if (first.isDelete) return [first];
    return pending
        .takeWhile((entry) => !entry.isDelete && entry.kind == first.kind)
        .take(batchLimit)
        .toList();
  }

  Future<void> _send(List<OutboxEntry> group) async {
    final first = group.first;
    final path = 'me/docs/${first.kind}';
    if (first.isDelete) {
      await _api.delete('$path/${Uri.encodeComponent(first.id)}');
    } else if (group.length == 1) {
      await _api.put(
        '$path/${Uri.encodeComponent(first.id)}',
        body: first.body,
      );
    } else {
      await _api.put(
        path,
        body: {
          'docs': [
            for (final entry in group) {...?entry.body, 'id': entry.id},
          ],
        },
      );
    }
  }

  static bool _isTransient(ApiException e) {
    final status = e.statusCode;
    return status == null || status == 401 || status == 429 || status >= 500;
  }
}
