import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/openai_service.dart';
import '../../../domain/ai_workout_parser.dart';
import '../../../domain/models/workout.dart';

/// Natural-language workout builder: describe a session, GPT returns a
/// structured plan, preview it, save as a `custom-ai-*` workout.
class AiWorkoutPage extends StatefulWidget {
  const AiWorkoutPage({super.key});

  @override
  State<AiWorkoutPage> createState() => _AiWorkoutPageState();
}

class _AiWorkoutPageState extends State<AiWorkoutPage> {
  static const _levels = ['Auto', 'Beginner', 'Intermediate', 'Advanced'];
  static const _suggestions = [
    '20-min full body, no equipment',
    'Cardio burn, intermediate',
    'Mobility & stretch, easy',
    'Fat loss circuit',
  ];

  final _requestCtrl = TextEditingController();
  final _service = const OpenAiService();
  String _level = 'Auto';
  double _duration = 30;
  bool _generating = false;
  Workout? _preview;

  @override
  void dispose() {
    _requestCtrl.dispose();
    super.dispose();
  }

  Future<Workout> _generatePlan(String request, String? goal) async {
    FormatException? parseError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final json = await _service.generateJson(
          system: AiWorkoutPrompt.system,
          user: AiWorkoutPrompt.user(
            request: request,
            level: _level == 'Auto' ? null : _level,
            durationMinutes: _duration.round(),
            goal: goal,
          ),
          schema: AiWorkoutPrompt.schema,
          schemaName: 'workout_plan',
        );
        return AiWorkoutParser.parse(json);
      } on FormatException catch (e) {
        parseError = e;
      }
    }
    throw parseError!;
  }

  Future<void> _generate() async {
    final request = _requestCtrl.text.trim();
    if (request.isEmpty || _generating) return;
    final goal = AppScope.of(context).goal;
    setState(() => _generating = true);
    try {
      final workout = await _generatePlan(request, goal);
      if (mounted) setState(() => _preview = workout);
    } on OpenAiException catch (e) {
      _showError(e.message);
    } on FormatException {
      _showError('Could not generate a plan — try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final workout = _preview;
    if (workout == null) return;
    await AppScope.of(context).saveWorkout(workout);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI workout')),
    body: SafeArea(
      child: ResponsiveContent(
        child: _preview != null ? _buildPreview(_preview!) : _buildInput(),
      ),
    ),
  );

  Widget _buildInput() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Describe the workout you want',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text('e.g. "30 minutes, legs, no equipment, beginner friendly"'),
      const SizedBox(height: AppSpacing.md),
      TextField(
        key: const Key('ai-request'),
        controller: _requestCtrl,
        minLines: 3,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Type your request…',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final suggestion in _suggestions)
            ActionChip(
              label: Text(suggestion),
              onPressed: () => _requestCtrl.text = suggestion,
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const Key('ai-level'),
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Level'),
              items: [
                for (final level in _levels)
                  DropdownMenuItem(value: level, child: Text(level)),
              ],
              onChanged: (value) => setState(() => _level = value ?? 'Auto'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_duration.round()} min'),
                Slider(
                  key: const Key('ai-duration'),
                  value: _duration,
                  min: 10,
                  max: 90,
                  divisions: 16,
                  onChanged: (value) => setState(() => _duration = value),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      if (!OpenAiService.configured)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text(
              'AI generation needs an OpenAI API key configured at build '
              'time (--dart-define=OPENAI_API_KEY=…).',
            ),
          ),
        )
      else
        FilledButton.icon(
          key: const Key('ai-generate'),
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_generating ? 'Generating…' : 'Generate workout'),
        ),
    ],
  );

  Widget _buildPreview(Workout workout) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
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
      Text(
        'Exercises (${workout.exercises.length})',
        style: Theme.of(context).textTheme.titleLarge,
      ),
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
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('ai-regenerate'),
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              key: const Key('ai-save'),
              onPressed: _generating ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Save plan'),
            ),
          ),
        ],
      ),
      TextButton(
        key: const Key('ai-edit-request'),
        onPressed: () => setState(() => _preview = null),
        child: const Text('Edit request'),
      ),
    ],
  );
}
