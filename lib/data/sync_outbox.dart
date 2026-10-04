import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One write waiting to reach the server.
class OutboxEntry {
  const OutboxEntry({
    required this.owner,
    required this.kind,
    required this.id,
    this.body,
  });

  /// Account that made the write; entries of another account are never
  /// sent with the current session.
  final String owner;

  /// `sessions`, `workouts` or `weights`.
  final String kind;
  final String id;

  /// The document to store, or null for a delete.
  final Map<String, dynamic>? body;

  bool get isDelete => body == null;

  Map<String, Object?> toJson() => {
    'owner': owner,
    'kind': kind,
    'id': id,
    'body': body,
  };

  static OutboxEntry? tryParse(Object? json) {
    if (json is! Map) return null;
    final owner = json['owner'];
    final kind = json['kind'];
    final id = json['id'];
    final body = json['body'];
    if (owner is! String || kind is! String || id is! String) return null;
    if (body != null && body is! Map) return null;
    return OutboxEntry(
      owner: owner,
      kind: kind,
      id: id,
      body: body == null ? null : Map<String, dynamic>.from(body as Map),
    );
  }
}

/// Writes that have not reached the server yet, persisted so they survive
/// going offline and app restarts (Firestore's offline queue did this
/// before). Only the latest write per document is kept: a newer save or
/// delete of the same document replaces the pending one and moves to the
/// end, so the server always ends with the last local state.
class SyncOutbox {
  SyncOutbox(this._preferences) : _entries = _load(_preferences);

  static const _key = 'sync_outbox_v1';

  final SharedPreferences _preferences;
  final List<OutboxEntry> _entries;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  /// Pending writes of [owner] for [kind], in queue order.
  List<OutboxEntry> pendingFor(String owner, String kind) => [
    for (final entry in _entries)
      if (entry.owner == owner && entry.kind == kind) entry,
  ];

  Future<void> add(OutboxEntry entry) async {
    _entries.removeWhere((pending) => _sameDoc(pending, entry));
    _entries.add(entry);
    await _save();
  }

  Future<void> addAll(Iterable<OutboxEntry> entries) async {
    for (final entry in entries) {
      _entries.removeWhere((pending) => _sameDoc(pending, entry));
      _entries.add(entry);
    }
    await _save();
  }

  /// Removes [delivered] — but only if it is still the pending write for
  /// its document (a newer write queued meanwhile must still be sent).
  Future<void> remove(Iterable<OutboxEntry> delivered) async {
    final sent = delivered.toSet();
    _entries.removeWhere(sent.contains);
    await _save();
  }

  /// Drops every write not made by [owner] (another account's leftovers).
  Future<void> dropOthers(String owner) async {
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.owner != owner);
    if (_entries.length != before) await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    await _preferences.remove(_key);
  }

  static bool _sameDoc(OutboxEntry a, OutboxEntry b) =>
      a.owner == b.owner && a.kind == b.kind && a.id == b.id;

  Future<void> _save() => _preferences.setString(
    _key,
    jsonEncode([for (final entry in _entries) entry.toJson()]),
  );

  static List<OutboxEntry> _load(SharedPreferences preferences) {
    final raw = preferences.getString(_key);
    if (raw == null) return [];
    try {
      final json = jsonDecode(raw);
      if (json is! List) return [];
      return [for (final item in json) ?OutboxEntry.tryParse(item)];
    } on FormatException {
      return [];
    }
  }
}
