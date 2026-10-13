import '../../../domain/load_math.dart';

/// Weight entry in the user's unit system. Weights are always stored in kg;
/// forms show and accept kg or lb depending on `AppController.useMetric`.
abstract final class WeightUnits {
  static const lbPerKg = LoadMath.lbPerKg;

  /// Heaviest weight any form accepts, in kg. Unbounded input (e.g. 1e308)
  /// would overflow rounding and JSON downstream.
  static const maxKg = 1000.0;

  static String label(bool metric) => metric ? 'kg' : 'lb';

  static double toDisplay(double kg, bool metric) => metric ? kg : kg * lbPerKg;

  static double toKg(double value, bool metric) =>
      metric ? value : value / lbPerKg;

  /// [kg] in the display unit, at most one decimal ("20", "44.1").
  static String format(double kg, bool metric) =>
      formatNumber(toDisplay(kg, metric));

  /// Largest value accepted in the display unit: [maxKg] rounded down to
  /// the one decimal shown, so the message and the check agree.
  static double maxInput(bool metric) =>
      (toDisplay(maxKg, metric) * 10).floorToDouble() / 10;

  /// "1000 kg" / "2204.6 lb", for field errors.
  static String maxLabel(bool metric) =>
      '${formatNumber(maxInput(metric))} ${label(metric)}';

  static String formatNumber(double value) {
    // Beyond int range `round()` throws; such values only come from bad
    // legacy data, so show them as-is rather than crash.
    if (!value.isFinite || value.abs() >= 1e15) return '$value';
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}'
        : rounded.toStringAsFixed(1);
  }

  /// Parses a decimal typed with either '.' or ',' ("22,5"). Null when the
  /// text is not a finite number.
  static double? parseDecimal(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }
}
