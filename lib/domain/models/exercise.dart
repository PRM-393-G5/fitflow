import 'form_result.dart';

/// One actually-performed set, logged during a workout session.
/// Empty on plan templates; only populated on session snapshots.
class SetEntry {
  const SetEntry({required this.amount, this.weightKg = 0, this.form});

  /// Reps for rep-based exercises, seconds held for timed exercises.
  final int amount;
  final double weightKg;

  /// The camera form check's verdict, when the set was counted with it.
  final FormResult? form;

  SetEntry withForm(FormResult? form) =>
      SetEntry(amount: amount, weightKg: weightKg, form: form);

  SetEntry copyWith({int? amount, double? weightKg}) => SetEntry(
    amount: amount ?? this.amount,
    weightKg: weightKg ?? this.weightKg,
    form: form,
  );

  Map<String, Object> toJson() => {
    'amount': amount,
    'weightKg': weightKg,
    'form': ?form?.toJson(),
  };

  factory SetEntry.fromJson(Map<String, dynamic> json) => SetEntry(
    amount: json['amount'] as int,
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
    form: FormResult.tryParse(json['form']),
  );
}

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
    this.performedSets = const [],
  });

  final String id;
  final String name;
  final String muscleGroup;
  final int sets;
  final int reps;
  final int durationSeconds;
  final int restSeconds;
  final double weightKg;
  final List<SetEntry> performedSets;

  bool get isTimed => durationSeconds > 0;
  String get prescription =>
      isTimed ? '$sets × ${durationSeconds}s' : '$sets × $reps reps';

  /// Actual lifted volume across logged sets (0 for timed/bodyweight sets).
  double get performedVolumeKg => isTimed
      ? 0
      : performedSets.fold(0, (sum, set) => sum + set.weightKg * set.amount);

  Exercise copyWith({int? sets, List<SetEntry>? performedSets}) => Exercise(
    id: id,
    name: name,
    muscleGroup: muscleGroup,
    sets: sets ?? this.sets,
    reps: reps,
    durationSeconds: durationSeconds,
    restSeconds: restSeconds,
    weightKg: weightKg,
    performedSets: performedSets ?? this.performedSets,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'muscleGroup': muscleGroup,
    'sets': sets,
    'reps': reps,
    'durationSeconds': durationSeconds,
    'restSeconds': restSeconds,
    'weightKg': weightKg,
    'performedSets': performedSets.map((set) => set.toJson()).toList(),
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
    performedSets:
        (json['performedSets'] as List?)
            ?.map((item) => SetEntry.fromJson(item as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
