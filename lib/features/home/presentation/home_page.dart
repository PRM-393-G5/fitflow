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
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../workouts/presentation/active_workout_page.dart';
import '../../workouts/presentation/schedule_page.dart';
import '../../workouts/presentation/workout_detail_page.dart';
import '../../../core/widgets/app_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final now = DateTime.now();
    final today = controller.suggestedWorkout();
    final restDay = controller.isRestDay(now.weekday);
    final weekly = WorkoutStats.sessionsThisWeek(controller.sessions);
    // Same Monday-start calendar week as the weekly goal.
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final weekMinutes = WorkoutStats.totalMinutes(
      controller.sessions.where(
        (item) => !item.completedAt.isBefore(weekStart),
      ),
    );
    final dayStart = DateTime(now.year, now.month, now.day);
    WorkoutSession? doneToday;
    for (final session in controller.sessions) {
      // A camera form check is not today's planned workout.
      if (session.workoutId == WorkoutStats.formCheckId) continue;
      if (!session.completedAt.isBefore(dayStart)) {
        doneToday = session;
        break;
      }
    }
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
                      const SizedBox(height: AppSpacing.xs),
                      ..._heroContent(
                        context,
                        today: today,
                        restDay: restDay,
                        doneToday: doneToday,
                      ),
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
                  child: Icon(
                    doneToday != null
                        ? FLucideIcons.circleCheckBig
                        : restDay
                        ? FLucideIcons.moon
                        : FLucideIcons.activity,
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
                  'Squat · Push-up · Plank — real-time analysis',
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
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              children: [
                StatCard(
                  icon: FLucideIcons.flame,
                  value: '${WorkoutStats.streak(controller.sessions)}',
                  label: 'day streak',
                ),
                StatCard(
                  icon: FLucideIcons.timer,
                  value: '${weekMinutes}m',
                  label: 'active this week',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _heroContent(
    BuildContext context, {
    required Workout? today,
    required bool restDay,
    required WorkoutSession? doneToday,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final title = textTheme.titleLarge?.copyWith(color: Colors.white);
    const subtitle = TextStyle(color: Colors.white70);
    Widget details(Workout workout, String label) => FTappable(
      key: const Key('home-view-details'),
      onPress: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutDetailPage(workout: workout),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    if (doneToday != null) {
      return [
        Text('Done today', key: const Key('home-done-today'), style: title),
        Text(
          '${doneToday.workoutName} • ${doneToday.completedSets} sets • '
          '${doneToday.durationMinutes} min',
          style: subtitle,
        ),
        if (today != null) ...[
          const SizedBox(height: AppSpacing.sm),
          details(today, 'Train again'),
        ],
      ];
    }
    if (restDay) {
      return [
        Text('Rest day', key: const Key('home-rest-day'), style: title),
        const Text(
          'Recovery is part of the plan. Feel like moving? Pick any plan in '
          'Workouts.',
          style: subtitle,
        ),
      ];
    }
    if (today == null) return [Text('No plan available', style: title)];
    return [
      Text(today.name, style: title),
      Text('${today.duration.inMinutes} min • ${today.level}', style: subtitle),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FButton(
            key: const Key('home-quick-start'),
            variant: .secondary,
            onPress: today.totalSets == 0
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActiveWorkoutPage(
                        workout: today,
                        controller: AppScope.of(context),
                      ),
                    ),
                  ),
            prefix: const Icon(FLucideIcons.play),
            mainAxisSize: MainAxisSize.min,
            child: const Text('Quick start'),
          ),
          details(today, 'View details'),
        ],
      ),
    ];
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
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: FTappable(
        onPress: onTap,
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
    );
  }
}
