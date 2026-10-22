import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/muscle_body_map.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/muscle_volume.dart';

/// The muscles a workout plan trains, highlighted on the body: main movers
/// in the primary colour, helpers lighter. Tapping a muscle lists the
/// exercises that reach it. Nothing is shown when no exercise maps to a
/// muscle (mobility, cardio, full body).
class WorkoutMusclesCard extends StatelessWidget {
  const WorkoutMusclesCard({required this.exercises, super.key});

  final List<Exercise> exercises;

  @override
  Widget build(BuildContext context) {
    final planned = MuscleVolume.planned(exercises);
    if (planned.isEmpty) return const SizedBox.shrink();

    final colors = context.theme.colors;
    final mainColor = colors.primary;
    final helperColor = muscleMapSolid(
      colors,
      colors.primary.withValues(alpha: .35),
    );
    // Body order (Muscle.values), not map order.
    final main = [
      for (final muscle in Muscle.values)
        if (planned[muscle] case final rows? when MuscleVolume.isPrimary(rows))
          muscle,
    ];
    final helpers = [
      for (final muscle in Muscle.values)
        if (planned[muscle] case final rows? when !MuscleVolume.isPrimary(rows))
          muscle,
    ];
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);

    return AppCard(
      key: const Key('workout-muscles'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MuscleBodyMap(
            height: 240,
            fills: {
              for (final muscle in main) muscle: mainColor,
              for (final muscle in helpers) muscle: helperColor,
            },
            onTap: (muscle) => _showDetail(context, muscle, planned[muscle]),
            semanticsLabel:
                'Muscles worked. Main: '
                '${main.map((m) => m.label).join(', ')}'
                '${helpers.isEmpty ? '' : '. Assisting: '
                          '${helpers.map((m) => m.label).join(', ')}'}',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap a muscle to see which exercises train it',
            textAlign: TextAlign.center,
            style: labelStyle,
          ),
          const SizedBox(height: AppSpacing.md),
          _MuscleLine(
            key: const Key('workout-muscles-main'),
            color: mainColor,
            title: 'Main',
            muscles: main,
          ),
          if (helpers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _MuscleLine(
              key: const Key('workout-muscles-assisting'),
              color: helperColor,
              title: 'Assisting',
              muscles: helpers,
            ),
          ],
        ],
      ),
    );
  }
}

class _MuscleLine extends StatelessWidget {
  const _MuscleLine({
    required this.color,
    required this.title,
    required this.muscles,
    super.key,
  });

  final Color color;
  final String title;
  final List<Muscle> muscles;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: MuscleDot(color: color),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: muscles.map((m) => m.label).join(', ')),
            ],
          ),
        ),
      ),
    ],
  );
}

Future<void> _showDetail(
  BuildContext context,
  Muscle muscle,
  List<MuscleContribution>? rows,
) => showAppDialog<void>(
  context: context,
  title: muscle.label,
  body: Column(
    key: Key('workout-muscle-detail-${muscle.name}'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (rows == null || rows.isEmpty)
        const Text('This workout doesn\'t train it.')
      else ...[
        Text(
          '${MuscleVolume.sets(rows.fold(0, (sum, row) => sum + row.sets))} '
          'in this workout',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final row in rows)
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
        if (rows.any((row) => !row.primary))
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
