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
import '../../../data/openai_service.dart';
import '../../nutrition/presentation/add_meal_choice.dart';
import '../../nutrition/presentation/log_meal_page.dart';
import '../../nutrition/presentation/meal_type_picker.dart';
import '../../nutrition/presentation/nutrition_targets.dart';

/// Home's lead section: today's calories and macros against the target,
/// and one tile per meal to log it in a tap.
class HomeNutritionSection extends StatelessWidget {
  const HomeNutritionSection({
    super.key,
    this.onOpenNutrition,
    this.onMealPhoto,
  });

  /// Opens the full Nutrition tab; the "See all" link is hidden when null.
  final VoidCallback? onOpenNutrition;

  /// Hands a meal photo to the Nutrition tab; see [HomePage.onMealPhoto].
  final ValueChanged<MealPhotoRequest>? onMealPhoto;

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
                  _KcalRing(eaten: eaten.kcal, target: targets?.kcal),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _MacroBars(eaten: eaten, targets: targets),
                  ),
                ],
              ),
              if (missing == NoTargets.profile) ...[
                const SizedBox(height: AppSpacing.md),
                _ProfilePrompt(
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BodyMetricsPage(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // Side by side; with large text the button wraps below.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Text(
                    targets == null
                        ? '${entries.length} ${entries.length == 1 ? 'meal' : 'meals'} logged'
                        : eaten.kcal <= targets.kcal
                        ? '${thousands(targets.kcal - eaten.kcal)} kcal to go'
                        : '${thousands(eaten.kcal - targets.kcal)} kcal above '
                              'target',
                    style: muted,
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
                onTap: (type) => _addTo(context, controller, type),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Asks how to add a meal to [type], as the Nutrition tab does: a photo
  /// goes to that tab (where its analysis is shown), manual entry opens
  /// the log page here.
  Future<void> _addTo(
    BuildContext context,
    AppController controller,
    String type,
  ) async {
    final photo = onMealPhoto;
    final choice = await showAddMealChoice(
      context,
      type: type,
      photosEnabled: OpenAiService.configured && photo != null,
    );
    if (!context.mounted) return;
    switch (choice) {
      case AddMealChoice.manual:
        await _logTo(context, controller, type);
      // Camera or gallery; only offered when there is somewhere to send it.
      case final AddMealChoice via when photo != null:
        photo((type: type, via: via));
      default:
        break;
    }
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
      // excludeSemantics drops the tappable's own action, so give it here.
      onTap: onTap,
      label: done ? '$type, $kcal kilocalories' : 'Add $type',
      excludeSemantics: true,
      child: FTappable(
        key: Key('home-meal-$type'),
        onPress: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: done ? colors.secondary : null,
            border: Border.all(color: done ? colors.secondary : colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: done ? colors.primary : colors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      mealIcon(type),
                      size: 16,
                      color: done
                          ? colors.primaryForeground
                          : colors.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        done ? '${thousands(kcal!)} kcal' : 'Add',
                        style: textTheme.bodySmall?.copyWith(
                          color: done
                              ? colors.foreground
                              : colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kilocalories eaten in the middle of a ring that fills toward today's
/// target; without a target the ring stays empty.
class _KcalRing extends StatelessWidget {
  const _KcalRing({required this.eaten, required this.target});

  final int eaten;
  final int? target;

  static const _size = 104.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final goal = target;
    // 0 / 0 is NaN, which clamp passes through.
    final progress = goal == null || goal <= 0
        ? 0.0
        : (eaten / goal).clamp(0.0, 1.0);
    return Semantics(
      label: goal == null
          ? '$eaten kilocalories eaten today'
          : '$eaten of $goal kilocalories eaten today',
      excludeSemantics: true,
      child: SizedBox.square(
        key: const Key('home-kcal-ring'),
        dimension: _size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: colors.secondary,
              color: colors.primary,
            ),
            // Large text scales shrink to fit inside the ring.
            Padding(
              padding: const EdgeInsets.all(14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      thousands(eaten),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      goal == null ? 'kcal eaten' : 'of ${thousands(goal)}',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Protein / carbs / fat as label, grams and a thin bar each; the bar
/// fills toward the target when there is one.
class _MacroBars extends StatelessWidget {
  const _MacroBars({required this.eaten, required this.targets});

  final ({int kcal, double proteinG, double carbsG, double fatG}) eaten;
  final DailyTargets? targets;

  @override
  Widget build(BuildContext context) => Column(
    spacing: AppSpacing.sm,
    children: [
      _bar(
        context,
        'Protein',
        eaten.proteinG,
        targets?.proteinG,
        MacroColors.protein,
      ),
      _bar(context, 'Carbs', eaten.carbsG, targets?.carbsG, MacroColors.carbs),
      _bar(context, 'Fat', eaten.fatG, targets?.fatG, MacroColors.fat),
    ],
  );

  Widget _bar(
    BuildContext context,
    String label,
    double grams,
    int? target,
    Color color,
  ) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final progress = target == null || target <= 0
        ? 0.0
        : (grams / target).clamp(0.0, 1.0);
    // One announcement per macro instead of a label, a number and an
    // unnamed progress bar read separately.
    return Semantics(
      label:
          '$label ${grams.round()}'
          '${target == null ? '' : ' of $target'} grams',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ),
              // Narrow screens and large text: the grams shrink rather than
              // overflow the row.
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    target == null
                        ? '${grams.round()} g'
                        : '${grams.round()} / $target g',
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: colors.secondary,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tinted call to set up the body profile, the one thing missing for a
/// calorie target.
class _ProfilePrompt extends StatelessWidget {
  const _ProfilePrompt({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      key: const Key('home-nutrition-profile-needed'),
      onPress: onPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md - AppSpacing.xs,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Icon(FLucideIcons.target, size: 18, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Set up your body profile to get a calorie target',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(FLucideIcons.chevronRight, size: 16, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
