import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/workout_stats.dart';
import '../../../core/widgets/app_card.dart';
import '../../squat_form/presentation/form_review_view.dart';
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
          if (EditSessionPage.canEdit(session))
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
                    key: Key('session-exercise-$index'),
                    prefix: FAvatar.raw(child: Text('${index + 1}')),
                    title: Text(exercise.name),
                    subtitle: Text(
                      [
                        _setsLine(exercise, controller.useMetric),
                        ?_formLine(exercise),
                      ].join('\n'),
                    ),
                    // Camera-judged sets open their per-rep review.
                    suffix: _hasForm(exercise)
                        ? const Icon(FLucideIcons.chevronRight)
                        : null,
                    onPress: _hasForm(exercise)
                        ? () => _showForm(context, exercise)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static bool _hasForm(Exercise exercise) =>
      exercise.performedSets.any((set) => set.form?.quality != null);

  /// 'Form: 4/5 clean reps' over the camera-judged sets, or null.
  static String? _formLine(Exercise exercise) {
    // Only sets with something judged: an empty verdict says nothing.
    final forms = [
      for (final set in exercise.performedSets)
        if (set.form case final form? when form.quality != null) form,
    ];
    if (forms.isEmpty) return null;
    if (forms.length == 1) return 'Form: ${formSummaryLabel(forms.single)}';
    if (forms.every((form) => form.hold == null)) {
      final reps = [for (final form in forms) ...form.reps];
      final clean = reps.where((rep) => rep.clean).length;
      return 'Form: $clean/${reps.length} clean reps over ${forms.length} sets';
    }
    final mean =
        forms.map((form) => form.quality!).reduce((a, b) => a + b) /
        forms.length;
    return 'Form: ${(mean * 100).round()}% good over ${forms.length} sets';
  }

  static void _showForm(BuildContext context, Exercise exercise) =>
      showFSheet<void>(
        context: context,
        side: .btt,
        mainAxisMaxRatio: .infinity,
        builder: (context) => AppSheet(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${exercise.name} — form review',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  for (final (index, set) in exercise.performedSets.indexed)
                    if (set.form case final form?
                        when form.quality != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Set ${index + 1} · ${formSummaryLabel(form)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      FormReviewView(result: form),
                    ],
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FButton(
                      key: const Key('session-form-done'),
                      onPress: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

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
