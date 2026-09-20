import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/workout_stats.dart';
import '../../../core/widgets/app_card.dart';

class _Badge {
  const _Badge({
    required this.icon,
    required this.title,
    required this.detail,
    required this.progress,
    required this.goal,
    this.format,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// Current value toward [goal]; unlocked once it reaches it.
  final num progress;
  final num goal;

  /// Formats progress/goal numbers (e.g. unit conversion); plain by default.
  final String Function(num value)? format;

  bool get unlocked => progress >= goal;

  /// "3/5" toward a locked badge.
  String get progressLabel {
    String show(num value) => format?.call(value) ?? '${value.round()}';
    final current = progress > goal ? goal : progress;
    return '${show(current)}/${show(goal)}';
  }
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  /// Total volume for the strength badge — about 10 heavy sessions.
  static const _volumeGoalKg = 10000;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    // Empty sessions never count toward badges.
    final sessions = WorkoutStats.counted(controller.sessions).toList();
    final count = sessions.length;
    final streak = WorkoutStats.longestStreak(sessions);
    final minutes = WorkoutStats.totalMinutes(sessions);
    final volume = WorkoutStats.totalVolume(sessions);
    final weeklyGoal = controller.weeklyGoal;
    final goalWeeks = WorkoutStats.longestWeeklyGoalStreak(
      sessions,
      weeklyGoal,
    );
    final weekend = sessions.any(
      (item) => item.completedAt.weekday >= DateTime.saturday,
    );
    final metric = controller.useMetric;
    final volumeGoal = metric
        ? '10,000 kg'
        : '${_thousands(_volumeGoalKg * 2.20462)} lb';

    _Badge workouts(IconData icon, String title, int goal) => _Badge(
      icon: icon,
      title: title,
      detail: goal == 1
          ? 'Finish your first workout'
          : 'Complete $goal workouts',
      progress: count,
      goal: goal,
    );

    final badges = [
      workouts(FLucideIcons.footprints, 'First steps', 1),
      workouts(FLucideIcons.repeat, 'Regular', 5),
      workouts(FLucideIcons.dumbbell, 'Committed', 10),
      workouts(FLucideIcons.medal, 'Dedicated', 25),
      workouts(FLucideIcons.award, 'Unstoppable', 50),
      _Badge(
        icon: FLucideIcons.flame,
        title: 'Warming up',
        detail: 'Reach a 3-day streak',
        progress: streak,
        goal: 3,
      ),
      _Badge(
        icon: FLucideIcons.flame,
        title: 'On fire',
        detail: 'Reach a 7-day streak',
        progress: streak,
        goal: 7,
      ),
      _Badge(
        icon: FLucideIcons.sparkles,
        title: 'Monthly beast',
        detail: 'Hit your weekly goal ($weeklyGoal/week) 4 weeks in a row',
        progress: goalWeeks,
        goal: 4,
      ),
      _Badge(
        icon: FLucideIcons.timer,
        title: 'Five hours',
        detail: 'Train for 300 total minutes',
        progress: minutes,
        goal: 300,
      ),
      _Badge(
        icon: FLucideIcons.hourglass,
        title: 'Endurance',
        detail: 'Train for 1,000 total minutes',
        progress: minutes,
        goal: 1000,
      ),
      _Badge(
        icon: FLucideIcons.weight,
        title: 'Ten tonne club',
        detail: 'Lift $volumeGoal of total volume',
        progress: volume,
        goal: _volumeGoalKg,
        format: (kg) => _thousands(metric ? kg : kg * 2.20462),
      ),
      _Badge(
        icon: FLucideIcons.sofa,
        title: 'Weekend warrior',
        detail: 'Work out on a Saturday or Sunday',
        progress: weekend ? 1 : 0,
        goal: 1,
      ),
    ];
    final unlockedCount = badges.where((item) => item.unlocked).length;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Achievements'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$unlockedCount of ${badges.length} unlocked',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth < 500
                      ? 2
                      : constraints.maxWidth < 800
                      ? 3
                      : 4,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 190,
                ),
                itemCount: badges.length,
                itemBuilder: (_, index) => _BadgeCard(badge: badges[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final _Badge badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppCard(
      child: Opacity(
        opacity: badge.unlocked ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              badge.unlocked ? badge.icon : FLucideIcons.lock,
              size: 32,
              color: badge.unlocked ? colors.primary : colors.mutedForeground,
            ),
            const Spacer(),
            Text(
              badge.title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(badge.detail, style: Theme.of(context).textTheme.bodySmall),
            if (!badge.unlocked && badge.goal > 1) ...[
              const SizedBox(height: AppSpacing.xs),
              FDeterminateProgress(
                value: (badge.progress / badge.goal).clamp(0.0, 1.0).toDouble(),
              ),
              const SizedBox(height: 2),
              Text(
                badge.progressLabel,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 10000 → "10,000".
String _thousands(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
