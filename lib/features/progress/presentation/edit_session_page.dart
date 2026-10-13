import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
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

  /// Whether [session] has logged sets to edit (form checks and sessions
  /// from before per-set logging don't).
  static bool canEdit(WorkoutSession session) =>
      session.exercises.any((exercise) => exercise.performedSets.isNotEmpty);

  @override
  State<EditSessionPage> createState() => _EditSessionPageState();
}

/// The fields of one logged set.
class _SetFields {
  _SetFields(this.entry, bool metric)
    : prefillWeight = entry.weightKg > 0
          ? WeightUnits.format(entry.weightKg, metric)
          : '',
      amount = TextEditingController(text: '${entry.amount}') {
    weight = TextEditingController(text: prefillWeight);
  }

  final SetEntry entry;
  final String prefillWeight;
  final TextEditingController amount;
  late final TextEditingController weight;
  String? amountError;
  String? weightError;

  void dispose() {
    amount.dispose();
    weight.dispose();
  }
}

class _EditSessionPageState extends State<EditSessionPage> {
  static const _maxReps = 1000;
  static const _maxSeconds = 3600;

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

  /// The edited set, or null (with errors shown) when a field is invalid.
  /// An untouched weight keeps its stored kg, so a weight shown in lb is
  /// not re-rounded.
  SetEntry? _read(_SetFields fields, bool timed) {
    final amount = int.tryParse(fields.amount.text.trim());
    final text = fields.weight.text.trim();
    final weight = text.isEmpty ? 0.0 : WeightUnits.parseDecimal(text);
    final maxAmount = timed ? _maxSeconds : _maxReps;
    fields.amountError = amount == null || amount < 1
        ? (timed ? 'At least 1 s' : 'At least 1')
        : amount > maxAmount
        ? 'Max $maxAmount'
        : null;
    fields.weightError = weight == null || weight < 0
        ? '0 or more'
        : weight > WeightUnits.maxInput(_metric)
        ? 'Max ${WeightUnits.maxLabel(_metric)}'
        : null;
    if (fields.amountError != null || fields.weightError != null) return null;
    return SetEntry(
      amount: amount!,
      weightKg: text == fields.prefillWeight
          ? fields.entry.weightKg
          : WeightUnits.toKg(weight!, _metric),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    var valid = true;
    final exercises = <Exercise>[];
    for (final (index, exercise) in widget.session.exercises.indexed) {
      final sets = <SetEntry>[];
      for (final fields in _fields[index]) {
        final entry = _read(fields, exercise.isTimed);
        if (entry == null) {
          valid = false;
        } else {
          sets.add(entry);
        }
      }
      exercises.add(
        exercise.performedSets.isEmpty
            ? exercise
            : exercise.copyWith(performedSets: sets),
      );
    }
    setState(() {});
    if (!valid) return;
    setState(() => _saving = true);
    final updated = widget.session.copyWith(
      exercises: exercises,
      volumeKg: exercises.fold<double>(
        0,
        (sum, item) => sum + item.performedVolumeKg,
      ),
    );
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
