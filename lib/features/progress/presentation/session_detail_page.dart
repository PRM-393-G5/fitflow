import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/exercise.dart';
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

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Session detail'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
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
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(FLucideIcons.timer),
                title: const Text('Duration'),
                suffix: Text('${session.durationMinutes} min'),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.circleCheckBig),
                title: const Text('Sets completed'),
                suffix: Text('${session.completedSets}'),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.weight),
                title: const Text('Volume'),
                suffix: Text('${volume.round()} $unit'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (session.exercises.isEmpty)
            const FCard(child: Text('No exercises recorded for this session.'))
          else
            FTileGroup(
              children: [
                for (final (index, exercise) in session.exercises.indexed)
                  FTile(
                    prefix: FAvatar.raw(child: Text('${index + 1}')),
                    title: Text(exercise.name),
                    subtitle: Text(_setsLine(exercise, controller.useMetric)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// 'Muscle • 10 × 20 kg · 8 × 22.5 kg' for logged sets, else the plan line.
  static String _setsLine(Exercise exercise, bool metric) {
    if (exercise.performedSets.isEmpty) {
      return '${exercise.muscleGroup} • ${exercise.prescription} • ${exercise.restSeconds}s rest';
    }
    final unit = metric ? 'kg' : 'lb';
    final sets = exercise.performedSets
        .map((set) {
          if (exercise.isTimed) return '${set.amount}s';
          if (set.weightKg <= 0) return '${set.amount} reps';
          final weight = metric ? set.weightKg : set.weightKg * 2.20462;
          return '${set.amount} × ${_trim(weight)} $unit';
        })
        .join(' · ');
    return '${exercise.muscleGroup} • $sets';
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
