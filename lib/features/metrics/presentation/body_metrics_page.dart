import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/models/body_weight_entry.dart';
import '../../../domain/training_options.dart';
import '../../../core/widgets/app_card.dart';

class BodyMetricsPage extends StatelessWidget {
  const BodyMetricsPage({super.key});

  static const _kgPerLb = BodyMetrics.kgPerLb;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final entries = controller.weightEntries;
    final unit = controller.useMetric ? 'kg' : 'lb';
    double display(double kg) => controller.useMetric ? kg : kg / _kgPerLb;

    final latest = entries.isEmpty ? null : entries.last;
    final delta = entries.length < 2
        ? null
        : entries.last.weightKg - entries[entries.length - 2].weightKg;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Body metrics'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              style: .delta(
                decoration: .boxDelta(
                  color: context.theme.colors.secondary,
                  border: Border.all(width: 0, color: Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current weight'),
                        Text(
                          latest == null
                              ? '—'
                              : '${display(latest.weightKg).toStringAsFixed(1)} $unit',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (delta != null)
                          Text(
                            '${delta >= 0 ? '+' : ''}${display(delta).toStringAsFixed(1)} $unit vs last entry',
                          ),
                      ],
                    ),
                  ),
                  const Icon(FLucideIcons.weight, size: 56),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _BodyProfileCard(latestKg: latest?.weightKg),
            const SizedBox(height: AppSpacing.lg),
            if (entries.length >= 2) ...[
              Text('Trend', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: _WeightTrend(
                  entries: entries,
                  metric: controller.useMetric,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('Log', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (entries.isEmpty)
              const AppCard(
                child: Center(child: Text('Log your first weigh-in.')),
              )
            else
              FTileGroup(
                children: [
                  for (final entry in entries.reversed)
                    FTile(
                      prefix: FAvatar.raw(
                        child: const Icon(FLucideIcons.weight),
                      ),
                      title: Text(
                        '${display(entry.weightKg).toStringAsFixed(1)} $unit',
                      ),
                      subtitle: Text(_date(entry.date)),
                      suffix: FButton.icon(
                        variant: .ghost,
                        size: .sm,
                        onPress: () => _confirmRemove(
                          context,
                          controller,
                          entry,
                          '${display(entry.weightKg).toStringAsFixed(1)} $unit',
                        ),
                        child: const Icon(FLucideIcons.trash2),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FButton(
                key: const Key('log-weight'),
                onPress: () => _logWeight(context, controller),
                prefix: const Icon(FLucideIcons.plus),
                child: const Text('Log weight'),
              ),
            ),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
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
        ?.copyWith(color: context.theme.colors.mutedForeground);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Body profile',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FButton(
                variant: .ghost,
                size: .sm,
                onPress: () => _edit(context),
                child: Text(hasProfile ? 'Edit' : 'Set up'),
              ),
            ],
          ),
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
              ' • $age years • ${controller.isMale ? 'Male' : 'Female'}'
              ' • ${activityLabel(controller.activityLevel)}',
              style: mutedStyle,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (weight == null)
              Text(
                adult
                    ? 'Log your weight to see BMI/BMR/TDEE.'
                    : 'Log your weight to see BMI.',
                key: const Key('metrics-weight-hint'),
              )
            else ...[
              Row(
                children: [
                  _value(
                    context,
                    'BMI',
                    bmi!.toStringAsFixed(1),
                    BodyMetrics.bmiCategory(bmi, age: age),
                  ),
                  if (adult) ...[
                    _value(context, 'BMR', '${bmr!.round()} kcal'),
                    _value(context, 'TDEE', '${tdee!.round()} kcal'),
                  ],
                ],
              ),
              if (!adult) ...[
                const SizedBox(height: AppSpacing.xs),
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
    );
  }

  Widget _value(
    BuildContext context,
    String label,
    String value, [
    String? caption,
  ]) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (caption != null)
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

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
    final unit = widget.metric ? 'kg' : 'lb';
    String display(double kg) =>
        (widget.metric ? kg : kg / BodyMetrics.kgPerLb).toStringAsFixed(1);
    final colors = context.theme.colors;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);

    double? min;
    double? max;
    for (final entry in entries) {
      if (min == null || entry.weightKg < min) min = entry.weightKg;
      if (max == null || entry.weightKg > max) max = entry.weightKg;
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
        if (entries.length < 2)
          const SizedBox(
            height: 160,
            child: Center(child: Text('Not enough entries in this range.')),
          )
        else ...[
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${display(max!)} $unit', style: labelStyle),
                    Text('${display(min!)} $unit', style: labelStyle),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: CustomPaint(
                    painter: _WeightPainter(
                      entries: entries,
                      color: colors.primary,
                      dotColor: colors.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                BodyMetricsPage._date(entries.first.date),
                style: labelStyle,
              ),
              Text(BodyMetricsPage._date(entries.last.date), style: labelStyle),
            ],
          ),
        ],
      ],
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.entries,
    required this.color,
    required this.dotColor,
  }) : signature = Object.hashAll(
         entries.map((entry) => Object.hash(entry.id, entry.weightKg)),
       );

  final List<BodyWeightEntry> entries;
  final Color color;
  final Color dotColor;

  /// Content hash: the controller mutates its list in place, so identity
  /// comparison would miss edits.
  final int signature;

  static int _dayIndex(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 12.0;
    var min = entries.first.weightKg;
    var max = entries.first.weightKg;
    for (final entry in entries) {
      if (entry.weightKg < min) min = entry.weightKg;
      if (entry.weightKg > max) max = entry.weightKg;
    }
    if (min == max) {
      min -= 1;
      max += 1;
    }
    final firstDay = _dayIndex(entries.first.date);
    final span = _dayIndex(entries.last.date) - firstDay;

    Offset point(int index) => Offset(
      pad +
          (span == 0
              ? 0
              : (_dayIndex(entries[index].date) - firstDay) /
                    span *
                    (size.width - pad * 2)),
      size.height -
          pad -
          (entries[index].weightKg - min) /
              (max - min) *
              (size.height - pad * 2),
    );

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < entries.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final dots = Paint()..color = dotColor;
    for (var i = 0; i < entries.length; i++) {
      canvas.drawCircle(point(i), 3, dots);
    }
  }

  @override
  bool shouldRepaint(_WeightPainter oldDelegate) =>
      oldDelegate.signature != signature ||
      oldDelegate.color != color ||
      oldDelegate.dotColor != dotColor;
}
