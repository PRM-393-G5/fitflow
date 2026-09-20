import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../data/openai_service.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/meal_plan.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';

/// Suggestion-only nutrition: a daily calorie target from the user's
/// profile and goal, plus an AI-generated meal plan cached per day.
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  static const _cacheKey = 'meal_plan_v1';
  static const _logKey = 'food_log_v1';

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  final _service = const OpenAiService();
  final _prefsCtrl = TextEditingController();
  MealPlan? _plan;
  final _logged = <Meal>[];
  DateTime _logDate = DateTime.now();
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
      } catch (_) {
        // Corrupt cache — ignore, a new plan can be generated.
      }
    }
    final rawLog = AppScope.of(context).preferences
        .getString(NutritionPage._logKey);
    if (rawLog != null) {
      try {
        final json = jsonDecode(rawLog) as Map<String, dynamic>;
        final date = DateTime.parse(json['date'] as String);
        final now = DateTime.now();
        if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          _logDate = date;
          _logged.addAll([
            for (final meal in json['meals'] as List)
              Meal.fromJson(meal as Map<String, dynamic>),
          ]);
        }
      } catch (_) {
        // Corrupt log — drop it, food logs are throwaway.
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
      _showSnack(e.message);
    } on FormatException {
      _showSnack('Could not generate a plan — try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _analyzePhoto(ImageSource source) async {
    if (_analyzing) return;
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
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
      _showSnack(e.message);
    } on FormatException {
      _showSnack('Could not analyze the photo — try again.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  /// Appends [meal] to today's log and persists it (local only —
  /// food logs are throwaway data, no cloud sync).
  Future<void> _logMeal(Meal meal) {
    final now = DateTime.now();
    setState(() {
      // App left open past midnight — don't carry yesterday's meals
      // into the new day's log.
      if (_logDate.year != now.year ||
          _logDate.month != now.month ||
          _logDate.day != now.day) {
        _logged.clear();
      }
      _logDate = now;
      _logged.add(meal);
    });
    return _persistLog();
  }

  Future<void> _removeLogged(int index) {
    setState(() => _logged.removeAt(index));
    return _persistLog();
  }

  /// Shared write for all log mutations — callers are fire-and-forget,
  /// so a prefs failure is swallowed here (throwaway data).
  Future<void> _persistLog() async {
    try {
      await AppScope.of(context).preferences.setString(
        NutritionPage._logKey,
        jsonEncode({
          'date': _logDate.toIso8601String(),
          'meals': [for (final m in _logged) m.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Logs a manually typed dish (name + kcal) — the fallback when the
  /// photo path isn't available.
  Future<void> _logManually() async {
    final meal = await showFDialog<Meal>(
      context: context,
      builder: (context, style, animation) =>
          _LogMealDialog(animation: animation),
    );
    if (meal != null && mounted) await _logMeal(meal);
  }

  void _showSnack(String text) {
    if (!mounted) return;
    showFToast(context: context, title: Text(text));
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

    final eatenKcal = _logged.fold(0, (sum, m) => sum + m.kcal);
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
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Today'),
          const SizedBox(height: AppSpacing.sm),
          if (targetKcal != null || _logged.isNotEmpty) ...[
            Semantics(
              label: targetKcal == null
                  ? '$eatenKcal kilocalories eaten today'
                  : '$eatenKcal of $targetKcal kilocalories eaten today',
              child: FDeterminateProgress(
                value: targetKcal == null
                    ? 0
                    : (eatenKcal / targetKcal).clamp(0.0, 1.0),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$eatenKcal / ${targetKcal ?? '—'} kcal eaten today',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          ..._logged.indexed.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _MealCard(
                meal: entry.$2,
                onRemove: () => _removeLogged(entry.$1),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: FButton(
                  key: const Key('nutrition-photo'),
                  variant: .outline,
                  onPress: _analyzing || !OpenAiService.configured
                      ? null
                      : () => _analyzePhoto(.camera),
                  prefix: _analyzing
                      ? const FCircularProgress()
                      : const Icon(FLucideIcons.camera),
                  child: Text(_analyzing ? 'Analyzing…' : 'Take photo'),
                ),
              ),
              Expanded(
                child: FButton(
                  variant: .outline,
                  onPress: _analyzing || !OpenAiService.configured
                      ? null
                      : () => _analyzePhoto(.gallery),
                  prefix: const Icon(FLucideIcons.images),
                  child: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              key: const Key('nutrition-log-manual'),
              variant: .ghost,
              size: .sm,
              onPress: _logManually,
              prefix: const Icon(FLucideIcons.pencil),
              child: const Text('Log a meal manually'),
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
              Align(
                alignment: Alignment.centerRight,
                child: FButton(
                  key: const Key('nutrition-log-photo'),
                  variant: .secondary,
                  size: .sm,
                  onPress: () {
                    final meal = _photoMeal!;
                    _logMeal(meal).ignore();
                    setState(() {
                      _photoBytes = null;
                      _photoMeal = null;
                      _photoNote = '';
                    });
                    _showSnack('Logged to today.');
                  },
                  prefix: const Icon(FLucideIcons.check),
                  child: const Text('Log this meal'),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _photoNote.isEmpty
                    ? 'Estimated from the photo — portions are approximate.'
                    : _photoNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'AI meal plan'),
          const SizedBox(height: AppSpacing.sm),
          FTextField(
            key: const Key('nutrition-preferences'),
            control: .managed(controller: _prefsCtrl),
            label: const Text('Preferences (optional)'),
            hint: 'e.g. vegetarian, no seafood, lactose free',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Meals per day', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final (value, label) in [(3, '3 meals'), (4, '3 + snack')])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: value == 3 ? AppSpacing.sm : 0,
                    ),
                    child: FButton(
                      variant: _mealCount == value ? .primary : .outline,
                      size: .sm,
                      onPress: () => setState(() => _mealCount = value),
                      child: Text(label),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!OpenAiService.configured)
            const AppCard(
              child: Text(
                'AI suggestions need an OpenAI API key '
                '(.env file or --dart-define=OPENAI_API_KEY=…).',
              ),
            )
          else if (targetKcal != null)
            SizedBox(
              width: double.infinity,
              child: FButton(
                key: const Key('nutrition-generate'),
                onPress: _generating
                    ? null
                    : () => _generate(targetKcal, proteinG!),
                prefix: _generating
                    ? const FCircularProgress()
                    : const Icon(FLucideIcons.sparkles),
                child: Text(
                  _generating ? 'Generating…' : "Suggest today's menu",
                ),
              ),
            ),
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
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set up your body profile and log a weight first — your '
          'calorie target comes from TDEE.',
        ),
        const SizedBox(height: AppSpacing.sm),
        FButton(
          key: const Key('nutrition-open-metrics'),
          variant: .ghost,
          size: .sm,
          onPress: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BodyMetricsPage()),
          ),
          child: const Text('Open body metrics'),
        ),
      ],
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
    return AppCard(
      style: .delta(
        decoration: .boxDelta(
          color: context.theme.colors.secondary,
          border: Border.all(width: 0, color: Colors.transparent),
        ),
      ),
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
              Expanded(child: _value(context, 'TDEE', '${tdee.round()} kcal')),
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
        child: FDeterminateProgress(
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
      ...plan.meals.map(
        (meal) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _MealCard(meal: meal),
        ),
      ),
    ],
  );
}

/// Dialog owning its own controllers — disposing them in the caller
/// would race the route's exit animation (the subtree still builds the
/// TextFields while dismissing).
class _LogMealDialog extends StatefulWidget {
  const _LogMealDialog({this.animation});

  final Animation<double>? animation;

  @override
  State<_LogMealDialog> createState() => _LogMealDialogState();
}

class _LogMealDialogState extends State<_LogMealDialog> {
  final _nameCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    final kcal = int.tryParse(_kcalCtrl.text.trim());
    final valid = name.isNotEmpty && kcal != null && kcal > 0;
    return FDialog(
      style: .context(),
      animation: widget.animation,
      builder: (context, style) => AppDialogContent(
        title: 'Log a meal',
        style: style,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextField(
              control: .managed(
                controller: _nameCtrl,
                onChange: (_) => setState(() {}),
              ),
              label: const Text('What did you eat?'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FTextField(
              control: .managed(
                controller: _kcalCtrl,
                onChange: (_) => setState(() {}),
              ),
              label: const Text('Calories (kcal)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: valid
                ? () => Navigator.pop(
                    context,
                    Meal(
                      label: 'Manual entry',
                      items: [MealItem(name: name, kcal: kcal)],
                    ),
                  )
                : null,
            child: const Text('Log'),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, this.onRemove});

  final Meal meal;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
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
            if (onRemove != null)
              FButton.icon(
                variant: .ghost,
                size: .sm,
                onPress: onRemove,
                child: const Icon(FLucideIcons.x),
              ),
          ],
        ),
        const FDivider(),
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
  );
}
