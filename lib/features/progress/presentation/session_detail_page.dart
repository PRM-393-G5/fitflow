import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({required this.session, super.key});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final unit = controller.useMetric ? 'kg' : 'lb';
    final volume = controller.useMetric
        ? session.volumeKg
        : session.volumeKg * 2.20462;
    Workout? workout;
    for (final item in controller.workouts) {
      if (item.id == session.workoutId) {
        workout = item;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Session detail')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              session.workoutName,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(_date(session.completedAt)),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Duration'),
                    trailing: Text('${session.durationMinutes} min'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Sets completed'),
                    trailing: Text('${session.completedSets}'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.monitor_weight_outlined),
                    title: const Text('Volume'),
                    trailing: Text('${volume.round()} $unit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (workout == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('This session was not tied to a saved plan.'),
                ),
              )
            else
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
          ],
        ),
      ),
    );
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
