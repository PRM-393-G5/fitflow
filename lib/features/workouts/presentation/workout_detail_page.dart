import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import 'active_workout_page.dart';

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({required this.workout, super.key});

  final Workout workout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Workout details')),
    body: SafeArea(
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
              Chip(label: Text(workout.category)),
              Chip(label: Text(workout.level)),
              Chip(label: Text('${workout.duration.inMinutes} min')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...workout.exercises.indexed.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                title: Text(entry.$2.name),
                subtitle: Text(
                  '${entry.$2.muscleGroup} • ${entry.$2.prescription} • ${entry.$2.restSeconds}s rest',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (workout.exercises.any(
            (exercise) => exercise.name.toLowerCase().contains('squat'),
          )) ...[
            OutlinedButton.icon(
              key: const Key('open-squat-form-check-detail'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SquatFormCheckPage(controller: AppScope.of(context)),
                ),
              ),
              icon: const Icon(Icons.accessibility_new),
              label: const Text('Check squat form'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          FilledButton.icon(
            key: const Key('start-workout'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ActiveWorkoutPage(
                  workout: workout,
                  controller: AppScope.of(context),
                ),
              ),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start workout'),
          ),
        ],
      ),
    ),
  );
}
