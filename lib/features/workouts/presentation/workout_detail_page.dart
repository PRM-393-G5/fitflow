import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import 'active_workout_page.dart';

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({required this.workout, super.key});

  final Workout workout;

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: const Text('Workout details'),
      prefixes: [
        FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
      ],
    ),
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          workout.name,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(workout.description),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            FBadge(variant: .secondary, child: Text(workout.category)),
            FBadge(variant: .secondary, child: Text(workout.level)),
            FBadge(
              variant: .secondary,
              child: Text('${workout.duration.inMinutes} min'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        FTileGroup(
          children: [
            for (final (index, exercise) in workout.exercises.indexed)
              FTile(
                prefix: FAvatar.raw(child: Text('${index + 1}')),
                title: Text(exercise.name),
                subtitle: Text(
                  '${exercise.muscleGroup} • ${exercise.prescription} • ${exercise.restSeconds}s rest',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (workout.exercises.any(
          (exercise) => exercise.name.toLowerCase().contains('squat'),
        )) ...[
          FButton(
            key: const Key('open-squat-form-check-detail'),
            variant: .outline,
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SquatFormCheckPage(controller: AppScope.of(context)),
              ),
            ),
            prefix: const Icon(FLucideIcons.accessibility),
            child: const Text('Check squat form'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        FButton(
          key: const Key('start-workout'),
          onPress: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ActiveWorkoutPage(
                workout: workout,
                controller: AppScope.of(context),
              ),
            ),
          ),
          prefix: const Icon(FLucideIcons.play),
          child: const Text('Start workout'),
        ),
      ],
    ),
  );
}
