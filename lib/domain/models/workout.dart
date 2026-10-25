import 'exercise.dart';

class Workout {
  const Workout({
    required this.id,
    required this.name,
    required this.exercises,
    required this.duration,
    required this.level,
    required this.category,
    required this.description,
  });

  final String id;
  final String name;
  final List<Exercise> exercises;
  final Duration duration;
  final String level;
  final String category;
  final String description;

  int get totalSets => exercises.fold(0, (sum, item) => sum + item.sets);

  Workout copyWith({List<Exercise>? exercises}) => Workout(
    id: id,
    name: name,
    exercises: exercises ?? this.exercises,
    duration: duration,
    level: level,
    category: category,
    description: description,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'exercises': exercises.map((item) => item.toJson()).toList(),
    'durationMinutes': duration.inMinutes,
    'level': level,
    'category': category,
    'description': description,
  };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'] as String,
    name: json['name'] as String,
    exercises: (json['exercises'] as List)
        .map((item) => Exercise.fromJson(item as Map<String, dynamic>))
        .toList(),
    duration: Duration(minutes: json['durationMinutes'] as int),
    level: json['level'] as String,
    category: json['category'] as String,
    description: json['description'] as String,
  );
}
