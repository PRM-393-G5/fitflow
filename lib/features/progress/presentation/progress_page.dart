import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';
import '../../../domain/workout_stats.dart';
import '../../achievements/presentation/achievements_page.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import 'session_detail_page.dart';
import 'share_summary_dialog.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final sessions = controller.sessions;
    final volume = WorkoutStats.totalVolume(sessions);
    final displayVolume = controller.useMetric ? volume : volume * 2.20462;
    final unit = controller.useMetric ? 'kg' : 'lb';

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Text('Consistency compounds. Every session counts.'),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: constraints.maxWidth < 500 ? 2 : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: [
                StatCard(
                  icon: FLucideIcons.calendarCheck,
                  value: '${sessions.length}',
                  label: 'sessions',
                ),
                StatCard(
                  icon: FLucideIcons.timer,
                  value: '${WorkoutStats.totalMinutes(sessions)}',
                  label: 'minutes',
                ),
                StatCard(
                  icon: FLucideIcons.weight,
                  value: '${displayVolume.round()} $unit',
                  label: 'volume',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Activity'),
          const SizedBox(height: AppSpacing.sm),
          FCard(child: _ActivityHeatmap(sessions: sessions)),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'This week'),
          const SizedBox(height: AppSpacing.sm),
          FCard(child: _WeekChart(sessions: sessions)),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Personal records'),
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
                    value: '${WorkoutStats.longestStreak(sessions)}',
                    label: 'longest streak',
                  ),
                  StatCard(
                    icon: FLucideIcons.dumbbell,
                    value: _bestVolume(sessions, controller.useMetric),
                    label: 'best session',
                  ),
                  StatCard(
                    icon: FLucideIcons.clock,
                    value:
                        '${sessions.map((item) => item.durationMinutes).reduce((a, b) => a > b ? a : b)} min',
                    label: 'longest session',
                  ),
                ],
              ),
            ),
            ..._exerciseRecords(context, controller),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Explore'),
          const SizedBox(height: AppSpacing.sm),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(FLucideIcons.trophy),
                title: const Text('Achievements'),
                subtitle: const Text('Badges earned from your training'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AchievementsPage(),
                  ),
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.weight),
                title: const Text('Body metrics'),
                subtitle: const Text('Log and track your weight'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BodyMetricsPage(),
                  ),
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.share),
                title: const Text('Share summary'),
                subtitle: const Text('A card with your latest stats'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => showShareSummaryDialog(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('History', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (sessions.isEmpty)
            const FCard(
              child: Center(
                child: Text('Complete a workout to begin tracking.'),
              ),
            )
          else
            ...sessions.map(
              (session) => FCard(
                child: FTappable(
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionDetailPage(session: session),
                    ),
                  ),
                  child: Row(
                    children: [
                      FAvatar.raw(child: const Icon(FLucideIcons.check)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.workoutName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${_date(session.completedAt)} • ${session.durationMinutes} min • ${session.completedSets} sets',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        FLucideIcons.chevronRight,
                        color: context.theme.colors.mutedForeground,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _bestVolume(List<WorkoutSession> sessions, bool metric) {
    final best = sessions
        .map((item) => item.volumeKg)
        .reduce((a, b) => a > b ? a : b);
    final display = metric ? best : best * 2.20462;
    return '${display.round()} ${metric ? 'kg' : 'lb'}';
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static List<Widget> _exerciseRecords(
    BuildContext context,
    AppController controller,
  ) {
    final records = PersonalRecords.best(controller.sessions).values.toList()
      ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    if (records.isEmpty) return [];
    final unit = controller.useMetric ? 'kg' : 'lb';
    return [
      const SizedBox(height: AppSpacing.sm),
      FTileGroup(
        children: [
          for (final record in records)
            FTile(
              prefix: const Icon(FLucideIcons.trophy),
              title: Text(record.exerciseName),
              subtitle: Text(_date(record.date)),
              suffix: Text(
                record.isTimed
                    ? '${record.value.round()}s'
                    : '${(controller.useMetric ? record.value : record.value * 2.20462).round()} $unit',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    ];
  }
}

class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap({required this.sessions});

  final List<WorkoutSession> sessions;

  static const _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final counts = <DateTime, int>{};
    for (final session in sessions) {
      final day = DateTime(
        session.completedAt.year,
        session.completedAt.month,
        session.completedAt.day,
      );
      counts[day] = (counts[day] ?? 0) + 1;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - 7 * (_weeks - 1),
    );
    final colors = context.theme.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        _weeks,
        (week) => Column(
          children: List.generate(7, (weekday) {
            final day = DateTime(
              start.year,
              start.month,
              start.day + week * 7 + weekday,
            );
            final count = counts[day] ?? 0;
            final color = day.isAfter(today)
                ? Colors.transparent
                : count == 0
                ? colors.muted
                : colors.primary.withValues(
                    alpha: (0.25 + 0.25 * count).clamp(0.0, 1.0),
                  );
            return Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.sessions});

  final List<WorkoutSession> sessions;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final mondayUtc = DateTime.utc(monday.year, monday.month, monday.day);
    final minutes = List<int>.filled(7, 0);
    for (final session in sessions) {
      final day = session.completedAt;
      final index = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).difference(mondayUtc).inDays;
      if (index >= 0 && index < 7) minutes[index] += session.durationMinutes;
    }
    final peak = minutes.reduce((a, b) => a > b ? a : b);
    final colors = context.theme.colors;

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(7, (index) {
          final value = minutes[index];
          final isToday = monday.add(Duration(days: index)) == today;
          return Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 20,
                      height: peak == 0 ? 4 : (value / peak) * 88,
                      decoration: BoxDecoration(
                        color: isToday
                            ? colors.primary
                            : colors.primary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _labels[index],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
