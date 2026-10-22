import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/muscle_volume.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import 'active_workout_page.dart';
import 'weight_units.dart';
import 'workout_builder_page.dart';
import 'workout_muscles_card.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Confirms, deletes the custom [workout] and returns to the first route
/// (the workout list). Past sessions of the plan stay in Progress.
Future<void> confirmDeleteWorkout(BuildContext context, Workout workout) async {
  final controller = AppScope.of(context);
  final confirmed = await showAppDialog<bool>(
    context: context,
    title: 'Delete workout?',
    body: Text(
      '"${workout.name}" will be removed from your plans and schedule. '
      'Past sessions stay in Progress.',
    ),
    actions: [
      FButton(
        key: const Key('confirm-delete-workout'),
        variant: .destructive,
        onPress: () => Navigator.pop(context, true),
        child: const Text('Delete'),
      ),
      FButton(
        variant: .ghost,
        onPress: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
    ],
  );
  if (confirmed != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  try {
    await controller.deleteWorkout(workout.id);
  } catch (e) {
    debugPrint('Deleting workout failed: $e');
    if (context.mounted) {
      showFToast(
        context: context,
        title: const Text('Could not delete the workout. Try again.'),
      );
    }
    return;
  }
  navigator.popUntil((route) => route.isFirst);
}

String _relativeDay(DateTime date) {
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  return '${day.day}/${day.month}/${day.year}';
}

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({required this.workout, super.key});

  final Workout workout;

  Future<void> _addToSchedule(
    BuildContext context,
    AppController controller,
    Workout current,
  ) async {
    final colors = context.theme.colors;
    final weekday = await showAppDialog<int>(
      context: context,
      title: 'Add to schedule',
      body: FTileGroup(
        children: [
          for (var day = 1; day <= 7; day++)
            FTile(
              title: Text(_weekdayNames[day - 1]),
              subtitle: Text(_dayLabel(controller, day)),
              suffix: controller.schedule[day] == current.id
                  ? Icon(FLucideIcons.check, color: colors.primary)
                  : null,
              onPress: () => Navigator.pop(context, day),
            ),
        ],
      ),
    );
    if (weekday == null || !context.mounted) return;
    await controller.setScheduleDay(weekday, current.id);
    if (context.mounted) {
      showFToast(
        context: context,
        title: Text('Scheduled for ${_weekdayNames[weekday - 1]}.'),
      );
    }
  }

  static String _dayLabel(AppController controller, int weekday) {
    if (controller.isRestDay(weekday)) return 'Rest day';
    return controller.scheduledWorkout(weekday)?.name ?? 'Unassigned';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    // Re-read by id so edits made in the builder show up here.
    final current = controller.workouts.firstWhere(
      (item) => item.id == workout.id,
      orElse: () => workout,
    );
    final custom = AppController.isCustomWorkout(current);
    final metric = controller.useMetric;
    WorkoutSession? last;
    for (final session in controller.sessions) {
      if (session.workoutId == current.id) {
        last = session;
        break;
      }
    }
    final canStart = current.totalSets > 0;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Workout details'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
        suffixes: [
          if (custom) ...[
            FHeaderAction(
              key: const Key('edit-workout'),
              icon: const Icon(FLucideIcons.pencil),
              semanticsLabel: 'Edit workout',
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute<Workout>(
                  builder: (_) => WorkoutBuilderPage(initial: current),
                ),
              ),
            ),
            FHeaderAction(
              key: const Key('delete-workout'),
              icon: const Icon(FLucideIcons.trash2),
              semanticsLabel: 'Delete workout',
              onPress: () => confirmDeleteWorkout(context, current),
            ),
          ],
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            current.name,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(current.description),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FBadge(variant: .secondary, child: Text(current.category)),
              FBadge(variant: .secondary, child: Text(current.level)),
              FBadge(
                variant: .secondary,
                child: Text('${current.duration.inMinutes} min'),
              ),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              key: const Key('last-performed'),
              child: Row(
                children: [
                  Icon(
                    FLucideIcons.history,
                    color: context.theme.colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last performed ${_relativeDay(last.completedAt)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          [
                            '${last.completedSets} sets',
                            '${last.durationMinutes} min',
                            if (last.volumeKg > 0)
                              '${WeightUnits.format(last.volumeKg, metric)} '
                                  '${WeightUnits.label(metric)} volume',
                          ].join(' • '),
                          style: TextStyle(
                            color: context.theme.colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (MuscleVolume.planned(current.exercises).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Muscles worked',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            WorkoutMusclesCard(exercises: current.exercises),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (current.exercises.isEmpty)
            const Text('This workout has no exercises yet.')
          else
            FTileGroup(
              children: [
                for (final (index, exercise) in current.exercises.indexed)
                  FTile(
                    prefix: FAvatar.raw(child: Text('${index + 1}')),
                    title: Text(exercise.name),
                    subtitle: Text(
                      [
                        exercise.muscleGroup,
                        exercise.prescription,
                        if (exercise.weightKg > 0)
                          '${WeightUnits.format(exercise.weightKg, metric)} '
                              '${WeightUnits.label(metric)}',
                        '${exercise.restSeconds}s rest',
                      ].join(' • '),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          if (current.exercises.any(
            (exercise) => exercise.name.toLowerCase().contains('squat'),
          )) ...[
            FButton(
              key: const Key('open-squat-form-check-detail'),
              variant: .outline,
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SquatFormCheckPage(controller: controller),
                ),
              ),
              prefix: const Icon(FLucideIcons.accessibility),
              child: const Text('Check squat form'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          FButton(
            key: const Key('add-to-schedule'),
            variant: .outline,
            onPress: () => _addToSchedule(context, controller, current),
            prefix: const Icon(FLucideIcons.calendarPlus),
            child: const Text('Add to schedule'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FButton(
            key: const Key('start-workout'),
            onPress: canStart
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActiveWorkoutPage(
                        workout: current,
                        controller: controller,
                      ),
                    ),
                  )
                : null,
            prefix: const Icon(FLucideIcons.play),
            child: const Text('Start workout'),
          ),
        ],
      ),
    );
  }
}
