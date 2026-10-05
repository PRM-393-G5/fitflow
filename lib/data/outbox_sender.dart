import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'sync_outbox.dart';

/// Delivers [SyncOutbox] writes to the API, one request at a time and in
/// queue order (so a delete never overtakes the save before it).
/// Consecutive saves of one kind go out as a single bulk request.
///
/// Delivery stops at the first transient failure (offline, 5xx, 408, 409,
/// 429, an expired session) and resumes on the next [flush]. A bulk
/// request the server rejects (4xx, e.g. one bad document or 413) is
/// retried one document at a time, and only the documents rejected on
/// their own are dropped, so one bad write cannot block or sink the rest.
///
/// Writes of another account stay queued (they go out when that account
/// signs in again) but are never sent with the current session.
class OutboxSender {
  OutboxSender(this._outbox, this._api, {required this._currentUserId});

  /// The API accepts at most 500 documents per bulk upload.
  static const batchLimit = 500;

  final SyncOutbox _outbox;
  final ApiClient _api;
  final String? Function() _currentUserId;

  Future<bool>? _running;

  /// Sends what can be sent. True when nothing of the current account is
  /// left pending. Concurrent calls share a run; a write queued while a
  /// run was finishing triggers another one before this returns.
  Future<bool> flush() async {
    while (true) {
      final delivered = await (_running ??= _flush().whenComplete(
        () => _running = null,
      ));
      if (!delivered) return false;
      final owner = _currentUserId();
      if (owner == null || !_hasPending(owner)) return true;
    }
  }

  bool _hasPending(String owner) =>
      _outbox.entries.any((entry) => entry.owner == owner);

  Future<bool> _flush() async {
    final owner = _currentUserId();
    if (owner == null) return true;
    while (true) {
      if (_currentUserId() != owner) return false; // switched mid-flush
      final group = _nextGroup(owner);
      if (group.isEmpty) return true;
      final outcome = await _deliver(group);
      if (outcome == _Outcome.paused) return false;
      if (outcome == _Outcome.rejected && group.length > 1) {
        // Find the bad document(s) instead of dropping the whole batch.
        for (final entry in group) {
          if (_currentUserId() != owner) return false;
          final single = await _deliver([entry]);
          if (single == _Outcome.paused) return false;
          if (single == _Outcome.rejected) {
            debugPrint('Outbox dropped rejected write ${entry.id}');
          }
          await _outbox.remove([entry]);
        }
        continue;
      }
      if (outcome == _Outcome.rejected) {
        debugPrint('Outbox dropped rejected write ${group.single.id}');
      }
      await _outbox.remove(group);
    }
  }

  Future<_Outcome> _deliver(List<OutboxEntry> group) async {
    try {
      await _send(group);
      return _Outcome.sent;
    } on ApiException catch (e) {
      if (_isTransient(e)) {
        debugPrint('Outbox paused: $e');
        return _Outcome.paused;
      }
      return _Outcome.rejected;
    } catch (e) {
      debugPrint('Outbox paused: $e');
      return _Outcome.paused;
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
    return status == null ||
        const {401, 408, 409, 429}.contains(status) ||
        status >= 500;
  }
}

enum _Outcome { sent, paused, rejected }
