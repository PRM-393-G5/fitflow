import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout.dart';

class _ExerciseDraft {
  final name = TextEditingController();
  final sets = TextEditingController(text: '3');
  final reps = TextEditingController(text: '10');
  final rest = TextEditingController(text: '45');
  final weight = TextEditingController(text: '0');

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
    rest.dispose();
    weight.dispose();
  }
}

class WorkoutBuilderPage extends StatefulWidget {
  const WorkoutBuilderPage({super.key});

  @override
  State<WorkoutBuilderPage> createState() => _WorkoutBuilderPageState();
}

class _WorkoutBuilderPageState extends State<WorkoutBuilderPage> {
  final _name = TextEditingController();
  final _exercises = [_ExerciseDraft()];
  String _category = 'Strength';
  String _level = 'Beginner';
  bool _saving = false;

  static const _categories = ['Strength', 'Cardio', 'Mobility'];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  @override
  void dispose() {
    _name.dispose();
    for (final draft in _exercises) {
      draft.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _save() async {
    final name = _name.text.trim();
    final exercises = _exercises
        .where((draft) => draft.name.text.trim().isNotEmpty)
        .map(
          (draft) => Exercise(
            id: 'custom-${draft.name.text.trim().toLowerCase().replaceAll(' ', '-')}',
            name: draft.name.text.trim(),
            muscleGroup: _category,
            sets: _int(draft.sets, 3).clamp(1, 20),
            reps: _int(draft.reps, 10).clamp(1, 100),
            restSeconds: _int(draft.rest, 45).clamp(0, 600),
            weightKg:
                double.tryParse(draft.weight.text.trim())?.clamp(0, 500) ?? 0,
          ),
        )
        .toList();

    if (name.isEmpty || exercises.isEmpty) {
      showFToast(
        context: context,
        title: const Text('Add a workout name and at least one exercise.'),
      );
      return;
    }

    final seconds = exercises.fold<int>(
      0,
      (sum, item) => sum + item.sets * (45 + item.restSeconds),
    );
    setState(() => _saving = true);
    await AppScope.of(context).saveWorkout(
      Workout(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        exercises: exercises,
        duration: Duration(minutes: (seconds / 60).ceil()),
        level: _level,
        category: _category,
        description: 'Your custom workout.',
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: const Text('New workout'),
      prefixes: [
        FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
      ],
    ),
    child: ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTextField(
            control: .managed(controller: _name),
            label: const Text('Workout name'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Category', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final category in _categories)
                FButton(
                  variant: _category == category ? .primary : .outline,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: () => setState(() => _category = category),
                  child: Text(category),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Level', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final level in _levels)
                FButton(
                  variant: _level == level ? .primary : .outline,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: () => setState(() => _level = level),
                  child: Text(level),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ..._exercises.indexed.map(
            (entry) => FCard(
              key: ValueKey(entry.$2),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FTextField(
                          control: .managed(controller: entry.$2.name),
                          label: Text('Exercise ${entry.$1 + 1}'),
                        ),
                      ),
                      FButton.icon(
                        variant: .ghost,
                        onPress: _exercises.length == 1
                            ? null
                            : () => setState(() {
                                _exercises.remove(entry.$2);
                                entry.$2.dispose();
                              }),
                        child: const Icon(FLucideIcons.trash2),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _number(entry.$2.sets, 'Sets'),
                      _number(entry.$2.reps, 'Reps'),
                      _number(entry.$2.rest, 'Rest (s)'),
                      _number(entry.$2.weight, 'Kg'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FButton(
            variant: .outline,
            onPress: () => setState(() => _exercises.add(_ExerciseDraft())),
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
              child: const Text('Save workout'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _number(TextEditingController controller, String label) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FTextField(
        control: .managed(controller: controller),
        keyboardType: TextInputType.number,
        label: Text(label),
      ),
    ),
  );
}
