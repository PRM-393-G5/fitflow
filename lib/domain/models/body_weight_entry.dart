class BodyWeightEntry {
  /// [date] is reduced to a local calendar day — one entry per day.
  BodyWeightEntry({required DateTime date, required this.weightKg})
    : date = DateTime(date.year, date.month, date.day);

  final DateTime date;
  final double weightKg;

  /// Stable per-day id (`yyyy-mm-dd`), used to merge and sync entries.
  String get id =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, Object> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'weightKg': weightKg,
  };

  /// Older entries stored a UTC-midnight timestamp; its calendar fields
  /// still name the intended day, so they are read before normalizing.
  factory BodyWeightEntry.fromJson(Map<String, dynamic> json) =>
      BodyWeightEntry(
        date: DateTime.parse(json['date'] as String),
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}
