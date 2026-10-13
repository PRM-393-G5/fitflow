/// Comparisons and rounding on stored loads.
///
/// Weights are stored in kg but may be typed in lb: 60 kg shows as
/// "132.3 lb", and re-typing that stores 60.0103 kg. Anything within
/// [toleranceKg] is the same load, so unit round trips never count as
/// heavier (or as a new record).
abstract final class LoadMath {
  /// Largest difference still treated as the same load; lb display
  /// rounding stays within about 0.023 kg.
  static const toleranceKg = 0.05;

  static const lbPerKg = 2.20462;

  /// Whether [kg] is heavier than [thanKg] by more than the tolerance.
  static bool heavier(double kg, double thanKg) => kg > thanKg + toleranceKg;

  /// Whether [a] and [b] are the same load within the tolerance.
  static bool same(double a, double b) => (a - b).abs() <= toleranceKg;

  /// Smallest load change a gym offers at [load] (in the display unit):
  /// light dumbbells go up 1 kg / 2.5 lb, barbells and heavier dumbbells
  /// 2.5 kg / 5 lb.
  static double step(double load, {required bool metric}) =>
      metric ? (load < 20 ? 1 : 2.5) : (load < 45 ? 2.5 : 5);

  /// [kg] raised by [fraction] of itself, rounded to a load the gym has:
  /// the increase is rounded to whole steps (at least one), and the result
  /// lands on the step grid of the user's unit — 4 kg → 5 kg, 60 kg →
  /// 62.5 kg, 60 kg shown as 132.3 lb → 135 lb.
  static double increase(double kg, double fraction, {required bool metric}) {
    final perKg = metric ? 1.0 : lbPerKg;
    final shown = kg * perKg;
    final unit = step(shown, metric: metric);
    final increment = _atLeastOne((shown * fraction / unit).round()) * unit;
    var next = _snap(
      shown + increment,
      step(shown + increment, metric: metric),
    );
    if (next <= shown + toleranceKg * perKg) next += unit;
    return next / perKg;
  }

  /// [kg] cut by [fraction], rounded to the nearest load on the step grid
  /// (11 kg − 10% → 10 kg, not 9); null when the load is too light to cut
  /// (two steps or less) or rounding would leave it unchanged.
  static double? reduce(double kg, double fraction, {required bool metric}) {
    final perKg = metric ? 1.0 : lbPerKg;
    final shown = kg * perKg;
    if (shown <= 2 * step(shown, metric: metric)) return null;
    final target = shown * (1 - fraction);
    final next = _snap(target, step(target, metric: metric));
    if (next <= 0 || next >= shown - toleranceKg * perKg) return null;
    return next / perKg;
  }

  /// [kg] rounded to the nearest load on the step grid of the user's unit.
  static double round(double kg, {required bool metric}) {
    final perKg = metric ? 1.0 : lbPerKg;
    final shown = kg * perKg;
    return _snap(shown, step(shown, metric: metric)) / perKg;
  }

  static int _atLeastOne(int steps) => steps < 1 ? 1 : steps;

  static double _snap(double load, double unit) => (load / unit).round() * unit;
}
