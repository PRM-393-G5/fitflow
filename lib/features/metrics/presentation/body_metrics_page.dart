import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/body_weight_entry.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Body metrics')),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      const Icon(Icons.monitor_weight_outlined, size: 56),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _BodyProfileCard(latestKg: latest?.weightKg),
              const SizedBox(height: AppSpacing.lg),
              if (entries.length >= 2) ...[
                Text('Trend', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _WeightChart(entries: entries),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text('Log', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (entries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: Text('Log your first weigh-in.')),
                  ),
                )
              else
                ...entries.reversed.map(
                  (entry) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.monitor_weight_outlined),
                      ),
                      title: Text(
                        '${display(entry.weightKg).toStringAsFixed(1)} $unit',
                      ),
                      subtitle: Text(_date(entry.date)),
                      trailing: IconButton(
                        tooltip: 'Delete entry',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.removeWeightEntry(entry),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('log-weight'),
        onPressed: () => _logWeight(context, controller),
        icon: const Icon(Icons.add),
        label: const Text('Log weight'),
      ),
    );
  }

  Future<void> _logWeight(
    BuildContext context,
    AppController controller,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !context.mounted) return;

    final unit = controller.useMetric ? 'kg' : 'lb';
    final input = TextEditingController();
    final weight = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log weight'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Weight ($unit)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(input.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
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

  static const _activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];
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
    if (hasProfile && latestKg != null) {
      final meters = height / 100;
      bmi = latestKg! / (meters * meters);
      bmr =
          10 * latestKg! +
          6.25 * height -
          5 * age +
          (controller.isMale ? 5 : -161);
    }
    final tdee = bmr == null
        ? null
        : bmr * _activityFactors[controller.activityLevel.clamp(0, 4)];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
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
                TextButton(
                  onPressed: () => _edit(context),
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
    return showDialog<void>(
      context: context,
      builder: (_) => _ProfileDialog(controller: controller),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.controller});

  final AppController controller;

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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Body profile'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _height,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Height (cm)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _age,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Age'),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Male')),
            ButtonSegment(value: false, label: Text('Female')),
          ],
          selected: {_isMale},
          onSelectionChanged: (value) => setState(() => _isMale = value.first),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          initialValue: _activity,
          decoration: const InputDecoration(labelText: 'Activity level'),
          items: [
            for (var i = 0; i < _BodyProfileCard._activityLabels.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(_BodyProfileCard._activityLabels[i]),
              ),
          ],
          onChanged: (value) => setState(() => _activity = value ?? 1),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
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
        color: Theme.of(context).colorScheme.primary,
        dotColor: Theme.of(context).colorScheme.onSurface,
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
