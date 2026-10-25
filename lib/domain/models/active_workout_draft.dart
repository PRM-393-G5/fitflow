import 'dart:convert';

import 'exercise.dart';
import 'workout.dart';

/// Persisted snapshot of an in-progress workout session so the user can
/// resume where they left off if the app is closed or killed mid-workout.
class ActiveWorkoutDraft {
  const ActiveWorkoutDraft({
    required this.workout,
    required this.startedAt,
    required this.exerciseIndex,
    required this.setIndex,
    required this.done,
    required this.entries,
    required this.log,
    this.skippedExercises = const {},
    this.restEndsAt,
  });

  /// Snapshot of the workout plan (including any extra sets added mid-session).
  final Workout workout;
  final DateTime startedAt;
  final int exerciseIndex;
  final int setIndex;
  final bool done;

  /// Logged sets keyed by exercise index in [workout.exercises].
  final Map<int, List<SetEntry>> entries;

  /// Chronological `(exerciseIndex, setIndex)` pairs for "Undo last set".
  final List<(int, int)> log;

  /// Indices of exercises skipped by the user during this session.
  final Set<int> skippedExercises;

  /// Wall-clock time when the active rest timer ends, if resting.
  final DateTime? restEndsAt;

  int get completedSets => log.length;

  int get totalSets {
    var total = 0;
    for (final (index, item) in workout.exercises.indexed) {
      if (skippedExercises.contains(index)) {
        total += entries[index]?.length ?? 0;
      } else if (item.sets > 0) {
        total += item.sets;
      }
    }
    return total;
  }

  Map<String, Object?> toJson() => {
    'workout': workout.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'exerciseIndex': exerciseIndex,
    'setIndex': setIndex,
    'done': done,
    'entries': {
      for (final MapEntry(:key, :value) in entries.entries)
        '$key': [for (final set in value) set.toJson()],
    },
    'log': [
      for (final (ex, set) in log) [ex, set],
    ],
    'skippedExercises': skippedExercises.toList()..sort(),
    'restEndsAt': ?restEndsAt?.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  static ActiveWorkoutDraft? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ActiveWorkoutDraft.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  factory ActiveWorkoutDraft.fromJson(Map<String, dynamic> json) {
    final workout = Workout.fromJson(json['workout'] as Map<String, dynamic>);
    final count = workout.exercises.length;
    if (count == 0) {
      throw const FormatException('Draft workout has no exercises');
    }
    final rawEntries = json['entries'] as Map<String, dynamic>? ?? const {};
    final entries = <int, List<SetEntry>>{};
    for (final MapEntry(:key, :value) in rawEntries.entries) {
      final index = int.tryParse(key);
      if (index == null || index < 0 || index >= count || value is! List) {
        continue;
      }
      final list = [
        for (final item in value)
          if (item is Map<String, dynamic>) SetEntry.fromJson(item),
      ];
      if (list.isNotEmpty) entries[index] = list;
    }

    final rawLog = json['log'] as List? ?? const [];
    final log = <(int, int)>[];
    for (final item in rawLog) {
      if (item is List && item.length == 2) {
        final ex = item[0];
        final set = item[1];
        if (ex is int && set is int && ex >= 0 && ex < count && set >= 0) {
          log.add((ex, set));
        }
      }
    }

    final rawSkipped = json['skippedExercises'] as List? ?? const [];
    final skipped = <int>{
      for (final item in rawSkipped)
        if (item is int && item >= 0 && item < count) item,
    };

    final exerciseIndex = ((json['exerciseIndex'] as int?) ?? 0).clamp(
      0,
      count - 1,
    );
    final setIndex = ((json['setIndex'] as int?) ?? 0).clamp(0, 100);
    final restRaw = json['restEndsAt'] as String?;

    return ActiveWorkoutDraft(
      workout: workout,
      startedAt: DateTime.parse(json['startedAt'] as String),
      exerciseIndex: exerciseIndex,
      setIndex: setIndex,
      done: json['done'] as bool? ?? false,
      entries: entries,
      log: log,
      skippedExercises: skipped,
      restEndsAt: restRaw == null ? null : DateTime.tryParse(restRaw),
    );
  }
}
