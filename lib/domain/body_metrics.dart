/// Mifflin-St Jeor body-metric formulas shared by the metrics and
/// nutrition features.
abstract final class BodyMetrics {
  static const activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];

  static double bmi({required double weightKg, required double heightCm}) {
    final meters = heightCm / 100;
    return weightKg / (meters * meters);
  }

  static double bmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required bool isMale,
  }) => 10 * weightKg + 6.25 * heightCm - 5 * age + (isMale ? 5 : -161);

  static double tdee({
    required double weightKg,
    required double heightCm,
    required int age,
    required bool isMale,
    required int activityLevel,
  }) =>
      bmr(weightKg: weightKg, heightCm: heightCm, age: age, isMale: isMale) *
      activityFactors[activityLevel.clamp(0, activityFactors.length - 1)];
}
