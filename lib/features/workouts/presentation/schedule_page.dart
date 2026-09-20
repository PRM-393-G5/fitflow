import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';

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
  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _categoryIcons = {
    'Strength': FLucideIcons.dumbbell,
    'Cardio': FLucideIcons.flame,
    'Mobility': FLucideIcons.activity,
  };
  static const _categoryColors = {
    'Strength': Color(0xFF3B82F6),
    'Cardio': Color(0xFFF97316),
    'Mobility': Color(0xFF22C55E),
  };

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Weekly schedule'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assign a plan to each day. Home shows today\u2019s pick.',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              spacing: AppSpacing.xs,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  _DayCell(
                    weekday: weekday,
                    label: _dayShort[weekday - 1],
                    controller: controller,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              spacing: AppSpacing.md,
              children: [
                for (final category in _categoryIcons.keys)
                  _Legend(
                    icon: _categoryIcons[category]!,
                    color: _categoryColors[category]!,
                    label: category,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.weekday,
    required this.label,
    required this.controller,
  });

  final int weekday;
  final String label;
  final AppController controller;

  Future<void> _pick(BuildContext context) {
    final colors = context.theme.colors;
    return showAppDialog<void>(
      context: context,
      title: SchedulePage._dayNames[weekday - 1],
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: FTileGroup(
            children: [
              FTile(
                prefix: Icon(FLucideIcons.moon, color: colors.mutedForeground),
                title: const Text('Rest'),
                suffix: controller.schedule[weekday] == null
                    ? Icon(FLucideIcons.check, color: colors.primary)
                    : null,
                onPress: () {
                  controller.setScheduleDay(weekday, null);
                  Navigator.of(context).pop();
                },
              ),
              for (final workout in controller.workouts)
                FTile(
                  prefix: Icon(
                    SchedulePage._categoryIcons[workout.category] ??
                        FLucideIcons.dumbbell,
                    color:
                        SchedulePage._categoryColors[workout.category] ??
                        colors.primary,
                  ),
                  title: Text(workout.name),
                  suffix: controller.schedule[weekday] == workout.id
                      ? Icon(FLucideIcons.check, color: colors.primary)
                      : null,
                  onPress: () {
                    controller.setScheduleDay(weekday, workout.id);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final workout = controller.scheduledWorkout(weekday);
    final color =
        SchedulePage._categoryColors[workout?.category] ?? colors.primary;
    final isToday = DateTime.now().weekday == weekday;
    return Expanded(
      child: FTappable(
        onPress: () => _pick(context),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: isToday ? .bold : null,
                color: isToday ? color : colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: workout == null
                    ? colors.muted
                    : color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: isToday
                    ? Border.all(color: color, width: 1.5)
                    : Border.all(color: colors.border),
              ),
              child: Center(
                child: Icon(
                  workout == null
                      ? FLucideIcons.moon
                      : (SchedulePage._categoryIcons[workout.category] ??
                            FLucideIcons.dumbbell),
                  size: 18,
                  color: workout == null ? colors.mutedForeground : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 4,
    children: [
      Icon(icon, size: 14, color: color),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
