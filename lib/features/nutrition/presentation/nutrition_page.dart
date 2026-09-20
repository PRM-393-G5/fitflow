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
/// profile and goal, an AI-generated meal plan cached per day, and a food
/// log kept for the last [FoodLog.keepDays] days.
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  static const _cacheKey = 'meal_plan_v1';
  static const _logKey = 'food_log_v1';

  /// Same values as onboarding (workout categories).
  static const goals = [
    (label: 'Build muscle', value: 'Strength'),
    (label: 'Lose fat', value: 'Cardio'),
    (label: 'Stay mobile', value: 'Mobility'),
  ];

  static String goalLabel(String goal) => goals
      .firstWhere(
        (option) => option.value == goal,
        orElse: () => (label: goal, value: goal),
      )
      .label;

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with WidgetsBindingObserver {
  final _service = const OpenAiService();
  final _prefsCtrl = TextEditingController();
  MealPlanCache _cache = const MealPlanCache();
  FoodLog _log = FoodLog();

  /// The calendar day the page considers "today" — re-checked on build
  /// and on resume so a page left open past midnight rolls over.
  DateTime _today = _dayOf(DateTime.now());

  /// The day whose food log is shown (today or one of the kept days).
  DateTime _viewDay = _dayOf(DateTime.now());

  /// The controller's [AppController.dataEpoch] the cached data belongs
  /// to; a change means the user's data was wiped or replaced.
  int? _epoch;
  bool _generating = false;
  Uint8List? _photoBytes;
  Meal? _photoMeal;
  String _photoNote = '';
  bool _analyzing = false;
  bool _photoFailed = false;

  static DateTime _dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (_epoch == controller.dataEpoch) return;
    _epoch = controller.dataEpoch;
    _reload(controller);
  }

  /// (Re)reads the plan cache and food log — on first build and whenever
  /// the account's data changes, so a previous user's data never shows.
  void _reload(AppController controller) {
    final preferences = controller.preferences;
    _cache = MealPlanCache.decode(
      preferences.getString(NutritionPage._cacheKey),
    );
    _prefsCtrl.text = _cache.preferences;
    _log = FoodLog.decode(preferences.getString(NutritionPage._logKey))
      ..prune(DateTime.now());
    _today = _dayOf(DateTime.now());
    _viewDay = _today;
    _photoBytes = null;
    _photoMeal = null;
    _photoNote = '';
    _photoFailed = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _rollOver()) setState(() {});
  }

  /// Moves [_today] to the current day; returns true when it changed.
  bool _rollOver() {
    final today = _dayOf(DateTime.now());
    if (today == _today) return false;
    if (_viewDay == _today) _viewDay = today;
    _today = today;
    _log.prune(today);
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            meals: _cache.mealCount,
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
    if (_cache.plan?.isOn(_today) ?? false) {
      final replace = await _confirm(
        title: "Replace today's menu?",
        message: 'The current suggestions will be replaced by a new plan.',
        action: 'Regenerate',
      );
      if (!replace || !mounted) return;
    }
    final controller = AppScope.of(context);
    final goal = controller.goal;
    // Compare against the controller, not [_epoch]: the page only catches
    // up on its next rebuild, which may come after the response.
    final epoch = controller.dataEpoch;
    setState(() => _generating = true);
    try {
      final plan = await _generatePlan(targetKcal, proteinG, goal);
      // The account changed mid-request — don't save into the new one.
      if (!mounted || epoch != controller.dataEpoch) return;
      setState(() => _cache = _cache.withPlan(plan));
      await _saveCache();
    } on OpenAiException catch (e) {
      _showSnack(e.message);
    } on FormatException {
      _showSnack('Could not generate a plan — try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveCache() async {
    try {
      await AppScope.of(context).preferences
          .setString(NutritionPage._cacheKey, jsonEncode(_cache.toJson()));
    } catch (_) {}
  }

  void _setMealCount(int count) {
    setState(() => _cache = _cache.copyWith(mealCount: count));
    _saveCache().ignore();
  }

  void _setPreferences(String text) {
    _cache = _cache.copyWith(preferences: text.trim());
    _saveCache().ignore();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_analyzing) return;
    // Don't silently drop an analyzed result that was never logged.
    final pending = _photoMeal;
    if (pending != null) {
      final choice = await showAppDialog<String>(
        context: context,
        title: 'Log the previous photo?',
        body: const Text(
          'Its analysis has not been logged yet. A new photo replaces it.',
        ),
        actions: [
          FButton(
            onPress: () => Navigator.pop(context, 'log'),
            child: const Text('Log it, then continue'),
          ),
          FButton(
            variant: .outline,
            onPress: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard it'),
          ),
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      );
      if (choice == null || !mounted) return;
      if (choice == 'log') await _logMeal(pending);
      if (!mounted) return;
      _clearPhoto();
    }
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    await _analyze(bytes);
  }

  Future<void> _analyze(Uint8List bytes) async {
    // Captured from the controller for the same reason as in [_generate].
    final controller = AppScope.of(context);
    final epoch = controller.dataEpoch;
    setState(() {
      _analyzing = true;
      _photoFailed = false;
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
      if (mounted && epoch == controller.dataEpoch) {
        setState(() {
          _photoMeal = parsed.meal;
          _photoNote = parsed.note;
        });
      }
    } on OpenAiException catch (e) {
      if (mounted) setState(() => _photoFailed = true);
      _showSnack(e.message);
    } on FormatException {
      if (mounted) setState(() => _photoFailed = true);
      _showSnack('Could not analyze the photo — try again.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _clearPhoto() => setState(() {
    _photoBytes = null;
    _photoMeal = null;
    _photoNote = '';
    _photoFailed = false;
  });

  /// Adds [meal] to [day]'s log (the viewed day by default) and persists
  /// it (local only — food logs are not synced).
  Future<void> _logMeal(Meal meal, {DateTime? day}) {
    _rollOver();
    setState(() => _log.add(day ?? _viewDay, meal));
    return _persistLog();
  }

  Future<void> _removeLogged(int index) {
    setState(() => _log.removeAt(_viewDay, index));
    return _persistLog();
  }

  Future<void> _editLogged(int index, Meal meal) async {
    final day = _viewDay;
    final edited = await showFDialog<Meal>(
      context: context,
      builder: (context, style, animation) =>
          _EditMealDialog(meal: meal, animation: animation),
    );
    if (edited == null || !mounted) return;
    setState(() => _log.replace(day, index, edited));
    await _persistLog();
  }

  /// Shared write for all log mutations — callers are fire-and-forget,
  /// so a prefs failure is swallowed here.
  Future<void> _persistLog() async {
    _log.prune(_today);
    try {
      await AppScope.of(context).preferences
          .setString(NutritionPage._logKey, jsonEncode(_log.toJson()));
    } catch (_) {}
  }

  /// Logs a manually typed dish (name, kcal, optional macros) — the
  /// fallback when the photo path isn't available.
  Future<void> _logManually() async {
    final meal = await showFDialog<Meal>(
      context: context,
      builder: (context, style, animation) =>
          _LogMealDialog(animation: animation),
    );
    if (meal != null && mounted) await _logMeal(meal);
  }

  Future<void> _changeGoal(AppController controller) async {
    final picked = await showAppDialog<String>(
      context: context,
      title: 'Your goal',
      body: const Text('Your calorie and protein targets follow your goal.'),
      actions: [
        for (final option in NutritionPage.goals)
          FButton(
            variant: controller.goal == option.value ? .primary : .outline,
            onPress: () => Navigator.pop(context, option.value),
            child: Text(option.label),
          ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
    if (picked == null || picked == controller.goal) return;
    await controller.setGoal(goal: picked, level: controller.level);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showAppDialog<bool>(
        context: context,
        title: title,
        body: Text(message),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ) ??
      false;

  void _showSnack(String text) {
    if (!mounted) return;
    showFToast(context: context, title: Text(text));
  }

  String _dayLabel(DateTime day) {
    if (day == _today) return 'Today';
    if (day == DateTime(_today.year, _today.month, _today.day - 1)) {
      return 'Yesterday';
    }
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[day.weekday - 1]} '
        '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}';
  }

  void _shiftDay(int days) => setState(
    () =>
        _viewDay = DateTime(_viewDay.year, _viewDay.month, _viewDay.day + days),
  );

  @override
  Widget build(BuildContext context) {
    _rollOver();
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
    final plan = _cache.plan != null && _cache.plan!.isOn(_today)
        ? _cache.plan
        : null;
    final targetChanged =
        plan != null && targetKcal != null && plan.targetKcal != targetKcal;

    final isToday = _viewDay == _today;
    final oldest = DateTime(
      _today.year,
      _today.month,
      _today.day - (FoodLog.keepDays - 1),
    );
    final logged = _log.mealsOn(_viewDay);
    final eaten = FoodLog.totals(logged);
    final dayText = isToday
        ? 'today'
        : 'on ${_dayLabel(_viewDay).toLowerCase()}';
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodySmall?.copyWith(
      color: context.theme.colors.mutedForeground,
    );

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrition',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
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
              onChangeGoal: () => _changeGoal(controller),
            ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: _dayLabel(_viewDay),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FButton.icon(
                  key: const Key('nutrition-prev-day'),
                  variant: .ghost,
                  size: .sm,
                  onPress: _viewDay.isAfter(oldest)
                      ? () => _shiftDay(-1)
                      : null,
                  child: const Icon(FLucideIcons.chevronLeft),
                ),
                FButton.icon(
                  key: const Key('nutrition-next-day'),
                  variant: .ghost,
                  size: .sm,
                  onPress: isToday ? null : () => _shiftDay(1),
                  child: const Icon(FLucideIcons.chevronRight),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (targetKcal != null || logged.isNotEmpty) ...[
            Semantics(
              label: targetKcal == null
                  ? '${eaten.kcal} kilocalories eaten $dayText'
                  : '${eaten.kcal} of $targetKcal kilocalories eaten $dayText',
              child: FDeterminateProgress(
                value: targetKcal == null || targetKcal <= 0
                    ? 0
                    : (eaten.kcal / targetKcal).clamp(0.0, 1.0),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${eaten.kcal} / ${targetKcal ?? '—'} kcal eaten $dayText',
              style: textTheme.bodySmall,
            ),
            Text(
              _macroLine(eaten, targetKcal, proteinG),
              key: const Key('nutrition-macros'),
              style: mutedStyle,
            ),
          ],
          if (logged.isEmpty && !isToday) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Nothing logged this day.'),
          ],
          ...logged.indexed.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _MealCard(
                meal: entry.$2,
                onEdit: () => _editLogged(entry.$1, entry.$2),
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
                      : () => _pickPhoto(.camera),
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
                      : () => _pickPhoto(.gallery),
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
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _photoBytes!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (!_analyzing)
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: FButton.icon(
                      key: const Key('nutrition-clear-photo'),
                      variant: .secondary,
                      size: .sm,
                      onPress: _clearPhoto,
                      child: const Icon(FLucideIcons.x),
                    ),
                  ),
              ],
            ),
            if (_photoFailed && !_analyzing) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Expanded(child: Text('Could not analyze this photo.')),
                  FButton(
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => _analyze(_photoBytes!),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FButton(
                    variant: .ghost,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: _clearPhoto,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ],
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
                    _clearPhoto();
                    _showSnack(
                      'Logged to ${_dayLabel(_viewDay).toLowerCase()}.',
                    );
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
                style: textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'AI meal plan'),
          const SizedBox(height: AppSpacing.sm),
          FTextField(
            key: const Key('nutrition-preferences'),
            control: .managed(
              controller: _prefsCtrl,
              onChange: (value) => _setPreferences(value.text),
            ),
            label: const Text('Preferences (optional)'),
            hint: 'e.g. vegetarian, no seafood, lactose free',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Meals per day', style: textTheme.labelMedium),
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
                      variant: _cache.mealCount == value ? .primary : .outline,
                      size: .sm,
                      onPress: () => _setMealCount(value),
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
                  _generating
                      ? 'Generating…'
                      : plan == null
                      ? "Suggest today's menu"
                      : "Regenerate today's menu",
                ),
              ),
            ),
          if (plan != null) ...[
            if (targetChanged) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('nutrition-target-changed'),
                child: Row(
                  children: [
                    const Icon(FLucideIcons.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Target changed — regenerate. This menu was planned '
                        'for ${plan.targetKcal} kcal; your target is now '
                        '$targetKcal kcal.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _PlanView(
              plan: plan,
              onLog: (meal) {
                _logMeal(meal, day: _today).ignore();
                _showSnack('${meal.label} logged to today.');
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _macroLine(
    ({int kcal, double proteinG, double carbsG, double fatG}) eaten,
    int? targetKcal,
    int? proteinG,
  ) {
    if (targetKcal == null || proteinG == null) {
      return 'P ${eaten.proteinG.round()}g · C ${eaten.carbsG.round()}g · '
          'F ${eaten.fatG.round()}g';
    }
    final fat = NutritionTargets.fatG(targetKcal);
    final carbs = NutritionTargets.carbsG(
      targetKcal: targetKcal,
      proteinG: proteinG,
    );
    return 'P ${eaten.proteinG.round()}/${proteinG}g · '
        'C ${eaten.carbsG.round()}/${carbs}g · '
        'F ${eaten.fatG.round()}/${fat}g';
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
    required this.onChangeGoal,
  });

  final double tdee;
  final String? goal;
  final int targetKcal;
  final int proteinG;
  final VoidCallback onChangeGoal;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daily target'
                  '${goal != null ? ' — ${NutritionPage.goalLabel(goal!)}' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FButton(
                key: const Key('nutrition-change-goal'),
                variant: .ghost,
                size: .sm,
                mainAxisSize: .min,
                onPress: onChangeGoal,
                child: Text(goal == null ? 'Set goal' : 'Change goal'),
              ),
            ],
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
  const _PlanView({required this.plan, required this.onLog});

  final MealPlan plan;

  /// One-tap logging of a suggested meal.
  final ValueChanged<Meal> onLog;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: '${plan.totalKcal} of ${plan.targetKcal} kilocalories',
        child: FDeterminateProgress(
          // 0 / 0 is NaN, which clamp passes through.
          value: plan.targetKcal <= 0
              ? 0
              : (plan.totalKcal / plan.targetKcal).clamp(0.0, 1.0),
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
          child: _MealCard(meal: meal, onLog: () => onLog(meal)),
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
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      _nameCtrl,
      _kcalCtrl,
      _proteinCtrl,
      _carbsCtrl,
      _fatCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Optional grams: empty → 0, invalid → null.
  static double? _grams(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final value = BodyMetrics.parseDecimal(text);
    return value == null || value < 0 || value > 1000 ? null : value;
  }

  Widget _macroField(TextEditingController controller, String label) =>
      Expanded(
        child: FTextField(
          control: .managed(
            controller: controller,
            onChange: (_) => setState(() {}),
          ),
          label: Text(label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    final kcal = int.tryParse(_kcalCtrl.text.trim());
    final protein = _grams(_proteinCtrl);
    final carbs = _grams(_carbsCtrl);
    final fat = _grams(_fatCtrl);
    final valid =
        name.isNotEmpty &&
        kcal != null &&
        kcal > 0 &&
        kcal <= 10000 &&
        protein != null &&
        carbs != null &&
        fat != null;
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
            const SizedBox(height: AppSpacing.sm),
            Row(
              spacing: AppSpacing.sm,
              children: [
                _macroField(_proteinCtrl, 'Protein g'),
                _macroField(_carbsCtrl, 'Carbs g'),
                _macroField(_fatCtrl, 'Fat g'),
              ],
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
                      items: [
                        MealItem(
                          name: name,
                          kcal: kcal,
                          proteinG: protein,
                          carbsG: carbs,
                          fatG: fat,
                        ),
                      ],
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

/// Edits a logged meal's size: pick a portion multiple or type the kcal;
/// macros scale along. Pops the resized [Meal].
class _EditMealDialog extends StatefulWidget {
  const _EditMealDialog({required this.meal, this.animation});

  final Meal meal;
  final Animation<double>? animation;

  @override
  State<_EditMealDialog> createState() => _EditMealDialogState();
}

class _EditMealDialogState extends State<_EditMealDialog> {
  late final _kcalCtrl = TextEditingController(text: '${widget.meal.kcal}');

  static const _portions = [
    (0.5, '½×'),
    (1.0, '1×'),
    (1.5, '1½×'),
    (2.0, '2×'),
  ];

  @override
  void dispose() {
    _kcalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kcal = int.tryParse(_kcalCtrl.text.trim());
    final valid = kcal != null && kcal > 0 && kcal <= 10000;
    return FDialog(
      style: .context(),
      animation: widget.animation,
      builder: (context, style) => AppDialogContent(
        title: 'Edit ${widget.meal.label.toLowerCase()}',
        style: style,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.meal.items.map((item) => item.name).join(', ')),
            const SizedBox(height: AppSpacing.sm),
            Text('Portion', style: style.bodyTextStyle),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (factor, label) in _portions)
                  FButton(
                    variant: kcal == (widget.meal.kcal * factor).round()
                        ? .primary
                        : .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => setState(
                      () => _kcalCtrl.text =
                          '${(widget.meal.kcal * factor).round()}',
                    ),
                    child: Text(label),
                  ),
              ],
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
                ? () => Navigator.pop(context, widget.meal.withKcal(kcal))
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, this.onEdit, this.onRemove, this.onLog});

  final Meal meal;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback? onLog;

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
            if (onLog != null)
              Semantics(
                label: 'Log ${meal.label}',
                child: FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: onLog,
                  child: const Icon(FLucideIcons.plus),
                ),
              ),
            if (onEdit != null)
              Semantics(
                label: 'Edit ${meal.label}',
                child: FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: onEdit,
                  child: const Icon(FLucideIcons.pencil),
                ),
              ),
            if (onRemove != null)
              Semantics(
                label: 'Remove ${meal.label}',
                child: FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: onRemove,
                  child: const Icon(FLucideIcons.x),
                ),
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
