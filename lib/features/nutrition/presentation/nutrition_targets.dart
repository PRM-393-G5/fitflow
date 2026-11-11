import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/meal_plan.dart';

/// Today's TDEE and targets — or, when there are none, why.
typedef TodayTargets = ({
  double? tdee,
  DailyTargets? targets,
  NoTargets? missing,
});

/// Why there are no calorie targets.
enum NoTargets {
  /// Height, age or a logged weight is missing.
  profile,

  /// Under 18: FitFlow sets no calorie targets
  /// ([BodyMetrics.adultFormulasApply]).
  minor,
}

/// TDEE and today's targets from the body profile and latest weight —
/// or, when there are none, why ([NoTargets]). The one place that decides
/// it; the Nutrition page and Home both read it.
TodayTargets todayTargets(AppController controller) {
  final height = controller.heightCm;
  final age = controller.age;
  final weight = controller.weightEntries.isEmpty
      ? null
      : controller.weightEntries.last.weightKg;
  const minor = (tdee: null, targets: null, missing: NoTargets.minor);
  // A known under-18 age needs no profile check: there are no targets.
  if (!BodyMetrics.adultFormulasApply(age)) return minor;
  if (height == null || age == null || weight == null) {
    return (tdee: null, targets: null, missing: NoTargets.profile);
  }
  final tdee = BodyMetrics.tdee(
    weightKg: weight,
    heightCm: height,
    age: age,
    isMale: controller.isMale,
    activityLevel: controller.activityLevel,
  );
  final targets = NutritionTargets.daily(
    tdee: tdee,
    goal: controller.goal,
    weightKg: weight,
    heightCm: height,
    age: age,
    isMale: controller.isMale,
  );
  return (tdee: tdee, targets: targets, missing: null);
}

/// Colors of the protein / carbs / fat bars.
abstract final class MacroColors {
  static const protein = Color(0xFF2563EB);
  static const carbs = Color(0xFFF59E0B);
  static const fat = Color(0xFFEC4899);
}

/// Kilocalories against a target, shared by the day summary, the
/// suggested menu and Home.
class KcalProgress extends StatelessWidget {
  const KcalProgress({super.key, required this.eaten, required this.target});

  final int eaten;
  final int target;

  // 0 / 0 is NaN, which clamp passes through.
  @override
  Widget build(BuildContext context) => FDeterminateProgress(
    value: target <= 0 ? 0 : (eaten / target).clamp(0.0, 1.0),
  );
}
