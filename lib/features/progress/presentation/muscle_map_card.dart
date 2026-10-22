import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/muscle_body_map.dart';
import '../../../domain/muscle_volume.dart';

/// This week's sets per muscle, painted on a front and back body outline,
/// with each muscle's count and change from last week listed underneath.
/// Tapping a muscle (on the body or in the list) shows what trained it.
class MuscleMapCard extends StatelessWidget {
  const MuscleMapCard({required this.weeks, super.key});

  final Map<Muscle, MuscleWeek> weeks;

  MuscleWeek _week(Muscle muscle) =>
      weeks[muscle] ?? const MuscleWeek(sets: 0, previous: 0, exercises: []);

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);
    final fills = {
      for (final muscle in Muscle.values)
        muscle: _fill(colors, _week(muscle).sets),
    };
    final summary = [
      for (final muscle in Muscle.values)
        '${muscle.label} ${MuscleVolume.sets(_week(muscle).sets)}',
    ].join(', ');
    void open(Muscle muscle) => _showDetail(context, muscle, _week(muscle));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MuscleBodyMap(
          fills: fills,
          onTap: open,
          semanticsLabel: 'Muscle map this week: $summary',
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Tap a muscle for details · change vs last week',
          textAlign: TextAlign.center,
          style: labelStyle,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final muscle in Muscle.values)
              _MuscleChip(
                key: Key('muscle-${muscle.name}'),
                muscle: muscle,
                week: _week(muscle),
                color: fills[muscle]!,
                onPress: () => open(muscle),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (label, color) in [
              ('None', muscleMapUntrained(colors)),
              ('<${MuscleVolume.targetMin}', _low),
              ('${MuscleVolume.targetMin}–${MuscleVolume.targetMax}', _optimal),
              ('>${MuscleVolume.targetMax}', _high),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MuscleDot(color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Text(label, style: labelStyle),
                ],
              ),
            Text('sets / week', style: labelStyle),
          ],
        ),
      ],
    );
  }
}

Future<void> _showDetail(BuildContext context, Muscle muscle, MuscleWeek week) {
  const format = MuscleVolume.format;
  final advice = switch (week.level) {
    VolumeLevel.none =>
      'Not trained yet this week. Aim for '
          '${MuscleVolume.targetMin}–${MuscleVolume.targetMax} sets.',
    VolumeLevel.low =>
      '${format(week.missing)} more ${week.missing == 1 ? 'set' : 'sets'} to reach '
          '${MuscleVolume.targetMin} this week.',
    VolumeLevel.optimal =>
      'In the ${MuscleVolume.targetMin}–${MuscleVolume.targetMax} '
          'sets range. Nice work.',
    VolumeLevel.high =>
      'Above ${MuscleVolume.targetMax} sets. Make sure it recovers.',
  };
  return showAppDialog<void>(
    context: context,
    title: muscle.label,
    body: Column(
      key: Key('muscle-detail-${muscle.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${MuscleVolume.sets(week.sets)} this week · '
          '${format(week.previous)} last week',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(advice),
        if (week.exercises.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final row in week.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.primary ? row.exercise : '${row.exercise} (assists)',
                    ),
                  ),
                  Text(MuscleVolume.sets(row.sets)),
                ],
              ),
            ),
          if (week.exercises.any((row) => !row.primary))
            Text(
              'Assisting exercises count as half a set.',
              style: TextStyle(
                fontSize: 12,
                color: context.theme.colors.mutedForeground,
              ),
            ),
        ],
      ],
    ),
    actions: [
      FButton(
        variant: .outline,
        onPress: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

const _low = Color(0xFFE2A03F);
const _optimal = Color(0xFF22A06B);
const _high = Color(0xFFD9534F);

/// Under target fades in as sets build up, so 8 sets reads closer to the
/// goal than 2.
Color _fill(FColors colors, double sets) => switch (MuscleVolume.level(sets)) {
  VolumeLevel.none => muscleMapUntrained(colors),
  VolumeLevel.low => muscleMapSolid(
    colors,
    _low.withValues(alpha: 0.35 + 0.65 * sets / MuscleVolume.targetMin),
  ),
  VolumeLevel.optimal => _optimal,
  VolumeLevel.high => _high,
};

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({
    required this.muscle,
    required this.week,
    required this.color,
    required this.onPress,
    super.key,
  });

  final Muscle muscle;
  final MuscleWeek week;
  final Color color;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final change = week.change;
    return FTappable(
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MuscleDot(color: color),
            const SizedBox(width: AppSpacing.xs),
            // Narrow screens and large text: shrink rather than overflow.
            Flexible(
              child: Text(
                '${muscle.label} ${MuscleVolume.format(week.sets)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (change != 0) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                change > 0
                    ? '+${MuscleVolume.format(change)}'
                    : '−${MuscleVolume.format(-change)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: change > 0 ? _optimal : colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
