import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
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

/// Protein / carbs / fat eaten, each against its target when there is one.
class MacroRow extends StatelessWidget {
  const MacroRow({super.key, required this.eaten, this.targets});

  final ({int kcal, double proteinG, double carbsG, double fatG}) eaten;
  final DailyTargets? targets;

  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.md,
    children: [
      _macro(
        context,
        'Protein',
        eaten.proteinG,
        MacroColors.protein,
        targets?.proteinG,
      ),
      _macro(
        context,
        'Carbs',
        eaten.carbsG,
        MacroColors.carbs,
        targets?.carbsG,
      ),
      _macro(context, 'Fat', eaten.fatG, MacroColors.fat, targets?.fatG),
    ],
  );

  Widget _macro(
    BuildContext context,
    String label,
    double grams,
    Color color, [
    int? target,
  ]) {
    final colors = context.theme.colors;
    return Expanded(
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 4, height: 32),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: colors.mutedForeground),
                ),
                Text(
                  target == null
                      ? '${grams.round()} g'
                      : '${grams.round()} / $target g',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
