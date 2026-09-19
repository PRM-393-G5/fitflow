import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

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
  // Track fraction 0..1 mapped onto 10..90 minutes in 5-minute steps.
  late final FContinuousSliderController _durationControl;
  bool _generating = false;
  Workout? _preview;

  @override
  void initState() {
    super.initState();
    _durationControl =
        FContinuousSliderController(
          value: FSliderValue(max: (_duration - 10) / 80),
        )..addListener(
          () => setState(
            () => _duration =
                10.0 + (_durationControl.value.max * 80 / 5).round() * 5,
          ),
        );
  }

  @override
  void dispose() {
    _requestCtrl.dispose();
    _durationControl.dispose();
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
    showFToast(context: context, title: Text(text));
  }

  Future<void> _save() async {
    final workout = _preview;
    if (workout == null) return;
    await AppScope.of(context).saveWorkout(workout);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: const Text('AI workout'),
      prefixes: [
        FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
      ],
    ),
    child: ResponsiveContent(
      child: _preview != null ? _buildPreview(_preview!) : _buildInput(),
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
      FTextField(
        key: const Key('ai-request'),
        control: .managed(controller: _requestCtrl),
        minLines: 3,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        hint: 'Type your request…',
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final suggestion in _suggestions)
            FButton(
              variant: .outline,
              size: .sm,
              mainAxisSize: .min,
              onPress: () => _requestCtrl.text = suggestion,
              child: Text(suggestion),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FSelect<String>(
              key: const Key('ai-level'),
              items: {for (final level in _levels) level: level},
              control: .managed(
                initial: _level,
                onChange: (value) => setState(() => _level = value ?? 'Auto'),
              ),
              label: const Text('Level'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Text('${_duration.round()} min'),
                FSlider(
                  key: const Key('ai-duration'),
                  control: .managedContinuous(controller: _durationControl),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      if (!OpenAiService.configured)
        const FCard(
          child: Text(
            'AI generation needs an OpenAI API key '
            '(.env file or --dart-define=OPENAI_API_KEY=…).',
          ),
        )
      else
        FButton(
          key: const Key('ai-generate'),
          onPress: _generating ? null : _generate,
          prefix: _generating
              ? const FCircularProgress()
              : const Icon(FLucideIcons.sparkles),
          child: Text(_generating ? 'Generating…' : 'Generate workout'),
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
          FBadge(variant: .secondary, child: Text(workout.category)),
          FBadge(variant: .secondary, child: Text(workout.level)),
          FBadge(
            variant: .secondary,
            child: Text('${workout.duration.inMinutes} min'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        'Exercises (${workout.exercises.length})',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.sm),
      FTileGroup(
        children: [
          for (final (index, exercise) in workout.exercises.indexed)
            FTile(
              prefix: FAvatar.raw(child: Text('${index + 1}')),
              title: Text(exercise.name),
              subtitle: Text(
                '${exercise.muscleGroup} • ${exercise.prescription} • ${exercise.restSeconds}s rest',
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: FButton(
              key: const Key('ai-regenerate'),
              variant: .outline,
              onPress: _generating ? null : _generate,
              prefix: _generating
                  ? const FCircularProgress()
                  : const Icon(FLucideIcons.rotateCcw),
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FButton(
              key: const Key('ai-save'),
              onPress: _generating ? null : _save,
              prefix: const Icon(FLucideIcons.check),
              child: const Text('Save plan'),
            ),
          ),
        ],
      ),
      Center(
        child: FButton(
          key: const Key('ai-edit-request'),
          variant: .ghost,
          onPress: () => setState(() => _preview = null),
          child: const Text('Edit request'),
        ),
      ),
    ],
  );
}
