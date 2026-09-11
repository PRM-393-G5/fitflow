import 'exercise.dart';

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.workoutId,
    required this.workoutName,
    required this.startedAt,
    required this.completedAt,
    required this.completedSets,
    required this.volumeKg,
    this.exercises = const [],
  });

  final String id;
  final String workoutId;
  final String workoutName;
  final DateTime startedAt;
  final DateTime completedAt;
  final int completedSets;
  final double volumeKg;

  /// The exercises actually performed, snapshotted from the plan.
  /// Empty for sessions recorded before this field existed.
  final List<Exercise> exercises;

  int get durationMinutes {
    final minutes = completedAt.difference(startedAt).inMinutes;
    return minutes < 1 ? 1 : minutes;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'workoutId': workoutId,
    'workoutName': workoutName,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'completedSets': completedSets,
    'volumeKg': volumeKg,
    'exercises': exercises.map((item) => item.toJson()).toList(),
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    workoutId: json['workoutId'] as String,
    workoutName: json['workoutName'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: DateTime.parse(json['completedAt'] as String),
    completedSets: json['completedSets'] as int,
    volumeKg: (json['volumeKg'] as num).toDouble(),
    exercises:
        (json['exercises'] as List?)
            ?.map((item) => Exercise.fromJson(item as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
