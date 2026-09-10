class BodyWeightEntry {
  const BodyWeightEntry({required this.date, required this.weightKg});

  final DateTime date;
  final double weightKg;

  Map<String, Object> toJson() => {
    'date': date.toIso8601String(),
    'weightKg': weightKg,
  };

  factory BodyWeightEntry.fromJson(Map<String, dynamic> json) =>
      BodyWeightEntry(
        date: DateTime.parse(json['date'] as String),
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}
