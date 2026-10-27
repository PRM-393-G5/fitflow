import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/models/body_weight_entry.dart';
import '../../../domain/training_options.dart';

class BodyMetricsPage extends StatelessWidget {
  const BodyMetricsPage({super.key});

  static const _kgPerLb = BodyMetrics.kgPerLb;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final entries = controller.weightEntries;
    final metric = controller.useMetric;
    final latest = entries.isEmpty ? null : entries.last;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Body metrics'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CurrentWeight(
              latest: latest,
              metric: metric,
              onLog: () => _logWeight(context, controller),
            ),
            if (entries.length >= 2) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Trend'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: _WeightTrend(entries: entries, metric: metric),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _BodyProfileCard(latestKg: latest?.weightKg),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _WeightLog(
                entries: entries,
                metric: metric,
                onRemove: (entry, label) =>
                    _confirmRemove(context, controller, entry, label),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "72.5 kg" (or lb), one decimal.
  static String _weight(double kg, bool metric) =>
      '${(metric ? kg : kg / _kgPerLb).toStringAsFixed(1)} '
      '${metric ? 'kg' : 'lb'}';

  /// A change with a real minus sign: "−0.3", "+1.2", "0.0".
  static String _signed(double kg, bool metric) {
    final value = (metric ? kg : kg / _kgPerLb).toStringAsFixed(1);
    if (value == '0.0' || value == '-0.0') return '0.0';
    return kg < 0 ? '−${value.substring(1)}' : '+$value';
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AppController controller,
    BodyWeightEntry entry,
    String label,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Delete this entry?',
      body: Text('$label on ${_date(entry.date)} will be removed.'),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FButton(
          key: const Key('confirm-delete-weight'),
          variant: .destructive,
          onPress: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed == true) await controller.removeWeightEntry(entry);
  }

  Future<void> _logWeight(
    BuildContext context,
    AppController controller,
  ) async {
    final now = clock.now();
    var picked = now;
    final date = await showAppDialog<DateTime>(
      context: context,
      title: 'Pick a date',
      // The calendar has a fixed 7-day width that can exceed a phone
      // dialog; scale it down instead of overflowing.
      body: FittedBox(
        fit: BoxFit.scaleDown,
        child: FCalendar.grid(
          // Weigh-ins can't be logged in the future.
          // Today from the same clock as the end date, not the device's.
          control: FGridCalendarControl(end: now, today: now),
          selectionControl: .managedSingle(
            initial: picked,
            onChange: (value) => picked = value ?? picked,
          ),
        ),
      ),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () => Navigator.pop(context, picked),
          child: const Text('Select'),
        ),
      ],
    );
    if (date == null || !context.mounted) return;
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);

    final weightKg = await showFDialog<double>(
      context: context,
      builder: (context, style, animation) =>
          _LogWeightDialog(metric: controller.useMetric, animation: animation),
    );
    if (weightKg == null) return;
    await controller.addWeightEntry(weightKg, day.isAfter(today) ? today : day);
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// The latest weigh-in, how old it is, and the one action the page is
/// for: logging the next one.
class _CurrentWeight extends StatelessWidget {
  const _CurrentWeight({
    required this.latest,
    required this.metric,
    required this.onLog,
  });

  final BodyWeightEntry? latest;
  final bool metric;
  final VoidCallback onLog;

  static String _age(DateTime date) {
    final now = clock.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    return switch (days) {
      <= 0 => 'Logged today',
      1 => 'Logged yesterday',
      < 60 => 'Logged $days days ago',
      _ => 'Logged on ${BodyMetricsPage._date(date)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final entry = latest;
    return AppCard(
      key: const Key('metrics-current'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Current weight',
            style: textTheme.labelMedium?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          Text(
            entry == null
                ? '—'
                : BodyMetricsPage._weight(entry.weightKg, metric),
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            entry == null ? 'No weigh-ins yet' : _age(entry.date),
            style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: AppSpacing.md),
          FButton(
            key: const Key('log-weight'),
            onPress: onLog,
            prefix: const Icon(FLucideIcons.plus),
            child: const Text('Log weight'),
          ),
        ],
      ),
    );
  }
}

/// Weight entry with inline validation; pops the weight in kg. Owns its
/// controller so disposal can't race the exit animation.
class _LogWeightDialog extends StatefulWidget {
  const _LogWeightDialog({required this.metric, this.animation});

  final bool metric;
  final Animation<double>? animation;

  @override
  State<_LogWeightDialog> createState() => _LogWeightDialogState();
}

class _LogWeightDialogState extends State<_LogWeightDialog> {
  final _input = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final error = BodyMetrics.weightError(_input.text, metric: widget.metric);
    if (error != null) {
      setState(() => _submitted = true);
      return;
    }
    final value = BodyMetrics.parseDecimal(_input.text)!;
    Navigator.pop(context, widget.metric ? value : value * BodyMetrics.kgPerLb);
  }

  @override
  Widget build(BuildContext context) {
    final error = _submitted
        ? BodyMetrics.weightError(_input.text, metric: widget.metric)
        : null;
    return FDialog(
      style: .context(),
      animation: widget.animation,
      builder: (context, style) => AppDialogContent(
        title: 'Log weight',
        style: style,
        body: FTextField(
          key: const Key('weight-input'),
          control: .managed(
            controller: _input,
            onChange: (_) {
              if (_submitted) setState(() {});
            },
          ),
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          label: Text('Weight (${widget.metric ? 'kg' : 'lb'})'),
          error: error == null ? null : Text(error),
          onSubmit: (_) => _save(),
        ),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(onPress: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _BodyProfileCard extends StatelessWidget {
  const _BodyProfileCard({required this.latestKg});

  final double? latestKg;

  /// BMI band colour: only the category carries meaning, so only it is
  /// coloured.
  static Color? _bmiColor(String category, FColors colors) =>
      switch (category) {
        'Normal' => const Color(0xFF16A34A),
        'Underweight' || 'Overweight' => const Color(0xFFD97706),
        'Obese' => colors.destructive,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final colors = context.theme.colors;
    final height = controller.heightCm;
    final age = controller.age;
    final hasProfile = height != null && age != null;
    final weight = latestKg;
    // BMR and TDEE are adult formulas, as on Nutrition.
    final adult = BodyMetrics.adultFormulasApply(age);

    double? bmi;
    double? bmr;
    double? tdee;
    if (hasProfile && weight != null) {
      bmi = BodyMetrics.bmi(weightKg: weight, heightCm: height);
    }
    if (hasProfile && weight != null && adult) {
      bmr = BodyMetrics.bmr(
        weightKg: weight,
        heightCm: height,
        age: age,
        isMale: controller.isMale,
      );
      tdee = BodyMetrics.tdee(
        weightKg: weight,
        heightCm: height,
        age: age,
        isMale: controller.isMale,
        activityLevel: controller.activityLevel,
      );
    }
    final mutedStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.mutedForeground);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Body profile',
          action: FButton(
            variant: .ghost,
            size: .sm,
            mainAxisSize: .min,
            onPress: () => _edit(context),
            child: Text(hasProfile ? 'Edit' : 'Set up'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!hasProfile)
                Text(
                  adult
                      ? 'Add height, age, and sex to compute BMI and TDEE.'
                      : 'Add your height to compute BMI.',
                )
              else ...[
                Text(
                  '${height.round()} cm'
                  '${controller.useMetric ? '' : ' (${BodyMetrics.feetInches(height)})'}'
                  ' · $age years · ${controller.isMale ? 'Male' : 'Female'}'
                  ' · ${activityLabel(controller.activityLevel)}',
                  style: mutedStyle,
                ),
                const SizedBox(height: AppSpacing.md),
                if (weight == null)
                  Text(
                    adult
                        ? 'Log your weight to see BMI/BMR/TDEE.'
                        : 'Log your weight to see BMI.',
                    key: const Key('metrics-weight-hint'),
                  )
                else ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.sm,
                      children: [
                        () {
                          final category = BodyMetrics.bmiCategory(
                            bmi!,
                            age: age,
                          );
                          return _value(
                            context,
                            'BMI',
                            bmi.toStringAsFixed(1),
                            category,
                            _bmiColor(category, colors),
                          );
                        }(),
                        if (adult) ...[
                          _value(
                            context,
                            'BMR',
                            thousands(bmr!),
                            'kcal at rest',
                          ),
                          _value(
                            context,
                            'TDEE',
                            thousands(tdee!),
                            'kcal per day',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!adult) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'BMR and TDEE use adult formulas, so they are not shown '
                      'under ${BodyMetrics.adultAge}.',
                      key: const Key('metrics-minor-note'),
                      style: mutedStyle,
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// One equal-width figure: label, value, and what the value means.
  Widget _value(
    BuildContext context,
    String label,
    String value,
    String caption, [
    Color? captionColor,
  ]) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              caption,
              style: textTheme.bodySmall?.copyWith(
                color: captionColor ?? colors.mutedForeground,
                fontWeight: captionColor == null ? null : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) {
    final controller = AppScope.of(context);
    return showFDialog<void>(
      context: context,
      builder: (context, style, animation) =>
          _ProfileDialog(controller: controller, animation: animation),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.controller, this.animation});

  final AppController controller;
  final Animation<double>? animation;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _height = TextEditingController(
    text: widget.controller.heightCm?.toStringAsFixed(0) ?? '',
  );
  late final _age = TextEditingController(
    text: widget.controller.age?.toString() ?? '',
  );
  late bool _isMale = widget.controller.isMale;
  late int _activity = widget.controller.activityLevel;

  /// Errors show once the user tries to save, then update live.
  bool _submitted = false;

  @override
  void dispose() {
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  void _save() {
    if (BodyMetrics.heightError(_height.text) != null ||
        BodyMetrics.ageError(_age.text) != null) {
      setState(() => _submitted = true);
      return;
    }
    widget.controller.saveBodyProfile(
      heightCm: BodyMetrics.parseDecimal(_height.text)!,
      age: int.parse(_age.text.trim()),
      isMale: _isMale,
      activityLevel: _activity,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final heightError = _submitted
        ? BodyMetrics.heightError(_height.text)
        : null;
    final ageError = _submitted ? BodyMetrics.ageError(_age.text) : null;
    final heightCm = BodyMetrics.parseDecimal(_height.text);
    // Imperial users still enter cm; show the ft/in equivalent alongside.
    final heightHint =
        !widget.controller.useMetric &&
            heightCm != null &&
            BodyMetrics.heightError(_height.text) == null
        ? '≈ ${BodyMetrics.feetInches(heightCm)}'
        : null;
    return FDialog(
      style: .context(),
      animation: widget.animation,
      builder: (context, style) => AppDialogContent(
        title: 'Body profile',
        style: style,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextField(
              control: .managed(
                controller: _height,
                onChange: (_) => setState(() {}),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: const Text('Height (cm)'),
              description: heightHint == null ? null : Text(heightHint),
              error: heightError == null ? null : Text(heightError),
            ),
            const SizedBox(height: AppSpacing.sm),
            FTextField(
              control: .managed(
                controller: _age,
                onChange: (_) {
                  if (_submitted) setState(() {});
                },
              ),
              keyboardType: TextInputType.number,
              label: const Text('Age'),
              error: ageError == null ? null : Text(ageError),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (value, label) in [
                  (true, 'Male'),
                  (false, 'Female'),
                ])
                  FButton(
                    variant: _isMale == value ? .primary : .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => setState(() => _isMale = value),
                    child: Text(label),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FSelect<int>(
              items: {
                for (var i = 0; i < activityLevels.length; i++)
                  activityLevels[i]: i,
              },
              control: .managed(
                initial: _activity,
                onChange: (value) => setState(() => _activity = value ?? 1),
              ),
              label: const Text('Activity level'),
            ),
          ],
        ),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(onPress: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

enum _Range {
  days30('30d', 30),
  days90('90d', 90),
  all('All', null);

  const _Range(this.label, this.days);

  final String label;
  final int? days;
}

/// Weight trend with a range filter; points are spaced by date.
class _WeightTrend extends StatefulWidget {
  const _WeightTrend({required this.entries, required this.metric});

  /// Sorted oldest first.
  final List<BodyWeightEntry> entries;
  final bool metric;

  @override
  State<_WeightTrend> createState() => _WeightTrendState();
}

class _WeightTrendState extends State<_WeightTrend> {
  _Range _range = _Range.days90;

  @override
  Widget build(BuildContext context) {
    final days = _range.days;
    final now = clock.now();
    final from = days == null
        ? null
        : DateTime(now.year, now.month, now.day - (days - 1));
    final entries = [
      for (final entry in widget.entries)
        if (from == null || !entry.date.isBefore(from)) entry,
    ];
    final metric = widget.metric;
    final unit = metric ? 'kg' : 'lb';
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(
      color: colors.mutedForeground,
    );

    final Widget body;
    if (entries.length < 2) {
      body = const SizedBox(
        height: 160,
        child: Center(child: Text('Not enough entries in this range.')),
      );
    } else {
      final change = entries.last.weightKg - entries.first.weightKg;
      final spanDays = entries.last.date.difference(entries.first.date).inDays;
      final perWeek = spanDays >= 7 ? change / spanDays * 7 : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${BodyMetricsPage._signed(change, metric)} $unit',
            key: const Key('metrics-trend-change'),
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            'since ${BodyMetricsPage._date(entries.first.date)}'
            '${perWeek == null ? '' : ' · ${BodyMetricsPage._signed(perWeek, metric)} $unit per week'}',
            style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _WeightPainter(
                entries: entries,
                metric: metric,
                color: colors.primary,
                gridColor: colors.border,
                labelStyle: labelStyle ?? const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: _WeightPainter.axisWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  BodyMetricsPage._date(entries.first.date),
                  style: labelStyle,
                ),
                Text(
                  BodyMetricsPage._date(entries.last.date),
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: AppSpacing.xs,
          children: [
            for (final range in _Range.values)
              FButton(
                variant: _range == range ? .primary : .outline,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => setState(() => _range = range),
                child: Text(range.label),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        body,
      ],
    );
  }
}

/// The weight line over three faint gridlines (top, middle, bottom of the
/// range) labelled on the left. Only the latest point is marked: with
/// daily weigh-ins, a dot per entry is noise.
class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.entries,
    required this.metric,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
  }) : signature = Object.hashAll(
         entries.map((entry) => Object.hash(entry.id, entry.weightKg)),
       );

  /// Room on the left for the weight labels; the date row below lines up
  /// with the plot by the same amount.
  static const axisWidth = 44.0;

  final List<BodyWeightEntry> entries;
  final bool metric;
  final Color color;
  final Color gridColor;
  final TextStyle labelStyle;

  /// Content hash: the controller mutates its list in place, so identity
  /// comparison would miss edits.
  final int signature;

  static int _dayIndex(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    var min = entries.first.weightKg;
    var max = entries.first.weightKg;
    for (final entry in entries) {
      min = math.min(min, entry.weightKg);
      max = math.max(max, entry.weightKg);
    }
    if (max - min < 1) {
      final mid = (max + min) / 2;
      min = mid - .5;
      max = mid + .5;
    }
    final left = axisWidth;
    final width = size.width - left - pad;
    final top = pad;
    final height = size.height - pad * 2;
    double y(double kg) => top + (max - kg) / (max - min) * height;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final kg in [max, (max + min) / 2, min]) {
      final dy = y(kg);
      canvas.drawLine(Offset(left, dy), Offset(size.width, dy), grid);
      final label = TextPainter(
        text: TextSpan(
          text: (metric ? kg : kg / BodyMetrics.kgPerLb).toStringAsFixed(1),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: axisWidth - 6);
      label.paint(
        canvas,
        Offset(axisWidth - 6 - label.width, dy - label.height / 2),
      );
    }

    final firstDay = _dayIndex(entries.first.date);
    final span = _dayIndex(entries.last.date) - firstDay;
    Offset point(BodyWeightEntry entry) => Offset(
      left +
          (span == 0 ? 0 : (_dayIndex(entry.date) - firstDay) / span * width),
      y(entry.weightKg),
    );

    final path = Path()
      ..moveTo(point(entries.first).dx, point(entries.first).dy);
    for (final entry in entries.skip(1)) {
      final p = point(entry);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(point(entries.last), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WeightPainter oldDelegate) =>
      oldDelegate.signature != signature ||
      oldDelegate.metric != metric ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}

/// Recent weigh-ins, newest first, each with its change from the one
/// before. The full list is one tap away; tapping an entry offers to
/// delete it, so no delete button sits in reach of every scroll.
class _WeightLog extends StatefulWidget {
  const _WeightLog({
    required this.entries,
    required this.metric,
    required this.onRemove,
  });

  /// Sorted oldest first.
  final List<BodyWeightEntry> entries;
  final bool metric;
  final void Function(BodyWeightEntry entry, String label) onRemove;

  @override
  State<_WeightLog> createState() => _WeightLogState();
}

class _WeightLogState extends State<_WeightLog> {
  static const _preview = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final metric = widget.metric;
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final newestFirst = entries.reversed.toList();
    final shown = _all ? newestFirst : newestFirst.take(_preview).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Log',
          action: entries.length > _preview
              ? FButton(
                  key: const Key('metrics-log-all'),
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: () => setState(() => _all = !_all),
                  child: Text(
                    _all ? 'Show less' : 'Show all (${entries.length})',
                  ),
                )
              : null,
        ),
        Text(
          'Tap an entry to delete it.',
          style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.sm),
        FTileGroup(
          children: [
            for (final entry in shown)
              () {
                final index = entries.indexOf(entry);
                final label = BodyMetricsPage._weight(entry.weightKg, metric);
                return FTile(
                  key: Key('weight-entry-${entry.id}'),
                  title: Text(label),
                  subtitle: Text(BodyMetricsPage._date(entry.date)),
                  suffix: index > 0
                      ? Text(
                          BodyMetricsPage._signed(
                            entry.weightKg - entries[index - 1].weightKg,
                            metric,
                          ),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.mutedForeground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        )
                      : null,
                  onPress: () => widget.onRemove(entry, label),
                );
              }(),
          ],
        ),
      ],
    );
  }
}
