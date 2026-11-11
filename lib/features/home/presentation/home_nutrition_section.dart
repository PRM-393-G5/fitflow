import 'package:clock/clock.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/meal_plan.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import '../../nutrition/presentation/log_meal_page.dart';
import '../../nutrition/presentation/meal_type_picker.dart';
import '../../nutrition/presentation/nutrition_targets.dart';

/// Home's lead section: today's calories and macros against the target,
/// and one tile per meal to log it in a tap.
class HomeNutritionSection extends StatelessWidget {
  const HomeNutritionSection({super.key, this.onOpenNutrition});

  /// Opens the full Nutrition tab; the "See all" link is hidden when null.
  final VoidCallback? onOpenNutrition;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final now = clock.now();
    final entries = controller.foodLog.entriesOn(now);
    final eaten = FoodLog.totals(entries.map((entry) => entry.meal));
    final (tdee: _, :targets, :missing) = todayTargets(controller);
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Today’s nutrition',
          action: onOpenNutrition == null
              ? null
              : FButton(
                  key: const Key('home-open-nutrition'),
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: onOpenNutrition,
                  suffix: const Icon(FLucideIcons.chevronRight, size: 16),
                  child: const Text('See all'),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          key: const Key('home-nutrition'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: targets == null
                          ? '${eaten.kcal} kilocalories eaten today'
                          : '${eaten.kcal} of ${targets.kcal} kilocalories '
                                'eaten today',
                      excludeSemantics: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            thousands(eaten.kcal),
                            style: textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              targets == null
                                  ? 'kcal eaten'
                                  : '/ ${thousands(targets.kcal)} kcal',
                              style: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  FButton(
                    key: const Key('home-log-meal'),
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () =>
                        _logTo(context, controller, defaultMealType(now)),
                    prefix: const Icon(FLucideIcons.plus, size: 16),
                    child: const Text('Log meal'),
                  ),
                ],
              ),
              if (targets != null) ...[
                const SizedBox(height: AppSpacing.sm),
                KcalProgress(eaten: eaten.kcal, target: targets.kcal),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  eaten.kcal <= targets.kcal
                      ? '${thousands(targets.kcal - eaten.kcal)} kcal to go'
                      : '${thousands(eaten.kcal - targets.kcal)} kcal above '
                            'target',
                  style: muted,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              MacroRow(eaten: eaten, targets: targets),
              if (missing == NoTargets.profile) ...[
                const SizedBox(height: AppSpacing.sm),
                FTappable(
                  key: const Key('home-nutrition-profile-needed'),
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BodyMetricsPage(),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FLucideIcons.target,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Set up your body profile to get a calorie target',
                          style: textTheme.bodySmall,
                        ),
                      ),
                      Icon(
                        FLucideIcons.chevronRight,
                        size: 16,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _MealTiles(
                kcalOf: {
                  for (final type in mealTypes)
                    type: FoodLog.totals(
                      entries
                          .map((entry) => entry.meal)
                          .where((meal) => mealTypeOf(meal) == type),
                    ).kcal,
                },
                logged: {for (final entry in entries) mealTypeOf(entry.meal)},
                onTap: (type) => _logTo(context, controller, type),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the log page for [type] and adds the result to today.
  Future<void> _logTo(
    BuildContext context,
    AppController controller,
    String type,
  ) async {
    final meal = await LogMealPage.open(
      context,
      type: type,
      log: controller.foodLog,
    );
    if (meal != null) await controller.logMeal(clock.now(), meal);
  }
}

/// Breakfast / Lunch / Dinner / Snack: two by two on phones, one row on
/// wider screens.
class _MealTiles extends StatelessWidget {
  const _MealTiles({
    required this.kcalOf,
    required this.logged,
    required this.onTap,
  });

  final Map<String, int> kcalOf;

  /// Meal types with at least one entry today (a 0 kcal entry counts).
  final Set<String> logged;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tiles = [
        for (final type in mealTypes)
          Expanded(
            child: _MealTile(
              type: type,
              kcal: logged.contains(type) ? kcalOf[type] : null,
              onTap: () => onTap(type),
            ),
          ),
      ];
      if (constraints.maxWidth >= 500) {
        return Row(spacing: AppSpacing.sm, children: tiles);
      }
      return Column(
        spacing: AppSpacing.sm,
        children: [
          Row(spacing: AppSpacing.sm, children: tiles.sublist(0, 2)),
          Row(spacing: AppSpacing.sm, children: tiles.sublist(2)),
        ],
      );
    },
  );
}

class _MealTile extends StatelessWidget {
  const _MealTile({
    required this.type,
    required this.kcal,
    required this.onTap,
  });

  final String type;

  /// Kilocalories logged for [type] today; null when nothing is logged.
  final int? kcal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final done = kcal != null;
    return Semantics(
      button: true,
      label: done ? '$type, $kcal kilocalories' : 'Log $type',
      excludeSemantics: true,
      child: FTappable(
        key: Key('home-meal-$type'),
        onPress: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: done ? colors.secondary : null,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  mealIcon(type),
                  size: 18,
                  color: done ? colors.primary : colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type, style: textTheme.labelMedium),
                      Text(
                        done ? '${thousands(kcal!)} kcal' : 'Add',
                        style: textTheme.bodySmall?.copyWith(
                          color: done ? null : colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!done)
                  Icon(
                    FLucideIcons.plus,
                    size: 16,
                    color: colors.mutedForeground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
