import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/openai_service.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/meal_plan.dart';
import '../../metrics/presentation/body_metrics_page.dart';

/// Suggestion-only nutrition: a daily calorie target from the user's
/// profile and goal, plus an AI-generated meal plan cached per day.
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  static const _cacheKey = 'meal_plan_v1';

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  final _service = const OpenAiService();
  final _prefsCtrl = TextEditingController();
  MealPlan? _plan;
  int _mealCount = 3;
  bool _generating = false;
  bool _cacheLoaded = false;
  Uint8List? _photoBytes;
  Meal? _photoMeal;
  String _photoNote = '';
  bool _analyzing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    final raw = AppScope.of(context).preferences
        .getString(NutritionPage._cacheKey);
    if (raw != null) {
      try {
        final cached = MealPlan.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (cached.isToday) _plan = cached;
      } on FormatException {
        // Corrupt cache — ignore, a new plan can be generated.
      }
    }
  }

  @override
  void dispose() {
    _prefsCtrl.dispose();
    super.dispose();
  }

  /// TDEE from the body profile, or null when the profile is incomplete.
  double? _tdee(AppController controller) {
    final height = controller.heightCm;
    final age = controller.age;
    final weight = controller.weightEntries.isEmpty
        ? null
        : controller.weightEntries.last.weightKg;
    if (height == null || age == null || weight == null) return null;
    return BodyMetrics.tdee(
      weightKg: weight,
      heightCm: height,
      age: age,
      isMale: controller.isMale,
      activityLevel: controller.activityLevel,
    );
  }

  Future<MealPlan> _generatePlan(
    int targetKcal,
    int proteinG,
    String? goal,
  ) async {
    FormatException? parseError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final json = await _service.generateJson(
          system: AiMealPrompt.system,
          user: AiMealPrompt.user(
            targetKcal: targetKcal,
            proteinG: proteinG,
            meals: _mealCount,
            goal: goal,
            preferences: _prefsCtrl.text.trim(),
          ),
          schema: AiMealPrompt.schema,
          schemaName: 'meal_plan',
        );
        return AiMealParser.parse(json, targetKcal: targetKcal);
      } on FormatException catch (e) {
        parseError = e;
      }
    }
    throw parseError!;
  }

  Future<void> _generate(int targetKcal, int proteinG) async {
    if (_generating) return;
    final scope = AppScope.of(context);
    final goal = scope.goal;
    final preferences = scope.preferences;
    setState(() => _generating = true);
    try {
      final plan = await _generatePlan(targetKcal, proteinG, goal);
      await preferences.setString(
        NutritionPage._cacheKey,
        jsonEncode(plan.toJson()),
      );
      if (mounted) setState(() => _plan = plan);
    } on OpenAiException catch (e) {
      _showError(e.message);
    } on FormatException {
      _showError('Could not generate a plan — try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _analyzePhoto() async {
    if (_analyzing) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    setState(() {
      _analyzing = true;
      _photoBytes = bytes;
      _photoMeal = null;
      _photoNote = '';
    });
    try {
      final json = await _service.generateJson(
        system: AiFoodPhotoPrompt.system,
        user: AiFoodPhotoPrompt.user,
        schema: AiFoodPhotoPrompt.schema,
        schemaName: 'food_photo',
        model: OpenAiService.visionModel,
        temperature: null,
        reasoningEffort: 'low',
        imageBytes: bytes,
      );
      final parsed = AiMealParser.parsePhoto(json);
      if (mounted) {
        setState(() {
          _photoMeal = parsed.meal;
          _photoNote = parsed.note;
        });
      }
    } on OpenAiException catch (e) {
      _showError(e.message);
    } on FormatException {
      _showError('Could not analyze the photo — try again.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final tdee = _tdee(controller);
    final goal = controller.goal;
    final weight = controller.weightEntries.isEmpty
        ? null
        : controller.weightEntries.last.weightKg;
    final targetKcal = tdee == null
        ? null
        : NutritionTargets.targetKcal(tdee: tdee, goal: goal);
    final proteinG = weight == null
        ? null
        : NutritionTargets.proteinG(weightKg: weight, goal: goal);

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrition',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Eat for your goal — AI suggests your daily menu.'),
          const SizedBox(height: AppSpacing.md),
          if (tdee == null)
            const _ProfileNeededCard()
          else
            _TargetCard(
              tdee: tdee,
              goal: goal,
              targetKcal: targetKcal!,
              proteinG: proteinG!,
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('nutrition-preferences'),
            controller: _prefsCtrl,
            decoration: const InputDecoration(
              labelText: 'Preferences (optional)',
              hintText: 'e.g. vegetarian, no seafood, lactose free',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3 meals')),
              ButtonSegment(value: 4, label: Text('3 + snack')),
            ],
            selected: {_mealCount},
            onSelectionChanged: (value) =>
                setState(() => _mealCount = value.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!OpenAiService.configured)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'AI suggestions need an OpenAI API key configured at '
                  'build time (--dart-define=OPENAI_API_KEY=…).',
                ),
              ),
            )
          else if (targetKcal != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('nutrition-generate'),
                onPressed: _generating
                    ? null
                    : () => _generate(targetKcal, proteinG!),
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _generating ? 'Generating…' : "Suggest today's menu",
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('nutrition-photo'),
              onPressed: _analyzing ? null : _analyzePhoto,
              icon: _analyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined),
              label: Text(
                _analyzing ? 'Analyzing photo…' : 'Analyze a food photo',
              ),
            ),
          ),
          if (_photoBytes != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _photoBytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            if (_photoMeal != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _MealCard(meal: _photoMeal!),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _photoNote.isEmpty
                    ? 'Estimated from the photo — portions are approximate.'
                    : _photoNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          if (_plan != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _PlanView(plan: _plan!),
          ],
        ],
      ),
    );
  }
}

class _ProfileNeededCard extends StatelessWidget {
  const _ProfileNeededCard();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set up your body profile and log a weight first — your '
            'calorie target comes from TDEE.',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            key: const Key('nutrition-open-metrics'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BodyMetricsPage()),
            ),
            child: const Text('Open body metrics'),
          ),
        ],
      ),
    ),
  );
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.tdee,
    required this.goal,
    required this.targetKcal,
    required this.proteinG,
  });

  final double tdee;
  final String? goal;
  final int targetKcal;
  final int proteinG;

  @override
  Widget build(BuildContext context) {
    final fat = NutritionTargets.fatG(targetKcal);
    final carbs = NutritionTargets.carbsG(
      targetKcal: targetKcal,
      proteinG: proteinG,
    );
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily target${goal != null ? ' — $goal' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _value(context, 'TDEE', '${tdee.round()} kcal'),
                ),
                Expanded(child: _value(context, 'Target', '$targetKcal kcal')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'P ${proteinG}g · C ${carbs}g · F ${fat}g',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _value(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _PlanView extends StatelessWidget {
  const _PlanView({required this.plan});

  final MealPlan plan;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: '${plan.totalKcal} of ${plan.targetKcal} kilocalories',
        child: LinearProgressIndicator(
          value: (plan.totalKcal / plan.targetKcal).clamp(0.0, 1.0),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text('${plan.totalKcal} / ${plan.targetKcal} kcal suggested'),
      if (plan.note.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(plan.note, style: Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height: AppSpacing.md),
      ...plan.meals.map((meal) => _MealCard(meal: meal)),
    ],
  );
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${meal.kcal} kcal'),
            ],
          ),
          const Divider(),
          ...meal.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name),
                        Text(
                          'P ${item.proteinG.round()}g · '
                          'C ${item.carbsG.round()}g · '
                          'F ${item.fatG.round()}g',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text('${item.kcal} kcal'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
