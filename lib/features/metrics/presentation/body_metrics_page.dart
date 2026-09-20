import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/models/body_weight_entry.dart';
import '../../../core/widgets/app_card.dart';

class BodyMetricsPage extends StatelessWidget {
  const BodyMetricsPage({super.key});

  static const _kgPerLb = 0.453592;

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
              AppCard(child: _WeightChart(entries: entries)),
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
                        onPress: () => controller.removeWeightEntry(entry),
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

  Future<void> _logWeight(
    BuildContext context,
    AppController controller,
  ) async {
    var picked = DateTime.now();
    final date = await showAppDialog<DateTime>(
      context: context,
      title: 'Pick a date',
      body: FCalendar.grid(
        selectionControl: .managedSingle(
          initial: picked,
          onChange: (value) => picked = value ?? picked,
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

    final unit = controller.useMetric ? 'kg' : 'lb';
    final input = TextEditingController();
    final weight = await showAppDialog<double>(
      context: context,
      title: 'Log weight',
      body: FTextField(
        control: .managed(controller: input),
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        label: Text('Weight ($unit)'),
      ),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () =>
              Navigator.pop(context, double.tryParse(input.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
    input.dispose();
    if (weight == null || weight <= 0) return;
    await controller.addWeightEntry(
      controller.useMetric ? weight : weight * _kgPerLb,
      date,
    );
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _BodyProfileCard extends StatelessWidget {
  const _BodyProfileCard({required this.latestKg});

  final double? latestKg;
  static const _activityLabels = [
    'Sedentary',
    'Light',
    'Moderate',
    'Active',
    'Athlete',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final height = controller.heightCm;
    final age = controller.age;
    final hasProfile = height != null && age != null;

    double? bmi;
    double? bmr;
    double? tdee;
    if (hasProfile && latestKg != null) {
      bmi = BodyMetrics.bmi(weightKg: latestKg!, heightCm: height);
      bmr = BodyMetrics.bmr(
        weightKg: latestKg!,
        heightCm: height,
        age: age,
        isMale: controller.isMale,
      );
      tdee = BodyMetrics.tdee(
        weightKg: latestKg!,
        heightCm: height,
        age: age,
        isMale: controller.isMale,
        activityLevel: controller.activityLevel,
      );
    }

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
            const Text('Add height, age, and sex to compute BMI and TDEE.')
          else
            Row(
              children: [
                _value(context, 'BMI', bmi?.toStringAsFixed(1) ?? '—'),
                _value(
                  context,
                  'BMR',
                  bmr == null ? '—' : '${bmr.round()} kcal',
                ),
                _value(
                  context,
                  'TDEE',
                  tdee == null ? '—' : '${tdee.round()} kcal',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _value(BuildContext context, String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
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

  @override
  void dispose() {
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FDialog(
    style: .context(),
    animation: widget.animation,
    builder: (context, style) => AppDialogContent(
      title: 'Body profile',
      style: style,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FTextField(
            control: .managed(controller: _height),
            keyboardType: TextInputType.number,
            label: const Text('Height (cm)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FTextField(
            control: .managed(controller: _age),
            keyboardType: TextInputType.number,
            label: const Text('Age'),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (value, label) in [(true, 'Male'), (false, 'Female')])
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
              for (var i = 0; i < _BodyProfileCard._activityLabels.length; i++)
                _BodyProfileCard._activityLabels[i]: i,
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
        FButton(
          onPress: () {
            final height = double.tryParse(_height.text.trim());
            final age = int.tryParse(_age.text.trim());
            if (height == null || height <= 0 || age == null || age <= 0) {
              return;
            }
            widget.controller.saveBodyProfile(
              heightCm: height,
              age: age,
              isMale: _isMale,
              activityLevel: _activity,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.entries});

  final List<BodyWeightEntry> entries;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 160,
    width: double.infinity,
    child: CustomPaint(
      painter: _WeightPainter(
        entries: entries,
        color: context.theme.colors.primary,
        dotColor: context.theme.colors.foreground,
      ),
    ),
  );
}

class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.entries,
    required this.color,
    required this.dotColor,
  });

  final List<BodyWeightEntry> entries;
  final Color color;
  final Color dotColor;

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

    Offset point(int index) => Offset(
      pad + index * (size.width - pad * 2) / (entries.length - 1),
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
      oldDelegate.entries != entries;
}
