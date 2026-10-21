import 'dart:math' as math;

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/load_math.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';
import '../../../domain/workout_stats.dart';
import '../../workouts/presentation/set_input.dart';
import '../../workouts/presentation/weight_units.dart';

/// Fixes the reps (or seconds) and weight of each logged set of a past
/// session — e.g. a 600 typed for 60. Sets can't be added or removed.
/// Records and progression hints are derived from history, so they
/// follow the corrected numbers.
class EditSessionPage extends StatefulWidget {
  const EditSessionPage({
    required this.session,
    required this.controller,
    super.key,
  });

  final WorkoutSession session;
  final AppController controller;

  /// Whether [session] has logged sets to edit. Form checks don't: their
  /// count is part of the result, not a set to correct; nor do sessions
  /// from before per-set logging.
  static bool canEdit(WorkoutSession session) =>
      session.workoutId != WorkoutStats.formCheckId &&
      session.exercises.any((exercise) => exercise.performedSets.isNotEmpty);

  @override
  State<EditSessionPage> createState() => _EditSessionPageState();
}

/// The fields of one logged set, and the texts they started from.
class _SetFields {
  _SetFields(this.entry, bool metric)
    : amountText = '${entry.amount}',
      weightText = entry.weightKg > 0
          ? WeightUnits.format(entry.weightKg, metric)
          : '' {
    amount = TextEditingController(text: amountText);
    weight = TextEditingController(text: weightText);
  }

  final SetEntry entry;
  final String amountText;
  final String weightText;
  late final TextEditingController amount;
  late final TextEditingController weight;
  String? amountError;
  String? weightError;

  bool get amountChanged => amount.text.trim() != amountText;
  bool get weightChanged => weight.text.trim() != weightText;

  void dispose() {
    amount.dispose();
    weight.dispose();
  }
}

/// One validated change: set [setIndex] of exercise [exerciseIndex].
typedef _Change = ({
  int exerciseIndex,
  int setIndex,
  int? amount,
  double? weightKg,
});

class _EditSessionPageState extends State<EditSessionPage> {
  late final bool _metric = widget.controller.useMetric;
  late final List<List<_SetFields>> _fields = [
    for (final exercise in widget.session.exercises)
      [for (final set in exercise.performedSets) _SetFields(set, _metric)],
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final sets in _fields) {
      for (final set in sets) {
        set.dispose();
      }
    }
    super.dispose();
  }

  /// The edited fields, validated; only fields the user changed are
  /// checked, so a stored value outside today's limits never blocks
  /// fixing another set. Null (with errors shown) when one is invalid.
  List<_Change>? _changes() {
    var valid = true;
    final changes = <_Change>[];
    for (final (exerciseIndex, exercise) in widget.session.exercises.indexed) {
      for (final (setIndex, fields) in _fields[exerciseIndex].indexed) {
        final amount = fields.amountChanged
            ? SetInput.amount(fields.amount.text, timed: exercise.isTimed)
            : null;
        final weight = fields.weightChanged
            ? SetInput.weight(fields.weight.text, metric: _metric)
            : null;
        fields.amountError = amount?.error;
        fields.weightError = weight?.error;
        if (amount?.error != null || weight?.error != null) {
          valid = false;
        } else if (amount != null || weight != null) {
          changes.add((
            exerciseIndex: exerciseIndex,
            setIndex: setIndex,
            amount: amount?.value,
            weightKg: weight?.kg,
          ));
        }
      }
    }
    setState(() {});
    return valid ? changes : null;
  }

  /// [changes] applied to [base]: changed fields replace, untouched ones
  /// keep [base]'s values. Null when [base] no longer has the same sets
  /// (it changed on another device while this page was open).
  static WorkoutSession? _apply(WorkoutSession base, List<_Change> changes) {
    final exercises = [
      for (final exercise in base.exercises) [...exercise.performedSets],
    ];
    for (final change in changes) {
      if (change.exerciseIndex >= exercises.length ||
          change.setIndex >= exercises[change.exerciseIndex].length) {
        return null;
      }
      final sets = exercises[change.exerciseIndex];
      final set = sets[change.setIndex];
      final amount = change.amount ?? set.amount;
      sets[change.setIndex] = SetEntry(
        amount: amount,
        weightKg: change.weightKg ?? set.weightKg,
        // The camera verdict describes the reps it counted: kept while the
        // count stands, dropped once the reps are edited.
        form: amount == set.amount ? set.form : null,
      );
    }
    final updated = [
      for (final (index, exercise) in base.exercises.indexed)
        exercise.copyWith(performedSets: exercises[index]),
    ];
    return base.copyWith(
      exercises: updated,
      volumeKg: updated.fold<double>(
        0,
        (sum, item) => sum + item.performedVolumeKg,
      ),
    );
  }

  /// Changed loads far above the exercise's best elsewhere — other
  /// sessions and the other sets here.
  List<({double kg, String exercise})> _suspicious(
    WorkoutSession updated,
    List<_Change> changes,
  ) {
    final sessions = widget.controller.sessions;
    return [
      for (final change in changes)
        if (change.weightKg case final kg?)
          if (LoadMath.looksMistyped(
            kg,
            _bestElsewhere(sessions, updated, change),
          ))
            (kg: kg, exercise: updated.exercises[change.exerciseIndex].name),
    ];
  }

  static double _bestElsewhere(
    List<WorkoutSession> sessions,
    WorkoutSession updated,
    _Change change,
  ) {
    final exercise = updated.exercises[change.exerciseIndex];
    var best = PersonalRecords.heaviestLoad(
      sessions,
      exercise.name,
      timed: exercise.isTimed,
      exceptSessionId: updated.id,
    );
    for (final (index, other) in updated.exercises.indexed) {
      if (other.isTimed != exercise.isTimed ||
          other.name.trim().toLowerCase() !=
              exercise.name.trim().toLowerCase()) {
        continue;
      }
      for (final (setIndex, set) in other.performedSets.indexed) {
        final self =
            index == change.exerciseIndex && setIndex == change.setIndex;
        if (!self && set.amount > 0) best = math.max(best, set.weightKg);
      }
    }
    return best;
  }

  Future<void> _save() async {
    if (_saving) return;
    final changes = _changes();
    if (changes == null) return;
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    // Apply onto the latest copy: a sync may have updated the session
    // while this page was open, and untouched fields keep its values.
    final latest = widget.controller.sessions
        .where((item) => item.id == widget.session.id)
        .firstOrNull;
    final updated = latest == null ? null : _apply(latest, changes);
    if (updated == null) {
      showFToast(
        context: context,
        title: const Text('This session changed. Reopen it to edit.'),
      );
      Navigator.of(context).pop();
      return;
    }
    final suspicious = _suspicious(updated, changes);
    if (suspicious.isNotEmpty && !await _confirmHeavy(suspicious)) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.addSession(updated);
    } catch (e) {
      debugPrint('Saving edited session failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      showFToast(
        context: context,
        title: const Text('Could not save the changes. Try again.'),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _weight(double kg) =>
      '${WeightUnits.format(kg, _metric)} ${WeightUnits.label(_metric)}';

  Future<bool> _confirmHeavy(
    List<({double kg, String exercise})> loads,
  ) async =>
      await showAppDialog<bool>(
        context: context,
        title: 'Save ${_weight(loads.first.kg)}?',
        body: Text(
          '${loads.map((load) => '${_weight(load.kg)} on ${load.exercise}').join(', ')} '
          'is far above your best on that exercise. Check for a typo '
          'before saving.',
        ),
        actions: [
          FButton(
            key: const Key('fix-heavy-edit'),
            variant: .ghost,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Fix it'),
          ),
          FButton(
            key: const Key('confirm-heavy-edit'),
            onPress: () => Navigator.pop(context, true),
            child: const Text('Save it'),
          ),
        ],
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final unit = WeightUnits.label(_metric);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Edit session'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Fix a mistyped set. Records and next-session suggestions '
            'update from the corrected numbers.',
            style: TextStyle(color: context.theme.colors.mutedForeground),
          ),
          for (final (index, exercise) in widget.session.exercises.indexed)
            if (exercise.performedSets.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                exercise.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final (setIndex, fields) in _fields[index].indexed) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: Text('Set ${setIndex + 1}'),
                      ),
                    ),
                    Expanded(
                      child: FTextField(
                        key: Key('edit-amount-$index-$setIndex'),
                        control: .managed(controller: fields.amount),
                        keyboardType: TextInputType.number,
                        label: Text(exercise.isTimed ? 'Seconds' : 'Reps'),
                        error: fields.amountError == null
                            ? null
                            : Text(fields.amountError!),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FTextField(
                        key: Key('edit-weight-$index-$setIndex'),
                        control: .managed(controller: fields.weight),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        label: Text('Weight ($unit)'),
                        error: fields.weightError == null
                            ? null
                            : Text(fields.weightError!),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          const SizedBox(height: AppSpacing.xl),
          FButton(
            key: const Key('save-session-edit'),
            onPress: _saving ? null : _save,
            prefix: const Icon(FLucideIcons.check),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
