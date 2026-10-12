/// Comparisons on stored loads.
///
/// Weights are stored in kg but may be typed in lb: 60 kg shows as
/// "132.3 lb", and re-typing that stores 60.0103 kg. Anything within
/// [toleranceKg] is the same load, so unit round trips never count as
/// heavier (or as a new record).
abstract final class LoadMath {
  /// Largest difference still treated as the same load; lb display
  /// rounding stays within about 0.023 kg.
  static const toleranceKg = 0.05;

  /// Whether [kg] is heavier than [thanKg] by more than the tolerance.
  static bool heavier(double kg, double thanKg) => kg > thanKg + toleranceKg;

  /// Whether a set volume ([kg] × [reps]) beats [thanKg] by more than the
  /// tolerance carried through every rep.
  static bool moreVolume(double kg, int reps, double thanKg) =>
      kg * reps > thanKg + toleranceKg * reps;
}
