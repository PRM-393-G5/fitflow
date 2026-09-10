class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.sets,
    this.reps = 0,
    this.durationSeconds = 0,
    this.restSeconds = 45,
    this.weightKg = 0,
  });

  final String id;
  final String name;
  final String muscleGroup;
  final int sets;
  final int reps;
  final int durationSeconds;
  final int restSeconds;
  final double weightKg;

  bool get isTimed => durationSeconds > 0;
  String get prescription =>
      isTimed ? '$sets × ${durationSeconds}s' : '$sets × $reps reps';

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'muscleGroup': muscleGroup,
    'sets': sets,
    'reps': reps,
    'durationSeconds': durationSeconds,
    'restSeconds': restSeconds,
    'weightKg': weightKg,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    muscleGroup: json['muscleGroup'] as String,
    sets: json['sets'] as int,
    reps: json['reps'] as int? ?? 0,
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    restSeconds: json['restSeconds'] as int? ?? 45,
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
  );
}
