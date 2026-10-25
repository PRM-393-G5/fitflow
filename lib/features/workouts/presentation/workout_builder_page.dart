import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/ai_workout_parser.dart';
import '../../../domain/exercise_catalog.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/training_options.dart';
import 'weight_units.dart';
import 'workout_detail_page.dart';

class _ExerciseDraft {
  _ExerciseDraft({
    required bool metric,
    this.id,
    String name = '',
    int sets = 3,
    int reps = 10,
    int seconds = 30,
    int rest = 45,
    double weightKg = 0,
    this.timed = false,
    this.muscleGroup = 'Full body',
  }) : name = TextEditingController(text: name),
       sets = TextEditingController(text: '$sets'),
       reps = TextEditingController(text: '$reps'),
       seconds = TextEditingController(text: '$seconds'),
       rest = TextEditingController(text: '$rest'),
       initialWeightKg = weightKg,
       initialWeightText = WeightUnits.format(weightKg, metric),
       weight = TextEditingController(
         text: WeightUnits.format(weightKg, metric),
       ) {
    _created = snapshot();
  }

  factory _ExerciseDraft.from(Exercise exercise, {required bool metric}) =>
      _ExerciseDraft(
        metric: metric,
        id: exercise.id,
        name: exercise.name,
        sets: exercise.sets,
        reps: exercise.isTimed ? 10 : exercise.reps,
        seconds: exercise.isTimed ? exercise.durationSeconds : 30,
        rest: exercise.restSeconds,
        weightKg: exercise.weightKg,
        timed: exercise.isTimed,
        muscleGroup: exercise.muscleGroup,
      );

  /// Exercise id kept when editing; new rows get one on save.
  final String? id;
  final TextEditingController name;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController seconds;
  final TextEditingController rest;
  final TextEditingController weight;
  final double initialWeightKg;
  final String initialWeightText;
  bool timed;
  String muscleGroup;
  late final String _created;

  String? nameError;
  String? setsError;
  String? amountError;
  String? restError;
  String? weightError;

  String snapshot() => [
    name.text,
    sets.text,
    reps.text,
    seconds.text,
    rest.text,
    weight.text,
    timed,
    muscleGroup,
  ].join('|');

  /// A fresh row the user never touched — skipped on save.
  bool get untouched => snapshot() == _created && name.text.trim().isEmpty;

  void clearErrors() {
    nameError = null;
    setsError = null;
    amountError = null;
    restError = null;
    weightError = null;
  }

  bool get hasError =>
      nameError != null ||
      setsError != null ||
      amountError != null ||
      restError != null ||
      weightError != null;

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
    seconds.dispose();
    rest.dispose();
    weight.dispose();
  }
}

/// Creates a custom workout, or edits [initial] in place (same id).
class WorkoutBuilderPage extends StatefulWidget {
  const WorkoutBuilderPage({this.initial, super.key});

  final Workout? initial;

  @override
  State<WorkoutBuilderPage> createState() => _WorkoutBuilderPageState();
}

class _WorkoutBuilderPageState extends State<WorkoutBuilderPage> {
  final _name = TextEditingController();
  final _exercises = <_ExerciseDraft>[];
  String _category = 'Strength';
  String _level = 'Beginner';
  bool _saving = false;
  bool _initialized = false;
  late bool _metric;
  late String _initialSnapshot;
  String? _nameError;

  static const _categories = ['Strength', 'Cardio', 'Mobility'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _metric = AppScope.of(context).useMetric;
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      if (_categories.contains(initial.category)) _category = initial.category;
      if (trainingLevels.contains(initial.level)) _level = initial.level;
      _exercises.addAll(
        initial.exercises.map(
          (item) => _ExerciseDraft.from(item, metric: _metric),
        ),
      );
    }
    if (_exercises.isEmpty) _exercises.add(_newDraft());
    _initialSnapshot = _snapshot();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final draft in _exercises) {
      draft.dispose();
    }
    super.dispose();
  }

  _ExerciseDraft _newDraft() => _ExerciseDraft(
    metric: _metric,
    muscleGroup: _category == 'Cardio' ? 'Cardio' : 'Full body',
  );

  String _snapshot() => [
    _name.text,
    _category,
    _level,
    for (final draft in _exercises) draft.snapshot(),
  ].join('\n');

  bool get _dirty => _snapshot() != _initialSnapshot;

  /// The edited workout still exists in the store (not an unsaved AI draft).
  bool get _canDelete {
    final initial = widget.initial;
    return initial != null &&
        AppController.isCustomWorkout(initial) &&
        AppScope.of(context).workouts.any((item) => item.id == initial.id);
  }

  static int? _int(TextEditingController controller, int min, int max) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value >= min && value <= max ? value : null;
  }

  /// Validates every row, showing per-field errors. Null when invalid.
  List<Exercise>? _validExercises() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final exercises = <Exercise>[];
    var valid = true;
    for (final (index, draft) in _exercises.indexed) {
      draft.clearErrors();
      if (draft.untouched) continue;
      final name = draft.name.text.trim();
      final sets = _int(draft.sets, 1, 20);
      final amount = draft.timed
          ? _int(draft.seconds, 1, 600)
          : _int(draft.reps, 1, 100);
      final rest = _int(draft.rest, 0, 600);
      final weightText = draft.weight.text.trim();
      final weight = weightText.isEmpty
          ? 0.0
          : WeightUnits.parseDecimal(weightText);
      if (name.isEmpty) draft.nameError = 'Name this exercise or remove it';
      if (sets == null) draft.setsError = '1–20';
      if (amount == null) draft.amountError = draft.timed ? '1–600' : '1–100';
      if (rest == null) draft.restError = '0–600';
      if (weight == null || weight < 0) {
        draft.weightError = '0 or more';
      } else if (weight > WeightUnits.maxInput(_metric)) {
        draft.weightError = 'Max ${WeightUnits.maxLabel(_metric)}';
      }
      if (draft.hasError) {
        valid = false;
        continue;
      }
      exercises.add(
        Exercise(
          id: draft.id ?? 'custom-ex-$stamp-$index',
          name: name,
          muscleGroup: draft.muscleGroup,
          sets: sets!,
          reps: draft.timed ? 0 : amount!,
          durationSeconds: draft.timed ? amount! : 0,
          restSeconds: rest!,
          weightKg: weightText == draft.initialWeightText
              ? draft.initialWeightKg
              : WeightUnits.toKg(weight!, _metric),
        ),
      );
    }
    return valid ? exercises : null;
  }

  void _toast(String text) => showFToast(context: context, title: Text(text));

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final exercises = _validExercises();
    setState(() => _nameError = name.isEmpty ? 'Enter a workout name' : null);
    if (exercises == null || _nameError != null) {
      _toast('Fix the highlighted fields.');
      return;
    }
    if (exercises.isEmpty) {
      _toast('Add at least one exercise.');
      return;
    }

    final initial = widget.initial;
    final workout = Workout(
      id: initial != null && AppController.isCustomWorkout(initial)
          ? initial.id
          : 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      exercises: exercises,
      duration: estimateWorkoutDuration(exercises),
      level: _level,
      category: _category,
      description: initial == null || initial.description.isEmpty
          ? 'Your custom workout.'
          : initial.description,
    );
    setState(() => _saving = true);
    try {
      await AppScope.of(context).saveWorkout(workout);
    } catch (e) {
      debugPrint('Saving workout failed: $e');
      if (mounted) _toast('Could not save the workout. Try again.');
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop(workout);
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showAppDialog<bool>(
      context: context,
      title: 'Discard changes?',
      body: const Text('Your edits to this workout will be lost.'),
      actions: [
        FButton(
          key: const Key('discard-workout-changes'),
          variant: .destructive,
          onPress: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('Keep editing'),
        ),
      ],
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_saving) _leave();
    },
    child: FScaffold(
      header: FHeader.nested(
        title: Text(widget.initial == null ? 'New workout' : 'Edit workout'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).maybePop()),
        ],
        suffixes: [
          if (_canDelete)
            FHeaderAction(
              key: const Key('builder-delete-workout'),
              icon: const Icon(FLucideIcons.trash2),
              semanticsLabel: 'Delete workout',
              onPress: () => confirmDeleteWorkout(context, widget.initial!),
            ),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTextField(
              key: const Key('builder-name'),
              control: .managed(controller: _name),
              label: const Text('Workout name'),
              error: _nameError == null ? null : Text(_nameError!),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _choices(
              _categories,
              _category,
              (value) => setState(() => _category = value),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Level', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _choices(
              trainingLevels,
              _level,
              (value) => setState(() => _level = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            for (final (index, draft) in _exercises.indexed)
              Padding(
                key: ValueKey(draft),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _draftCard(index, draft),
              ),
            const SizedBox(height: AppSpacing.sm),
            FButton(
              key: const Key('builder-add-exercise'),
              variant: .outline,
              onPress: () => setState(() => _exercises.add(_newDraft())),
              prefix: const Icon(FLucideIcons.plus),
              child: const Text('Add exercise'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FButton(
                key: const Key('save-custom-workout'),
                onPress: _saving ? null : _save,
                prefix: const Icon(FLucideIcons.check),
                child: Text(
                  widget.initial == null ? 'Save workout' : 'Save changes',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _choices(
    List<String> values,
    String selected,
    ValueChanged<String> onSelect,
  ) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final value in values)
        FButton(
          variant: selected == value ? .primary : .outline,
          size: .sm,
          mainAxisSize: .min,
          onPress: () => onSelect(value),
          child: Text(value),
        ),
    ],
  );

  Widget _draftCard(int index, _ExerciseDraft draft) {
    // Keep a legacy group (e.g. "Glutes") selectable when editing.
    final groups = {...workoutMuscleGroups, draft.muscleGroup};
    final controller = AppScope.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FTextField(
                  key: Key('builder-exercise-name-$index'),
                  control: .managed(controller: draft.name),
                  label: Text('Exercise ${index + 1}'),
                  error: draft.nameError == null
                      ? null
                      : Text(draft.nameError!),
                ),
              ),
              FButton.icon(
                variant: .ghost,
                onPress: _exercises.length == 1
                    ? null
                    : () => setState(() {
                        _exercises.remove(draft);
                        draft.dispose();
                      }),
                child: const Icon(FLucideIcons.trash2),
              ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: draft.name,
            builder: (context, value, _) {
              final suggestions = ExerciseCatalog.suggestions(
                query: value.text,
                muscleGroup: draft.muscleGroup,
                workouts: controller.workouts,
                sessions: controller.sessions,
                limit: 6,
              );
              if (suggestions.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: FButton(
                            key: Key('builder-suggest-$index-${item.name}'),
                            variant: .outline,
                            size: .sm,
                            mainAxisSize: .min,
                            onPress: () => _applySuggestion(draft, item),
                            prefix: item.hasCameraCheck
                                ? const Icon(
                                    FLucideIcons.accessibility,
                                    size: 14,
                                  )
                                : null,
                            child: Text(item.name),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FButton(
                key: Key('builder-reps-$index'),
                variant: draft.timed ? .outline : .primary,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => setState(() => draft.timed = false),
                child: const Text('Reps'),
              ),
              const SizedBox(width: AppSpacing.xs),
              FButton(
                key: Key('builder-timed-$index'),
                variant: draft.timed ? .primary : .outline,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => setState(() => draft.timed = true),
                child: const Text('Seconds'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey(draft.muscleGroup),
                  child: FSelect<String>(
                    key: Key('builder-muscle-$index'),
                    items: {for (final group in groups) group: group},
                    control: .managed(
                      initial: draft.muscleGroup,
                      onChange: (value) {
                        if (value != null) {
                          setState(() => draft.muscleGroup = value);
                        }
                      },
                    ),
                    hint: 'Muscle group',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _number(
                draft.sets,
                'Sets',
                draft.setsError,
                Key('builder-sets-$index'),
              ),
              if (draft.timed)
                _number(
                  draft.seconds,
                  'Seconds',
                  draft.amountError,
                  Key('builder-seconds-$index'),
                )
              else
                _number(
                  draft.reps,
                  'Reps',
                  draft.amountError,
                  Key('builder-amount-$index'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _number(
                draft.rest,
                'Rest (s)',
                draft.restError,
                Key('builder-rest-$index'),
              ),
              _number(
                draft.weight,
                'Weight (${WeightUnits.label(_metric)})',
                draft.weightError,
                Key('builder-weight-$index'),
                decimal: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _applySuggestion(_ExerciseDraft draft, CatalogExercise item) {
    final untouchedPrescription =
        draft.sets.text == '3' &&
        draft.reps.text == '10' &&
        draft.seconds.text == '30' &&
        draft.rest.text == '45';
    setState(() {
      draft.name.text = item.name;
      draft.nameError = null;
      draft.muscleGroup = item.muscleGroup;
      draft.timed = item.isTimed;
      if (untouchedPrescription) {
        draft.sets.text = '${item.defaultSets}';
        if (item.isTimed) {
          draft.seconds.text = '${item.defaultSeconds}';
        } else {
          draft.reps.text = '${item.defaultReps}';
        }
        draft.rest.text = '${item.defaultRestSeconds}';
      }
    });
  }

  Widget _number(
    TextEditingController controller,
    String label,
    String? error,
    Key key, {
    bool decimal = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FTextField(
        key: key,
        control: .managed(controller: controller),
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        label: Text(label),
        error: error == null ? null : Text(error),
      ),
    ),
  );
}
