import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/form_trend.dart';
import '../../squat_form/domain/squat_analyzer.dart';
import '../../squat_form/presentation/form_review_view.dart';

/// Form quality per camera-checked exercise: the latest set's good-form
/// share, its direction, recent sets as bars and the most common fault.
class FormQualityCard extends StatelessWidget {
  const FormQualityCard({required this.trends, super.key});

  final List<FormTrend> trends;

  @override
  Widget build(BuildContext context) => FTileGroup(
    children: [
      for (final trend in trends)
        FTile(
          key: Key('form-trend-${trend.exercise}'),
          prefix: const Icon(FLucideIcons.scanEye),
          title: Text(
            FormExercise.values.asNameMap()[trend.exercise]?.label ??
                trend.exercise,
          ),
          subtitle: Text(
            trend.topFault == null
                ? 'No faults in recent sets'
                : 'Most common: ${formFaultLabel(trend.topFault!)}',
          ),
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Bars(qualities: trend.qualities),
              const SizedBox(width: AppSpacing.sm),
              _Latest(trend: trend),
            ],
          ),
        ),
    ],
  );
}

Color _qualityColor(double quality) => quality >= .8
    ? const Color(0xFF22A06B)
    : quality >= .5
    ? const Color(0xFFE2A03F)
    : const Color(0xFFD9534F);

class _Latest extends StatelessWidget {
  const _Latest({required this.trend});

  final FormTrend trend;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (trend.direction) {
      FormTrendDirection.improving => (FLucideIcons.trendingUp, 'Improving'),
      FormTrendDirection.slipping => (FLucideIcons.trendingDown, 'Slipping'),
      FormTrendDirection.steady => (FLucideIcons.minus, 'Steady'),
      null => (null, null),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${(trend.latest * 100).round()}%',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: _qualityColor(trend.latest),
          ),
        ),
        if (icon != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 2),
              Text(label!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

/// Recent sets' good-form share, oldest first.
class _Bars extends StatelessWidget {
  const _Bars({required this.qualities});

  final List<double> qualities;

  static const _height = 28.0;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Recent sets: ${[for (final q in qualities) '${(q * 100).round()}%'].join(', ')}',
    child: SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final quality in qualities)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Container(
                width: 5,
                // A clean-less set still shows a sliver.
                height: 3 + (_height - 3) * quality,
                decoration: BoxDecoration(
                  color: _qualityColor(quality),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
