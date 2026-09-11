import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../domain/workout_stats.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import '../../workouts/presentation/schedule_page.dart';
import '../../workouts/presentation/workout_detail_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final today = controller.suggestedWorkout();
    final weekly = WorkoutStats.sessionsThisWeek(controller.sessions);
    final weekMinutes = controller.sessions
        .where((item) => DateTime.now().difference(item.completedAt).inDays < 7)
        .fold(0, (sum, item) => sum + item.durationMinutes);

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Ready to move?',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Today’s workout',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Edit weekly schedule',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_calendar_outlined),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SchedulePage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          today?.name ?? 'No plan available',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (today != null) ...[
                          Text(
                            '${today.duration.inMinutes} min • ${today.level}',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    WorkoutDetailPage(workout: today),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Quick start'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Icon(Icons.directions_run, size: 64),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              key: const Key('open-squat-form-check-home'),
              leading: const Icon(Icons.accessibility_new),
              title: const Text('AI Form Check'),
              subtitle: const Text(
                'Squat · Push-up · Plank — phân tích realtime',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SquatFormCheckPage(controller: controller),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'This week'),
          const SizedBox(height: AppSpacing.sm),
          _WeeklyGoalCard(
            done: weekly,
            goal: controller.weeklyGoal,
            onTap: () => _pickWeeklyGoal(context, controller),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: constraints.maxWidth < 500 ? 2 : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: [
                StatCard(
                  icon: Icons.local_fire_department,
                  value: '${WorkoutStats.streak(controller.sessions)}',
                  label: 'day streak',
                ),
                StatCard(
                  icon: Icons.timer_outlined,
                  value: '${weekMinutes}m',
                  label: 'active time',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pickWeeklyGoal(BuildContext context, AppController controller) {
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Weekly goal'),
        children: [
          for (final value in List.generate(7, (index) => index + 1))
            SimpleDialogOption(
              onPressed: () {
                controller.setWeeklyGoal(value);
                Navigator.pop(context);
              },
              child: Text('$value workouts per week'),
            ),
        ],
      ),
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({
    required this.done,
    required this.goal,
    required this.onTap,
  });

  final int done;
  final int goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (done / goal).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                    Text(
                      '$done/$goal',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly goal',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      done >= goal
                          ? 'Goal reached — nice work.'
                          : '$done of $goal workouts done. Tap to change your goal.',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined),
            ],
          ),
        ),
      ),
    );
  }
}
