/// Mifflin-St Jeor body-metric formulas shared by the metrics and
/// nutrition features.
abstract final class BodyMetrics {
  static const activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];

  static const kgPerLb = 0.453592;

  /// Plausible input ranges; anything outside is treated as a typo.
  static const minWeightKg = 20.0;
  static const maxWeightKg = 400.0;
  static const minHeightCm = 100.0;
  static const maxHeightCm = 250.0;
  static const minAge = 13;
  static const maxAge = 100;

  static double bmi({required double weightKg, required double heightCm}) {
    final meters = heightCm / 100;
    return weightKg / (meters * meters);
  }

  /// WHO adult cutoffs: underweight below, overweight and obese from.
  static const underweightBmi = 18.5;
  static const overweightBmi = 25.0;
  static const obeseBmi = 30.0;

  /// Below this age the adult BMI categories don't apply (WHO uses
  /// BMI-for-age percentiles for children and teens).
  static const adultAge = 18;

  /// Whether the adult formulas here (BMR, TDEE, BMI categories) apply
  /// at [age] — the one place that rule lives. An unknown age is treated
  /// as adult (nothing is computed without a profile anyway).
  static bool adultFormulasApply(int? age) => age == null || age >= adultAge;

  /// WHO adult BMI category; for [age] under [adultAge] a pointer to
  /// BMI-for-age instead.
  static String bmiCategory(double bmi, {int? age}) {
    if (!adultFormulasApply(age)) return 'Use BMI-for-age';
    return switch (bmi) {
      < underweightBmi => 'Underweight',
      < overweightBmi => 'Normal',
      < obeseBmi => 'Overweight',
      _ => 'Obese',
    };
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

  /// Parses a user-typed decimal, accepting a comma separator ("70,5").
  /// Null when the text is not a finite number.
  static double? parseDecimal(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }

  /// Error text for a typed body weight, or null when valid. [metric]
  /// selects the unit [text] is in. The check runs in that unit against the
  /// same rounded bounds the message shows, so "44 lb" is never rejected by
  /// an error that says 44 is allowed.
  static String? weightError(String text, {required bool metric}) {
    final value = parseDecimal(text);
    if (value == null) return 'Enter a number, e.g. ${metric ? '70.5' : '155'}';
    final unit = metric ? 'kg' : 'lb';
    final min = (metric ? minWeightKg : minWeightKg / kgPerLb).roundToDouble();
    final max = (metric ? maxWeightKg : maxWeightKg / kgPerLb).roundToDouble();
    if (value < min || value > max) {
      return 'Enter a weight between ${min.round()} and ${max.round()} $unit';
    }
    return null;
  }

  static String? heightError(String text) {
    final value = parseDecimal(text);
    if (value == null) return 'Enter your height in cm, e.g. 175';
    if (value < minHeightCm || value > maxHeightCm) {
      return 'Enter a height between ${minHeightCm.round()} and '
          '${maxHeightCm.round()} cm';
    }
    return null;
  }

  static String? ageError(String text) {
    final value = int.tryParse(text.trim());
    if (value == null) return 'Enter your age in whole years';
    if (value < minAge || value > maxAge) {
      return 'Enter an age between $minAge and $maxAge';
    }
    return null;
  }

  /// "5 ft 9 in" for imperial hints next to a cm field.
  static String feetInches(double heightCm) {
    final totalInches = (heightCm / 2.54).round();
    return '${totalInches ~/ 12} ft ${totalInches % 12} in';
  }
}
