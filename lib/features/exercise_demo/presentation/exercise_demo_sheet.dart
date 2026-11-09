import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/muscle_body_map.dart' show MuscleDot;
import '../../../domain/models/exercise.dart';
import '../../../domain/models/exercise_motion.dart';
import '../../../domain/muscle_volume.dart' show Muscle;
import '../../squat_form/domain/squat_analyzer.dart' show FormExercise;
import 'exercise_demo.dart';

/// How [exercise] is done: the looping demo of [motion] (from the side,
/// front or back), the muscles it works and its form tips.
Future<void> showExerciseDemoSheet(
  BuildContext context, {
  required Exercise exercise,
  required ExerciseMotion motion,
}) => showFSheet<void>(
  context: context,
  side: .btt,
  mainAxisMaxRatio: .infinity,
  builder: (context) => AppSheet(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ExerciseDemoDetails(exercise: exercise, motion: motion),
      ),
    ),
  ),
);

class ExerciseDemoDetails extends StatelessWidget {
  const ExerciseDemoDetails({
    required this.exercise,
    required this.motion,
    super.key,
  });

  final Exercise exercise;
  final ExerciseMotion motion;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final cameraCheck =
        FormExercise.match(exercise.name, timed: exercise.isTimed) != null;
    return Column(
      key: const Key('exercise-demo-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          exercise.name,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          '${exercise.muscleGroup} • ${exercise.prescription}',
          style: TextStyle(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.md),
        AspectRatio(
          aspectRatio: 1,
          child: ExerciseDemo(motion: motion, showAngles: true),
        ),
        if (motion.muscles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Muscles worked', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            key: const Key('exercise-demo-muscles'),
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final muscle in Muscle.values)
                if (motion.muscles.contains(muscle))
                  FBadge(
                    variant: .secondary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MuscleDot(color: workedMuscleColor),
                        const SizedBox(width: AppSpacing.xs),
                        Text(muscle.label),
                      ],
                    ),
                  ),
            ],
          ),
        ],
        if (motion.tips.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final tip in motion.tips)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(FLucideIcons.check, size: 18, color: colors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(tip)),
                ],
              ),
            ),
        ],
        if (cameraCheck) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                FLucideIcons.camera,
                size: 18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'The AI camera can count this one and check your form.',
                  style: TextStyle(color: colors.mutedForeground),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FButton(
          key: const Key('exercise-demo-done'),
          onPress: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
