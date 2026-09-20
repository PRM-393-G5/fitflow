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
              'Assign a plan or a rest day to each day. Home shows '
              'today\u2019s pick.',
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
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                for (final category in _categoryIcons.keys)
                  _Legend(
                    icon: _categoryIcons[category]!,
                    color: _categoryColors[category]!,
                    label: category,
                  ),
                _Legend(
                  icon: FLucideIcons.moon,
                  color: context.theme.colors.mutedForeground,
                  label: 'Rest',
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

  /// The assigned plan id, or null when unassigned — including stale ids
  /// whose plan no longer exists.
  String? get _assignedId {
    if (controller.isRestDay(weekday)) return null;
    return controller.scheduledWorkout(weekday)?.id;
  }

  Future<void> _pick(BuildContext context) {
    final colors = context.theme.colors;
    final rest = controller.isRestDay(weekday);
    final assigned = _assignedId;
    Widget? check(bool selected) =>
        selected ? Icon(FLucideIcons.check, color: colors.primary) : null;
    void choose(String? value) {
      controller.setScheduleDay(weekday, value);
      Navigator.of(context).pop();
    }

    return showAppDialog<void>(
      context: context,
      title: SchedulePage._dayNames[weekday - 1],
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: FTileGroup(
            children: [
              FTile(
                key: const Key('schedule-rest'),
                prefix: Icon(FLucideIcons.moon, color: colors.mutedForeground),
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
                title: const Text('Unassigned'),
                suffix: check(!rest && assigned == null),
                onPress: () => choose(null),
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
                  suffix: check(assigned == workout.id),
                  onPress: () => choose(workout.id),
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
    final textTheme = Theme.of(context).textTheme;
    final rest = controller.isRestDay(weekday);
    final workout = rest ? null : controller.scheduledWorkout(weekday);
    final color =
        SchedulePage._categoryColors[workout?.category] ?? colors.primary;
    final isToday = DateTime.now().weekday == weekday;
    final foreground = workout == null ? colors.mutedForeground : color;
    final IconData icon;
    final String text;
    if (workout != null) {
      icon =
          SchedulePage._categoryIcons[workout.category] ??
          FLucideIcons.dumbbell;
      text = workout.name;
    } else if (rest) {
      icon = FLucideIcons.moon;
      text = 'Rest';
    } else {
      icon = FLucideIcons.plus;
      text = 'Unassigned';
    }
    return Expanded(
      child: Semantics(
        button: true,
        label: '${SchedulePage._dayNames[weekday - 1]}: $text',
        excludeSemantics: true,
        child: FTappable(
          onPress: () => _pick(context),
          child: Column(
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: isToday ? .bold : null,
                  color: isToday ? color : colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                height: 76,
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: workout == null
                      ? colors.muted
                      : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: isToday
                      ? Border.all(color: color, width: 1.5)
                      : Border.all(color: colors.border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        height: 1.1,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      Icon(icon, size: 14, color: color),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
