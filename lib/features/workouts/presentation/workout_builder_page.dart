import 'package:flutter/material.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a workout name and at least one exercise.'),
        ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New workout')),
    body: SafeArea(
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Workout name',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: _categories
                  .map(
                    (category) => ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Level', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: _levels
                  .map(
                    (level) => ChoiceChip(
                      label: Text(level),
                      selected: _level == level,
                      onSelected: (_) => setState(() => _level = level),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            ..._exercises.indexed.map(
              (entry) => Card(
                key: ValueKey(entry.$2),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: entry.$2.name,
                              decoration: InputDecoration(
                                labelText: 'Exercise ${entry.$1 + 1}',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove exercise',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _exercises.length == 1
                                ? null
                                : () => setState(() {
                                    _exercises.remove(entry.$2);
                                    entry.$2.dispose();
                                  }),
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
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => setState(() => _exercises.add(_ExerciseDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-custom-workout'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Save workout'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _number(TextEditingController controller, String label) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
    ),
  );
}
