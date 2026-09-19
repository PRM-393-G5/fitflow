import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
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
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back',
            style: textTheme.titleMedium?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          Text('Ready to move?', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary,
                  Color.lerp(colors.primary, Colors.black, 0.2)!,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Today’s workout',
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          FTappable(
                            onPress: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SchedulePage(),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.xs),
                              child: Icon(
                                FLucideIcons.calendarDays,
                                color: Colors.white,
                                semanticLabel: 'Edit weekly schedule',
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        today?.name ?? 'No plan available',
                        style: textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (today != null) ...[
                        Text(
                          '${today.duration.inMinutes} min • ${today.level}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FButton(
                          variant: .secondary,
                          onPress: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => WorkoutDetailPage(workout: today),
                            ),
                          ),
                          prefix: const Icon(FLucideIcons.play),
                          mainAxisSize: MainAxisSize.min,
                          child: const Text('Quick start'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    FLucideIcons.activity,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FTileGroup(
            children: [
              FTile(
                key: const Key('open-squat-form-check-home'),
                prefix: const Icon(FLucideIcons.accessibility),
                title: const Text('AI Form Check'),
                subtitle: const Text(
                  'Squat · Push-up · Plank — phân tích realtime',
                ),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SquatFormCheckPage(controller: controller),
                  ),
                ),
              ),
            ],
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
                  icon: FLucideIcons.flame,
                  value: '${WorkoutStats.streak(controller.sessions)}',
                  label: 'day streak',
                ),
                StatCard(
                  icon: FLucideIcons.timer,
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
    showAppDialog<void>(
      context: context,
      title: 'Weekly goal',
      body: FTileGroup(
        children: [
          for (final value in List.generate(7, (index) => index + 1))
            FTile(
              title: Text('$value workouts per week'),
              onPress: () {
                controller.setWeeklyGoal(value);
                Navigator.pop(context);
              },
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
    final colors = context.theme.colors;
    return FCard(
      clipBehavior: Clip.antiAlias,
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Weekly goal',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '$done/$goal',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FDeterminateProgress(value: progress),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      done >= goal
                          ? 'Goal reached — nice work.'
                          : '$done of $goal workouts done. Tap to change your goal.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(FLucideIcons.pencil, color: colors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
