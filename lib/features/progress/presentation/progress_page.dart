import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/models/body_weight_entry.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';
import '../../../domain/workout_stats.dart';
import '../../achievements/presentation/achievements_page.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import '../../workouts/presentation/weight_units.dart';
import 'session_detail_page.dart';
import 'share_summary_dialog.dart';
import '../../../core/widgets/app_card.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final sessions = controller.sessions;
    final metric = controller.useMetric;
    // Stats ignore empty sessions; computed once per build.
    final counted = WorkoutStats.counted(sessions).toList();
    final records = PersonalRecords.all(sessions).values.toList();
    final week = WorkoutStats.thisWeek(counted);

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Progress',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Semantics(
                label: 'Achievements',
                child: FButton.icon(
                  key: const Key('progress-achievements'),
                  variant: .ghost,
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AchievementsPage(),
                    ),
                  ),
                  child: const Icon(FLucideIcons.trophy),
                ),
              ),
              Semantics(
                label: 'Share summary',
                child: FButton.icon(
                  key: const Key('progress-share'),
                  variant: .ghost,
                  onPress: () => showShareSummaryDialog(context),
                  child: const Icon(FLucideIcons.share),
                ),
              ),
            ],
          ),
          const Text('Consistency compounds. Every session counts.'),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'This week'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: _ThisWeek(
              week: week,
              allCounted: counted,
              goal: controller.weeklyGoal,
              metric: metric,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'All time'),
          const SizedBox(height: AppSpacing.sm),
          _StatGrid(
            tiles: [
              _StatTile(
                icon: FLucideIcons.calendarCheck,
                value: thousands(counted.length),
                label: 'sessions',
              ),
              _StatTile(
                icon: FLucideIcons.timer,
                value: _hours(WorkoutStats.totalMinutes(counted)),
                label: 'trained',
              ),
              _StatTile(
                icon: FLucideIcons.weight,
                value: _weight(WorkoutStats.totalVolume(counted), metric),
                label: 'volume lifted',
              ),
              _StatTile(
                icon: FLucideIcons.flame,
                value: '${WorkoutStats.longestStreak(counted)} days',
                label: 'longest streak',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Activity'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(child: _ActivityHeatmap(sessions: counted)),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Body weight'),
          const SizedBox(height: AppSpacing.sm),
          _WeightCard(entries: controller.weightEntries, metric: metric),
          if (counted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: 'Personal records',
              action: records.length > _preview
                  ? FButton(
                      key: const Key('progress-records-all'),
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _RecordsPage(),
                        ),
                      ),
                      child: Text('See all (${records.length})'),
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StatGrid(
              tiles: [
                _StatTile(
                  icon: FLucideIcons.dumbbell,
                  value: _weight(
                    counted.map((item) => item.volumeKg).reduce(math.max),
                    metric,
                  ),
                  label: 'best session',
                ),
                _StatTile(
                  icon: FLucideIcons.clock,
                  value:
                      '${counted.map((item) => item.durationMinutes).reduce(math.max)} min',
                  label: 'longest session',
                ),
              ],
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              FTileGroup(
                children: [
                  for (final record in _newestFirst(records).take(_preview))
                    _recordTile(context, record, metric),
                ],
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'History',
            action: sessions.length > _preview
                ? FButton(
                    key: const Key('progress-history-all'),
                    variant: .ghost,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _HistoryPage(),
                      ),
                    ),
                    child: Text('See all (${sessions.length})'),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (sessions.isEmpty)
            const AppCard(
              child: Center(
                child: Text('Complete a workout to begin tracking.'),
              ),
            )
          else
            _HistoryList(sessions: sessions.take(_preview).toList()),
        ],
      ),
    );
  }

  /// Rows shown before "See all".
  static const _preview = 5;

  /// By exercise name, then record kind.
  static int _byExercise(PersonalRecord a, PersonalRecord b) {
    final byName = a.exerciseName.compareTo(b.exerciseName);
    return byName != 0 ? byName : a.kind.index.compareTo(b.kind.index);
  }

  /// Newest first; records set the same day keep exercise order, so the
  /// preview is stable.
  static List<PersonalRecord> _newestFirst(List<PersonalRecord> records) =>
      [...records]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : _byExercise(a, b);
      });

  static String _weight(double kg, bool metric) =>
      '${thousands(WeightUnits.toDisplay(kg, metric))} '
      '${WeightUnits.label(metric)}';

  /// 1411 → "23 h 31 m"; under an hour → "45 min".
  static String _hours(int minutes) => minutes < 60
      ? '$minutes min'
      : '${thousands(minutes ~/ 60)} h ${minutes % 60} m';

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static FTile _recordTile(
    BuildContext context,
    PersonalRecord record,
    bool metric,
  ) {
    String weight(double kg) =>
        '${WeightUnits.format(kg, metric)} ${WeightUnits.label(metric)}';
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

/// This week at a glance: sessions against the weekly goal, minutes and
/// volume, the current streak, then minutes per day.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek({
    required this.week,
    required this.allCounted,
    required this.goal,
    required this.metric,
  });

  final List<WorkoutSession> week;
  final List<WorkoutSession> allCounted;
  final int goal;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final done = week.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$done',
              key: const Key('progress-week-done'),
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(' / $goal sessions', style: textTheme.titleMedium),
            const Spacer(),
            if (goal > 0 && done >= goal)
              Text(
                'Goal reached',
                style: textTheme.labelMedium?.copyWith(color: colors.primary),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: goal <= 0 ? 0 : (done / goal).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: colors.muted,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${WorkoutStats.totalMinutes(week)} min · '
          '${ProgressPage._weight(WorkoutStats.totalVolume(week), metric)} · '
          '${WorkoutStats.streak(allCounted)}-day streak',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.md),
        _WeekChart(sessions: week),
      ],
    );
  }
}

/// Stat tiles two per row, every row the same height.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_StatTile> tiles;

  @override
  Widget build(BuildContext context) => Column(
    spacing: AppSpacing.sm,
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: [
              Expanded(child: tiles[i]),
              Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Compact stat: icon on the left, value over label.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(icon, size: 18, color: colors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: .scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Latest weight, its change over the last 30 days and a trend line;
/// opens Body metrics.
class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.entries, required this.metric});

  /// Oldest first.
  final List<BodyWeightEntry> entries;
  final bool metric;

  String _kg(double kg) =>
      '${WeightUnits.format(kg, metric)} ${WeightUnits.label(metric)}';

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    void open() => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const BodyMetricsPage()));
    if (entries.isEmpty) {
      return FTileGroup(
        children: [
          FTile(
            key: const Key('progress-weight'),
            prefix: const Icon(FLucideIcons.weight),
            title: const Text('Log your weight'),
            subtitle: const Text('Track your trend over time'),
            suffix: const Icon(FLucideIcons.chevronRight),
            onPress: open,
          ),
        ],
      );
    }
    final latest = entries.last;
    // The trend covers the last 30 days counted from today, so an old
    // log is never presented as recent.
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - 30);
    final recent = [
      for (final entry in entries)
        if (!entry.date.isBefore(from)) entry,
    ];
    final String detail;
    if (recent.length < 2) {
      detail = 'logged ${ProgressPage._date(latest.date)}';
    } else {
      // Sign from the value as displayed, so 0.04 kg never reads "−0 kg".
      final shown = double.parse(
        WeightUnits.formatNumber(
          WeightUnits.toDisplay(
            latest.weightKg - recent.first.weightKg,
            metric,
          ),
        ),
      );
      final sign = shown > 0 ? '+' : (shown < 0 ? '−' : '±');
      detail =
          '$sign${WeightUnits.formatNumber(shown.abs())} '
          '${WeightUnits.label(metric)} since '
          '${ProgressPage._date(recent.first.date).substring(0, 5)}';
    }
    return FTappable(
      key: const Key('progress-weight'),
      semanticsLabel:
          'Body weight ${_kg(latest.weightKg)}, $detail. '
          'Open body metrics',
      onPress: open,
      child: AppCard(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kg(latest.weightKg),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(detail, style: muted),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SizedBox(
                height: 44,
                child: recent.length < 2
                    ? null
                    : CustomPaint(
                        painter: _Sparkline([
                          for (final entry in recent) entry.weightKg,
                        ], colors.primary),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(FLucideIcons.chevronRight, color: colors.mutedForeground),
          ],
        ),
      ),
    );
  }
}

/// A plain trend line through [values], scaled to the box.
class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low == 0 ? 1 : high - low;
    final path = Path();
    for (final (index, value) in values.indexed) {
      final point = Offset(
        size.width * index / (values.length - 1),
        size.height * (1 - (value - low) / span),
      );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Sparkline oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}

/// Every personal record, by exercise.
class _RecordsPage extends StatelessWidget {
  const _RecordsPage();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final records = PersonalRecords.all(controller.sessions).values.toList()
      ..sort(ProgressPage._byExercise);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Personal records'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: FTileGroup(
          children: [
            for (final record in records)
              ProgressPage._recordTile(context, record, controller.useMetric),
          ],
        ),
      ),
    );
  }
}

/// The full session history, paged.
class _HistoryPage extends StatelessWidget {
  const _HistoryPage();

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: const Text('History'),
      prefixes: [
        FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
      ],
    ),
    child: ResponsiveContent(
      child: _HistoryList(sessions: AppScope.of(context).sessions),
    ),
  );
}
