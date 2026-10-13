import 'weight_units.dart';

/// Parsing and limits for one set's reps (or seconds) and weight, shared
/// by the workout screen and Edit session so both accept the same input.
abstract final class SetInput {
  static const maxReps = 1000;
  static const maxSeconds = 3600;

  /// Reps, or seconds for [timed] sets, from [text]; an error when it is
  /// not a whole number within the limits.
  static ({int? value, String? error}) amount(
    String text, {
    required bool timed,
  }) {
    final value = int.tryParse(text.trim());
    final max = timed ? maxSeconds : maxReps;
    final error = value == null || value < 1
        ? (timed ? 'Enter at least 1 second' : 'Enter at least 1 rep')
        : value > max
        ? (timed ? 'Max $max seconds' : 'Max $max reps')
        : null;
    return (value: error == null ? value : null, error: error);
  }

  /// The weight in [text] (display unit; blank = bodyweight) in kg. Text
  /// still equal to [prefillText] keeps [prefillKg] exactly, so a weight
  /// shown rounded in lb is never re-rounded.
  static ({double? kg, String? error}) weight(
    String text, {
    required bool metric,
    String prefillText = '',
    double prefillKg = 0,
  }) {
    final trimmed = text.trim();
    if (trimmed == prefillText) return (kg: prefillKg, error: null);
    final value = trimmed.isEmpty ? 0.0 : WeightUnits.parseDecimal(trimmed);
    final error = value == null || value < 0
        ? 'Enter 0 or more'
        : value > WeightUnits.maxInput(metric)
        ? 'Max ${WeightUnits.maxLabel(metric)}'
        : null;
    return (
      kg: error == null ? WeightUnits.toKg(value!, metric) : null,
      error: error,
    );
  }
}
