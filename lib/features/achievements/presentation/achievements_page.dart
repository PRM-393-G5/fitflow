import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/workout_stats.dart';

class _Badge {
  const _Badge({
    required this.icon,
    required this.title,
    required this.detail,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool unlocked;
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).sessions;
    final count = sessions.length;
    final streak = WorkoutStats.longestStreak(sessions);
    final minutes = WorkoutStats.totalMinutes(sessions);
    final volume = WorkoutStats.totalVolume(sessions);
    final weekend = sessions.any(
      (item) => item.completedAt.weekday >= DateTime.saturday,
    );

    final badges = [
      _Badge(
        icon: Icons.directions_walk,
        title: 'First steps',
        detail: 'Finish your first workout',
        unlocked: count >= 1,
      ),
      _Badge(
        icon: Icons.repeat,
        title: 'Regular',
        detail: 'Complete 5 workouts',
        unlocked: count >= 5,
      ),
      _Badge(
        icon: Icons.fitness_center,
        title: 'Committed',
        detail: 'Complete 10 workouts',
        unlocked: count >= 10,
      ),
      _Badge(
        icon: Icons.military_tech,
        title: 'Dedicated',
        detail: 'Complete 25 workouts',
        unlocked: count >= 25,
      ),
      _Badge(
        icon: Icons.workspace_premium,
        title: 'Unstoppable',
        detail: 'Complete 50 workouts',
        unlocked: count >= 50,
      ),
      _Badge(
        icon: Icons.whatshot,
        title: 'Warming up',
        detail: 'Reach a 3-day streak',
        unlocked: streak >= 3,
      ),
      _Badge(
        icon: Icons.local_fire_department,
        title: 'On fire',
        detail: 'Reach a 7-day streak',
        unlocked: streak >= 7,
      ),
      _Badge(
        icon: Icons.auto_awesome,
        title: 'Monthly beast',
        detail: 'Reach a 30-day streak',
        unlocked: streak >= 30,
      ),
      _Badge(
        icon: Icons.timer_outlined,
        title: 'Five hours',
        detail: 'Train for 300 total minutes',
        unlocked: minutes >= 300,
      ),
      _Badge(
        icon: Icons.hourglass_full,
        title: 'Endurance',
        detail: 'Train for 1,000 total minutes',
        unlocked: minutes >= 1000,
      ),
      _Badge(
        icon: Icons.monitor_weight_outlined,
        title: 'One tonne club',
        detail: 'Lift 1,000 kg of total volume',
        unlocked: volume >= 1000,
      ),
      _Badge(
        icon: Icons.weekend,
        title: 'Weekend warrior',
        detail: 'Work out on a Saturday or Sunday',
        unlocked: weekend,
      ),
    ];
    final unlockedCount = badges.where((item) => item.unlocked).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: SafeArea(
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
                    mainAxisExtent: 170,
                  ),
                  itemCount: badges.length,
                  itemBuilder: (_, index) => _BadgeCard(badge: badges[index]),
                ),
              ),
            ],
          ),
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
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Opacity(
          opacity: badge.unlocked ? 1 : 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                badge.unlocked ? badge.icon : Icons.lock_outline,
                size: 32,
                color: badge.unlocked
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              const Spacer(),
              Text(
                badge.title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(badge.detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
