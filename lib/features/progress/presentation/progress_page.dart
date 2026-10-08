import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
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
import '../../../core/widgets/app_card.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final sessions = controller.sessions;
    // Stats ignore empty sessions; computed once per build.
    final counted = WorkoutStats.counted(sessions).toList();
    final records = PersonalRecords.all(sessions).values.toList()
      ..sort((a, b) {
        final byName = a.exerciseName.compareTo(b.exerciseName);
        return byName != 0 ? byName : a.kind.index.compareTo(b.kind.index);
      });
    final volume = WorkoutStats.totalVolume(counted);
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
          const SectionHeader(title: 'All time'),
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
                  icon: FLucideIcons.calendarCheck,
                  value: '${counted.length}',
                  label: 'sessions',
                ),
                StatCard(
                  icon: FLucideIcons.timer,
                  value: '${WorkoutStats.totalMinutes(counted)}',
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
          AppCard(child: _ActivityHeatmap(sessions: counted)),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'This week'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(child: _WeekChart(sessions: counted)),
          if (counted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Personal records'),
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
                    value: '${WorkoutStats.longestStreak(counted)} days',
                    label: 'longest streak',
                  ),
                  StatCard(
                    icon: FLucideIcons.dumbbell,
                    value: _bestVolume(counted, controller.useMetric),
                    label: 'best session',
                  ),
                  StatCard(
                    icon: FLucideIcons.clock,
                    value:
                        '${counted.map((item) => item.durationMinutes).reduce((a, b) => a > b ? a : b)} min',
                    label: 'longest session',
                  ),
                ],
              ),
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              FTileGroup(
                children: [
                  for (final record in records)
                    _recordTile(context, record, controller.useMetric),
                ],
              ),
            ],
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
            const AppCard(
              child: Center(
                child: Text('Complete a workout to begin tracking.'),
              ),
            )
          else
            _HistoryList(sessions: sessions),
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

  static FTile _recordTile(
    BuildContext context,
    PersonalRecord record,
    bool metric,
  ) {
    final unit = metric ? 'kg' : 'lb';
    String weight(double kg) =>
        '${trimDecimal(metric ? kg : kg * 2.20462)} $unit';
    final oneRepMax = record.estimatedOneRepMaxKg;
    return FTile(
      prefix: const Icon(FLucideIcons.trophy),
      title: Text(record.exerciseName),
      subtitle: Text(
        record.kind == RecordKind.weight && oneRepMax > 0
            ? '${_date(record.date)} • est. 1RM ${weight(oneRepMax)}'
            : _date(record.date),
      ),
      suffix: Text(
        switch (record.kind) {
          RecordKind.weight => weight(record.value),
          RecordKind.hold => '${record.value.round()} s',
          RecordKind.reps => '${record.value.round()} reps',
        },
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Session history, built in pages so long histories stay cheap.
class _HistoryList extends StatefulWidget {
  const _HistoryList({required this.sessions});

  final List<WorkoutSession> sessions;

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  static const _page = 20;
  int _visible = _page;

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final remaining = sessions.length - _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTileGroup(
          children: [
            for (final session in sessions.take(_visible))
              FTile(
                prefix: FAvatar.raw(child: const Icon(FLucideIcons.check)),
                title: Text(session.workoutName),
                subtitle: Text(
                  '${ProgressPage._date(session.completedAt)} • '
                  '${session.durationMinutes} min • '
                  '${WorkoutStats.formCheckLabel(session) ?? '${session.completedSets} sets'}',
                ),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionDetailPage(session: session),
                  ),
                ),
              ),
          ],
        ),
        if (remaining > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          FButton(
            key: const Key('history-show-more'),
            variant: .outline,
            onPress: () => setState(() => _visible += _page),
            child: Text('Show more ($remaining left)'),
          ),
        ],
      ],
    );
  }
}

class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap({required this.sessions});

  final List<WorkoutSession> sessions;

  static const _weeks = 12;
  static const _cell = 14.0;
  static const _gap = 2.0;
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static final _months = [for (final name in monthNames) name.substring(0, 3)];

  static Color _shade(FColors colors, int count) => count == 0
      ? colors.muted
      : colors.primary.withValues(alpha: (0.25 + 0.25 * count).clamp(0.0, 1.0));

  Widget _box(Color color) => Container(
    width: _cell,
    height: _cell,
    margin: const EdgeInsets.all(_gap),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _label(String text, TextStyle? style) => SizedBox(
    height: _cell + _gap * 2,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: style,
      ),
    ),
  );

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
    // Recomputed every build so the grid rolls over at midnight.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - 7 * (_weeks - 1),
    );
    final colors = context.theme.colors;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('', labelStyle),
                for (final day in _weekdays) _label(day, labelStyle),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_weeks, (week) {
                  final monday = DateTime(
                    start.year,
                    start.month,
                    start.day + week * 7,
                  );
                  final previous = DateTime(
                    monday.year,
                    monday.month,
                    monday.day - 7,
                  );
                  // Label a column when its week starts a new month.
                  final monthLabel = week == 0 || previous.month != monday.month
                      ? _months[monday.month - 1]
                      : '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _cell + _gap * 2,
                        child: _label(monthLabel, labelStyle),
                      ),
                      for (var weekday = 0; weekday < 7; weekday++)
                        Builder(
                          builder: (context) {
                            final day = DateTime(
                              monday.year,
                              monday.month,
                              monday.day + weekday,
                            );
                            return _box(
                              day.isAfter(today)
                                  ? Colors.transparent
                                  : _shade(colors, counts[day] ?? 0),
                            );
                          },
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: labelStyle),
            const SizedBox(width: AppSpacing.xs),
            for (var count = 0; count <= 3; count++)
              _box(_shade(colors, count)),
            const SizedBox(width: AppSpacing.xs),
            Text('More', style: labelStyle),
          ],
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.sessions});

  final List<WorkoutSession> sessions;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _maxBar = 72.0;

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
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Minutes trained per day',
          style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(7, (index) {
              final value = minutes[index];
              // Calendar construction, not Duration: DST-safe.
              final isToday =
                  DateTime(monday.year, monday.month, monday.day + index) ==
                  today;
              return Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (value > 0)
                            Text(
                              '$value',
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: isToday ? FontWeight.bold : null,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            width: 20,
                            height: peak == 0 || value == 0
                                ? 4
                                : 4 + (value / peak) * (_maxBar - 4),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? colors.primary
                                  : colors.primary.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _labels[index],
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: isToday ? FontWeight.bold : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
