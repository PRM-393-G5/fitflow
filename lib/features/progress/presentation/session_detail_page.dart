import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/workout_stats.dart';
import '../../../core/widgets/app_card.dart';
import 'edit_session_page.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({required this.session, super.key});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    // Re-read by id so an edit shows here right away.
    final session = controller.sessions.firstWhere(
      (item) => item.id == this.session.id,
      orElse: () => this.session,
    );
    final unit = controller.useMetric ? 'kg' : 'lb';
    final volume = controller.useMetric
        ? session.volumeKg
        : session.volumeKg * 2.20462;
    final formCheck = WorkoutStats.formCheck(session);

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Session detail'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
        suffixes: [
          if (formCheck == null && EditSessionPage.canEdit(session))
            FHeaderAction(
              key: const Key('edit-session'),
              icon: const Icon(FLucideIcons.pencil),
              semanticsLabel: 'Edit session',
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      EditSessionPage(session: session, controller: controller),
                ),
              ),
            ),
          FHeaderAction(
            key: const Key('delete-session'),
            icon: const Icon(FLucideIcons.trash2),
            semanticsLabel: 'Delete session',
            onPress: () => _delete(context, controller),
          ),
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
              if (formCheck == null) ...[
                FTile(
                  prefix: const Icon(FLucideIcons.circleCheckBig),
                  title: const Text('Sets completed'),
                  suffix: Text('${session.completedSets}'),
                ),
                FTile(
                  prefix: const Icon(FLucideIcons.weight),
                  title: const Text('Volume'),
                  suffix: Text('${trimDecimal(volume)} $unit'),
                ),
              ] else
                FTile(
                  prefix: const Icon(FLucideIcons.scanEye),
                  title: Text(formCheck.timed ? 'Hold' : 'Reps'),
                  suffix: Text(WorkoutStats.formCheckLabel(session)!),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (session.exercises.isEmpty)
            const AppCard(
              child: Text('No exercises recorded for this session.'),
            )
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
          return '${set.amount} × ${trimDecimal(weight)} $unit';
        })
        .join(' · ');
    return '${exercise.muscleGroup} • $sets';
  }

  Future<void> _delete(BuildContext context, AppController controller) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Delete this session?',
      body: const Text(
        'It will be removed from your history, stats, and records.',
      ),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FButton(
          key: const Key('confirm-delete-session'),
          variant: .destructive,
          onPress: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    await controller.deleteSession(session.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// [value] with at most one decimal, dropping a trailing ".0".
String trimDecimal(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
