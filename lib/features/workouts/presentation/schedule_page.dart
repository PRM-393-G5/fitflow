import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/workout_category_style.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/muscle_volume.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _dayShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = context.theme.colors;
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Weekly schedule'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeekSummary(controller: controller),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tap a day to change it. Home shows today’s pick, and your '
              'training days set the weekly goal.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var weekday = 1; weekday <= 7; weekday++) ...[
              _DayRow(weekday: weekday, controller: controller),
              if (weekday < 7) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// Training days, weekly time and which muscle groups the week covers, so
/// a lopsided week (no legs day) shows at a glance.
class _WeekSummary extends StatelessWidget {
  const _WeekSummary({required this.controller});

  final AppController controller;

  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final rest = minutes % 60;
    return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final plans = [
      for (var weekday = 1; weekday <= 7; weekday++)
        if (!controller.isRestDay(weekday))
          ?controller.scheduledWorkout(weekday),
    ];
    final restDays = [
      for (var weekday = 1; weekday <= 7; weekday++)
        if (controller.isRestDay(weekday)) weekday,
    ].length;
    final minutes = plans.fold(0, (sum, plan) => sum + plan.duration.inMinutes);
    final covered = {
      for (final plan in plans) ...MuscleGroup.trainedBy(plan.exercises),
    };
    final missing = [
      for (final group in MuscleGroup.values)
        if (!covered.contains(group)) group.label,
    ];

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );

    return AppCard(
      key: const Key('schedule-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat('${plans.length}', 'training days'),
              stat(plans.isEmpty ? '0 min' : _duration(minutes), 'per week'),
              stat('$restDays', 'rest days'),
            ],
          ),
          if (plans.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Covers: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: covered.isEmpty
                        ? 'mobility and cardio only'
                        : [
                            for (final group in MuscleGroup.values)
                              if (covered.contains(group)) group.label,
                          ].join(', '),
                  ),
                ],
              ),
              style: textTheme.bodySmall,
            ),
            if (missing.isNotEmpty && covered.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'No day for ${missing.join(', ')} yet',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One day: its plan (or rest), with enough detail to plan the week from
/// this page alone. Tapping opens the picker.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.weekday, required this.controller});

  final int weekday;
  final AppController controller;

  /// The assigned plan id, or null when unassigned — including stale ids
  /// whose plan no longer exists.
  String? get _assignedId {
    if (controller.isRestDay(weekday)) return null;
    return controller.scheduledWorkout(weekday)?.id;
  }

  Future<void> _pick(BuildContext context) => showFSheet<void>(
    context: context,
    side: .btt,
    mainAxisMaxRatio: .85,
    builder: (sheetContext) {
      final colors = sheetContext.theme.colors;
      final rest = controller.isRestDay(weekday);
      final assigned = _assignedId;
      Widget? check(bool selected) =>
          selected ? Icon(FLucideIcons.check, color: colors.primary) : null;
      void choose(String? value) {
        controller.setScheduleDay(weekday, value);
        Navigator.of(sheetContext).pop();
      }

      return AppSheet(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  SchedulePage._dayNames[weekday - 1],
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.md),
                FTileGroup(
                  children: [
                    FTile(
                      key: const Key('schedule-rest'),
                      prefix: Icon(
                        FLucideIcons.moon,
                        color: colors.mutedForeground,
                      ),
                      title: const Text('Rest day'),
                      suffix: check(rest),
                      onPress: () => choose(AppController.restDay),
                    ),
                    FTile(
                      key: const Key('schedule-unassigned'),
                      prefix: Icon(
                        FLucideIcons.circleMinus,
                        color: colors.mutedForeground,
                      ),
                      title: const Text('Not planned'),
                      suffix: check(!rest && assigned == null),
                      onPress: () => choose(null),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FTileGroup(
                  children: [
                    for (final workout in controller.workouts)
                      FTile(
                        key: Key('schedule-pick-${workout.id}'),
                        prefix: Icon(
                          workoutCategoryIcon(workout.category),
                          color: workoutCategoryColor(
                            workout.category,
                            colors.primary,
                          ),
                        ),
                        title: Text(workout.name),
                        subtitle: Text(_meta(workout)),
                        suffix: check(assigned == workout.id),
                        onPress: () => choose(workout.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  static String _meta(Workout workout) =>
      '${workout.level} · ${workout.duration.inMinutes} min';

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final rest = controller.isRestDay(weekday);
    final workout = rest ? null : controller.scheduledWorkout(weekday);
    final isToday = clock.now().weekday == weekday;
    final accent = workout == null
        ? colors.mutedForeground
        : workoutCategoryColor(workout.category, colors.primary);
    final groups = workout == null
        ? const <MuscleGroup>{}
        : MuscleGroup.trainedBy(workout.exercises);

    final IconData icon;
    final String title;
    final String subtitle;
    if (workout != null) {
      icon = workoutCategoryIcon(workout.category);
      title = workout.name;
      subtitle = _meta(workout);
    } else if (rest) {
      icon = FLucideIcons.moon;
      title = 'Rest day';
      subtitle = 'Recover for the next session';
    } else {
      icon = FLucideIcons.plus;
      title = 'Not planned';
      subtitle = 'Tap to pick a plan or a rest day';
    }

    return Semantics(
      button: true,
      label:
          '${SchedulePage._dayNames[weekday - 1]}'
          '${isToday ? ', today' : ''}: $title',
      excludeSemantics: true,
      child: DecoratedBox(
        key: Key('schedule-day-$weekday'),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday ? accent : colors.border,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: FTappable(
          onPress: () => _pick(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Text(
                        SchedulePage._dayShort[weekday - 1],
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isToday ? accent : colors.mutedForeground,
                        ),
                      ),
                      if (isToday)
                        Text(
                          'Today',
                          style: textTheme.labelSmall?.copyWith(color: accent),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: workout == null
                        ? colors.muted
                        : accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: workout == null
                              ? colors.mutedForeground
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (groups.isNotEmpty)
                        Text(
                          [
                            for (final group in MuscleGroup.values)
                              if (groups.contains(group)) group.label,
                          ].join(' · '),
                          style: textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  FLucideIcons.chevronRight,
                  size: 18,
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
