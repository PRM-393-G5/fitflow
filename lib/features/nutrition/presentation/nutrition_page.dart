import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../data/openai_service.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/meal_plan.dart';
import '../../../domain/training_options.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import 'log_meal_page.dart';
import 'meal_type_picker.dart';

/// Suggestion-only nutrition: a daily calorie target from the user's
/// profile and goal, an AI-generated meal plan cached per day, and the
/// food log ([AppController.foodLog], synced to the backend).
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  static const _cacheKey = 'meal_plan_v1';

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with WidgetsBindingObserver {
  final _service = const OpenAiService();
  final _prefsCtrl = TextEditingController();
  MealPlanCache _cache = const MealPlanCache();

  /// The calendar day the page considers "today" — re-checked on build
  /// and on resume so a page left open past midnight rolls over.
  DateTime _today = _dayOf(DateTime.now());

  /// The day whose food log is shown (today or one of the kept days).
  DateTime _viewDay = _dayOf(DateTime.now());

  /// The controller's [AppController.dataEpoch] the cached data belongs
  /// to; a change means the user's data was wiped or replaced.
  int? _epoch;
  bool _generating = false;
  bool _showPlanOptions = false;
  Uint8List? _photoBytes;

  /// Meal slot the analyzed photo will be logged to.
  String _photoType = defaultMealType(DateTime.now());
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

  /// (Re)reads the plan cache and resets the view — on first build and whenever
  /// the account's data changes, so a previous user's data never shows.
  void _reload(AppController controller) {
    final preferences = controller.preferences;
    _cache = MealPlanCache.decode(
      preferences.getString(NutritionPage._cacheKey),
    );
    _prefsCtrl.text = _cache.preferences;
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

  /// Moves [_today] to the current day; returns true when it changed. A
  /// viewed day that fell out of the kept window moves to today.
  bool _rollOver() {
    final today = _dayOf(DateTime.now());
    if (today == _today) return false;
    final oldest = FoodLog.oldestKeptDay(today);
    if (_viewDay == _today || _viewDay.isBefore(oldest)) _viewDay = today;
    _today = today;
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefsCtrl.dispose();
    super.dispose();
  }

  /// TDEE and today's targets from the body profile and latest weight —
  /// or, when there are none, why ([_NoTargets]). The one place that
  /// decides it; everything on the page reads [missing].
  ({double? tdee, DailyTargets? targets, _NoTargets? missing}) _targets(
    AppController controller,
  ) {
    final height = controller.heightCm;
    final age = controller.age;
    final weight = controller.weightEntries.isEmpty
        ? null
        : controller.weightEntries.last.weightKg;
    const minor = (tdee: null, targets: null, missing: _NoTargets.minor);
    // A known under-18 age needs no profile check: there are no targets.
    if (age != null && !BodyMetrics.adultFormulasApply(age)) return minor;
    if (height == null || age == null || weight == null) {
      return (tdee: null, targets: null, missing: _NoTargets.profile);
    }
    final tdee = BodyMetrics.tdee(
      weightKg: weight,
      heightCm: height,
      age: age,
      isMale: controller.isMale,
      activityLevel: controller.activityLevel,
    );
    final targets = NutritionTargets.daily(
      tdee: tdee,
      goal: controller.goal,
      weightKg: weight,
      heightCm: height,
      age: age,
      isMale: controller.isMale,
    );
    return (tdee: tdee, targets: targets, missing: null);
  }

  Future<MealPlan> _generatePlan(DailyTargets targets, String? goal) async {
    final targetKcal = targets.kcal;
    FormatException? parseError;
    String? retryNote;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final json = await _service.generateJson(
          system: AiMealPrompt.system,
          user: AiMealPrompt.user(
            targets: targets,
            meals: _cache.mealCount,
            goal: goal,
            preferences: _prefsCtrl.text.trim(),
            retryNote: retryNote,
          ),
          schema: AiMealPrompt.schema,
          schemaName: 'meal_plan',
        );
        // A menu a little out of range is scaled into it; further off is
        // rejected and retried, telling the model why.
        return AiMealParser.parse(
          json,
          targetKcal: targetKcal,
          minKcal: targets.minMenuKcal,
          maxKcal: targets.maxMenuKcal,
        ).forTargets(targets, goal);
      } on FormatException catch (e) {
        parseError = e;
        retryNote =
            'Your previous menu was rejected (${e.message}). The day must '
            'total about $targetKcal kcal.';
      }
    }
    throw parseError!;
  }

  Future<void> _generate({required bool replacing}) async {
    if (_generating) return;
    if (replacing) {
      final replace = await _confirm(
        title: "Replace today's menu?",
        message: 'The current suggestions will be replaced by a new plan.',
        action: 'Regenerate',
      );
      if (!replace || !mounted) return;
    }
    final controller = AppScope.of(context);
    // Read after the dialog, together, so a sync while it was open can't
    // pair stale targets with a new goal (or save an outdated menu).
    final targets = _targets(controller).targets;
    final goal = controller.goal;
    if (targets == null) {
      _showSnack('Your profile changed — check it and try again.');
      return;
    }
    // Compare against the controller, not [_epoch]: the page only catches
    // up on its next rebuild, which may come after the response.
    final epoch = controller.dataEpoch;
    setState(() => _generating = true);
    try {
      final plan = await _generatePlan(targets, goal);
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

  /// Picks a dish photo for AI analysis; [type] presets the meal slot it
  /// will be logged to (default: by time of day).
  Future<void> _pickPhoto(ImageSource source, {String? type}) async {
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
      if (choice == 'log') await _logMeal(_typed(pending, _photoType));
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
    _photoType = type ?? defaultMealType(DateTime.now());
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

  /// Adds [meal] to [day]'s log (the viewed day by default).
  Future<void> _logMeal(Meal meal, {DateTime? day}) {
    _rollOver();
    return AppScope.of(context).logMeal(day ?? _viewDay, meal);
  }

  Future<void> _removeLogged(FoodEntry entry) =>
      AppScope.of(context).removeMeal(entry.id);

  Future<void> _editLogged(FoodEntry entry) async {
    final edited = await showFDialog<Meal>(
      context: context,
      builder: (context, style, animation) =>
          _EditMealDialog(meal: entry.meal, animation: animation),
    );
    if (edited == null || !mounted) return;
    await AppScope.of(context).replaceMeal(entry.id, edited);
  }

  /// Logs a manually typed dish (name, kcal, optional macros) — the
  /// fallback when the photo path isn't available.
  /// The slot's "+": photo, gallery or manual entry, logged into [type].
  Future<void> _addToSlot(String type) async {
    final ai = OpenAiService.configured && !_analyzing;
    final choice = await showAppDialog<String>(
      context: context,
      title: 'Add to $type',
      actions: [
        FButton(
          key: const Key('slot-add-photo'),
          variant: .outline,
          prefix: const Icon(FLucideIcons.camera),
          onPress: ai ? () => Navigator.pop(context, 'camera') : null,
          child: const Text('Take a photo'),
        ),
        FButton(
          key: const Key('slot-add-gallery'),
          variant: .outline,
          prefix: const Icon(FLucideIcons.images),
          onPress: ai ? () => Navigator.pop(context, 'gallery') : null,
          child: const Text('Choose from gallery'),
        ),
        FButton(
          key: const Key('slot-add-manual'),
          variant: .outline,
          prefix: const Icon(FLucideIcons.pencil),
          onPress: () => Navigator.pop(context, 'manual'),
          child: const Text('Enter manually'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'camera':
        await _pickPhoto(.camera, type: type);
      case 'gallery':
        await _pickPhoto(.gallery, type: type);
      case 'manual':
        await _logManually(type: type);
    }
  }

  Future<void> _logManually({String? type}) async {
    final recent = LogMealPage.recentItems(AppScope.of(context).foodLog);
    final meal = await Navigator.of(context).push<Meal>(
      MaterialPageRoute(
        builder: (_) => LogMealPage(
          type: type ?? defaultMealType(DateTime.now()),
          recent: recent,
        ),
      ),
    );
    if (meal != null && mounted) await _logMeal(meal);
  }

  Future<void> _changeGoal(
    AppController controller,
    _NoTargets? missing,
  ) async {
    final picked = await showAppDialog<String>(
      context: context,
      title: 'Your goal',
      body: Text(
        missing == _NoTargets.minor
            ? 'Your goal picks your suggested workouts. Calorie targets are '
                  'for adults.'
            : 'Your calorie and protein targets follow your goal.',
      ),
      actions: [
        for (final option in trainingGoals)
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
    return '${weekdayNames[day.weekday - 1]} '
        '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}';
  }

  int _kcalOn(DateTime day) =>
      FoodLog.totals(AppScope.of(context).foodLog.mealsOn(day)).kcal;

  Future<void> _openCalendar(DateTime oldest) async {
    final picked = await showFDialog<DateTime>(
      context: context,
      builder: (context, style, animation) => _MonthCalendarDialog(
        first: oldest,
        last: _today,
        selected: _viewDay,
        kcalOf: _kcalOn,
        animation: animation,
      ),
    );
    if (picked != null && mounted) setState(() => _viewDay = picked);
  }

  @override
  Widget build(BuildContext context) {
    _rollOver();
    final controller = AppScope.of(context);
    final (:tdee, :targets, :missing) = _targets(controller);
    final goal = controller.goal;
    final targetKcal = targets?.kcal;
    // No menus under 18 — not even one cached before the age changed.
    final plan =
        missing != _NoTargets.minor &&
            _cache.plan != null &&
            _cache.plan!.isOn(_today)
        ? _cache.plan
        : null;
    // A menu now under the safe minimum (e.g. a deficit a safety rule has
    // since removed) isn't shown or loggable, and says so; other changes
    // only show the banner.
    final planHidden =
        plan != null && targets != null && plan.unsafeFor(targets);
    final targetChanged =
        plan != null &&
        targets != null &&
        !planHidden &&
        plan.outdatedFor(targets, goal);

    final isToday = _viewDay == _today;
    final oldest = FoodLog.oldestKeptDay(_today);
    final logged = controller.foodLog.mealsOn(_viewDay);
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
          _DayStrip(
            days: [
              for (var i = 0; i < FoodLog.keepDays; i++)
                DateTime(oldest.year, oldest.month, oldest.day + i),
            ],
            selected: _viewDay,
            kcalOf: _kcalOn,
            onSelect: (day) => setState(() => _viewDay = day),
            onOpenCalendar: () => _openCalendar(oldest),
          ),
          const SizedBox(height: AppSpacing.md),
          if (missing != null) ...[
            _NoTargetsCard(missing),
            const SizedBox(height: AppSpacing.md),
          ],
          _SummaryCard(
            eaten: eaten,
            dayText: dayText,
            tdee: tdee,
            // Targets come from today's weight and goal; past days are
            // shown without them rather than judged against today's.
            targets: isToday ? targets : null,
            missing: missing,
            goal: goal,
            onChangeGoal: () => _changeGoal(controller, missing),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Meals',
            action: logged.isEmpty
                ? null
                : Text('${logged.length} logged', style: mutedStyle),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: _AddButton(
                  key: const Key('nutrition-photo'),
                  icon: _analyzing
                      ? const FCircularProgress()
                      : const Icon(FLucideIcons.camera),
                  label: _analyzing ? 'Analyzing…' : 'Photo',
                  onPress: _analyzing || !OpenAiService.configured
                      ? null
                      : () => _pickPhoto(.camera),
                ),
              ),
              Expanded(
                child: _AddButton(
                  icon: const Icon(FLucideIcons.images),
                  label: 'Gallery',
                  onPress: _analyzing || !OpenAiService.configured
                      ? null
                      : () => _pickPhoto(.gallery),
                ),
              ),
              Expanded(
                child: _AddButton(
                  key: const Key('nutrition-log-manual'),
                  icon: const Icon(FLucideIcons.pencil),
                  label: 'Manual',
                  onPress: () => _logManually(),
                ),
              ),
            ],
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
              const SizedBox(height: AppSpacing.xs),
              Text(
                _photoNote.isEmpty
                    ? 'Estimated from the photo — portions are approximate.'
                    : _photoNote,
                style: mutedStyle,
              ),
              const SizedBox(height: AppSpacing.md),
              MealTypePicker(
                selected: _photoType,
                onChanged: (type) => setState(() => _photoType = type),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FButton(
                  key: const Key('nutrition-log-photo'),
                  onPress: () {
                    final type = _photoType;
                    _logMeal(_typed(_photoMeal!, type)).ignore();
                    _clearPhoto();
                    _showSnack(
                      'Logged to ${type.toLowerCase()} · '
                      '${_dayLabel(_viewDay).toLowerCase()}.',
                    );
                  },
                  prefix: const Icon(FLucideIcons.check),
                  child: const Text('Log this meal'),
                ),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          if (logged.isEmpty && !isToday)
            const _EmptyDay()
          else
            for (final (type, entries) in _slots(
              controller.foodLog.entriesOn(_viewDay),
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _MealSlotCard(
                  type: type,
                  entries: entries,
                  onAdd: type == otherMealType ? null : () => _addToSlot(type),
                  onMore: _mealActions,
                ),
              ),
          if (isToday) ...[
            const SizedBox(height: AppSpacing.lg),
            _AiPlanCard(
              configured: OpenAiService.configured,
              targetKcal: targetKcal,
              missing: missing,
              hasPlan: plan != null && !planHidden,
              generating: _generating,
              showOptions: _showPlanOptions,
              onToggleOptions: () =>
                  setState(() => _showPlanOptions = !_showPlanOptions),
              optionsSummary: _optionsSummary(),
              options: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FTextField(
                    key: const Key('nutrition-preferences'),
                    control: .managed(
                      controller: _prefsCtrl,
                      onChange: (value) => _setPreferences(value.text),
                    ),
                    label: const Text('Preferences'),
                    hint: 'e.g. vegetarian, no seafood, lactose free',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Meals per day', style: textTheme.labelMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final (value, label) in [
                        (3, '3 meals'),
                        (4, '3 + snack'),
                      ])
                        Expanded(
                          child: FButton(
                            variant: _cache.mealCount == value
                                ? .primary
                                : .outline,
                            size: .sm,
                            onPress: () => _setMealCount(value),
                            child: Text(label),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              onGenerate: targets == null
                  ? null
                  : () => _generate(replacing: plan != null && !planHidden),
            ),
            if (planHidden) ...[
              const SizedBox(height: AppSpacing.md),
              const AppCard(
                key: Key('nutrition-menu-hidden'),
                child: Row(
                  children: [
                    Icon(FLucideIcons.shieldAlert),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        "Today's menu is now below your safe minimum, so "
                        "it is hidden — generate a new one.",
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (plan != null && !planHidden) ...[
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
                          plan.targetKcal != targetKcal
                              ? 'Target changed — regenerate. Today\'s menu '
                                    'was planned for ${plan.targetKcal} kcal; '
                                    'your target is now $targetKcal kcal.'
                              : 'Your goal or protein target changed since '
                                    'today\'s menu was planned — regenerate.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _PlanView(
                plan: plan,
                onLog: (meal) {
                  _logMeal(meal, day: _today).ignore();
                  _showSnack('${meal.label} logged to today.');
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  static Meal _typed(Meal meal, String type) =>
      Meal(label: type, items: meal.items);

  /// The day's entries bucketed into the fixed slots (plus "Other" for
  /// legacy labels).
  static List<(String, List<FoodEntry>)> _slots(List<FoodEntry> logged) {
    final buckets = {for (final type in mealTypes) type: <FoodEntry>[]};
    for (final entry in logged) {
      buckets.putIfAbsent(mealTypeOf(entry.meal), () => []).add(entry);
    }
    return [
      for (final MapEntry(:key, :value) in buckets.entries)
        if (key != otherMealType || value.isNotEmpty) (key, value),
    ];
  }

  String _optionsSummary() {
    final parts = [
      if (_cache.preferences.isNotEmpty) _cache.preferences,
      _cache.mealCount == 4 ? '3 meals + snack' : '3 meals',
    ];
    return parts.join(' · ');
  }

  Future<void> _mealActions(FoodEntry entry) async {
    final meal = entry.meal;
    final action = await showAppDialog<String>(
      context: context,
      title: mealTypeOf(meal) == otherMealType ? meal.label : mealTypeOf(meal),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${meal.items.map((item) => item.name).join(', ')} · '
            '${meal.kcal} kcal',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Move to', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          MealTypePicker(
            selected: mealTypeOf(meal),
            onChanged: (type) => Navigator.pop(context, 'move:$type'),
          ),
        ],
      ),
      actions: [
        FButton(
          key: const Key('nutrition-meal-edit'),
          variant: .outline,
          prefix: const Icon(FLucideIcons.pencil),
          onPress: () => Navigator.pop(context, 'edit'),
          child: const Text('Edit portion'),
        ),
        FButton(
          key: const Key('nutrition-meal-remove'),
          variant: .destructive,
          prefix: const Icon(FLucideIcons.trash2),
          onPress: () => Navigator.pop(context, 'remove'),
          child: const Text('Remove'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editLogged(entry);
    } else if (action == 'remove') {
      await _removeLogged(entry);
    } else if (action.startsWith('move:')) {
      final type = action.substring('move:'.length);
      if (type == mealTypeOf(meal)) return;
      await AppScope.of(context).replaceMeal(entry.id, _typed(meal, type));
    }
  }
}

/// Why the page shows no calorie targets.
enum _NoTargets {
  /// Height, age or a logged weight is missing.
  profile,

  /// Under 18: FitFlow sets no calorie targets
  /// ([BodyMetrics.adultFormulasApply]).
  minor,
}

/// In place of targets: why there are none, and a way to fix the profile.
class _NoTargetsCard extends StatelessWidget {
  const _NoTargetsCard(this.reason);

  final _NoTargets reason;

  @override
  Widget build(BuildContext context) {
    final (key, text, action) = switch (reason) {
      _NoTargets.profile => (
        const Key('nutrition-profile-needed'),
        'Set up your body profile and log a weight first — your calorie '
            'target comes from TDEE.',
        'Open body metrics',
      ),
      _NoTargets.minor => (
        const Key('nutrition-minor'),
        'Calorie targets are for adults. Under 18, energy needs change as '
            'you grow — ask a doctor or school nurse what is right for you. '
            'You can still log what you eat.',
        'Turned 18? Update your age',
      ),
    };
    return AppCard(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: AppSpacing.sm),
          FButton(
            key: const Key('nutrition-open-metrics'),
            variant: .ghost,
            size: .sm,
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BodyMetricsPage()),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// Kilocalories against a target, shared by the day summary and the
/// suggested menu.
class _KcalProgress extends StatelessWidget {
  const _KcalProgress({required this.eaten, required this.target});

  final int eaten;
  final int target;

  // 0 / 0 is NaN, which clamp passes through.
  @override
  Widget build(BuildContext context) => FDeterminateProgress(
    value: target <= 0 ? 0 : (eaten / target).clamp(0.0, 1.0),
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
        child: _KcalProgress(eaten: plan.totalKcal, target: plan.targetKcal),
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

/// Month label + a horizontal strip of the kept days, newest on the right,
/// each showing that day's kcal.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.days,
    required this.selected,
    required this.kcalOf,
    required this.onSelect,
    required this.onOpenCalendar,
  });

  /// Oldest → newest (today last).
  final List<DateTime> days;
  final DateTime selected;
  final int Function(DateTime day) kcalOf;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onOpenCalendar;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  static const _cellWidth = 52.0;
  static const _gap = AppSpacing.xs;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  /// Scrolls the selected day into view (e.g. after a calendar pick).
  void _reveal() {
    final index = widget.days.indexOf(widget.selected);
    if (!_scroll.hasClients || index < 0) return;
    final fromNewest = widget.days.length - 1 - index;
    final cellStart = fromNewest * (_cellWidth + _gap);
    final viewport = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    if (cellStart >= offset && cellStart + _cellWidth <= offset + viewport) {
      return;
    }
    _scroll.animateTo(
      (cellStart - viewport / 2 + _cellWidth / 2).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = widget.selected;
    final days = widget.days.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${monthNames[selected.month - 1]} ${selected.year}',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (selected != widget.days.last)
              FButton(
                key: const Key('nutrition-go-today'),
                variant: .ghost,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => widget.onSelect(widget.days.last),
                child: const Text('Today'),
              ),
            Semantics(
              label: 'Open calendar',
              child: FButton.icon(
                key: const Key('nutrition-calendar'),
                variant: .ghost,
                size: .sm,
                onPress: widget.onOpenCalendar,
                child: const Icon(FLucideIcons.calendarDays),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 64,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final day = days[index];
              return SizedBox(
                width: _cellWidth,
                child: _DayCell(
                  day: day,
                  label: weekdayNames[day.weekday - 1],
                  kcal: widget.kcalOf(day),
                  selected: day == selected,
                  onTap: () => widget.onSelect(day),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A day: weekday (strip only), date and kcal. Every cell has the same
/// layout so rows line up; days without a log leave the kcal line blank.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.kcal,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final DateTime day;
  final String? label;
  final int kcal;
  final bool selected;

  /// Null for days outside the kept range (shown dimmed).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final enabled = onTap != null;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final dayColor = selected
        ? colors.primaryForeground
        : enabled
        ? colors.foreground
        : colors.mutedForeground.withValues(alpha: 0.45);
    final kcalColor = selected
        ? colors.primaryForeground.withValues(alpha: 0.85)
        : colors.primary;
    final mutedColor = selected
        ? colors.primaryForeground.withValues(alpha: 0.85)
        : colors.mutedForeground;
    final logged = enabled && kcal > 0;
    return Semantics(
      button: enabled,
      selected: selected,
      label:
          '${day.day} ${monthNames[day.month - 1]}, '
          '${logged ? '$kcal kilocalories' : 'nothing logged'}',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('nutrition-day-${FoodLog.dayKey(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.primary : null,
            border: isToday && !selected
                ? Border.all(color: colors.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FittedBox(
              fit: .scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Text(
                      label!,
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                      color: dayColor,
                    ),
                  ),
                  SizedBox(
                    height: 13,
                    width: 40,
                    child: logged
                        ? FittedBox(
                            fit: .scaleDown,
                            child: Text(
                              thousands(kcal),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: kcalColor,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Month grid of the kept days with each day's kcal; pops the picked day.
class _MonthCalendarDialog extends StatefulWidget {
  const _MonthCalendarDialog({
    required this.first,
    required this.last,
    required this.selected,
    required this.kcalOf,
    this.animation,
  });

  final DateTime first;
  final DateTime last;
  final DateTime selected;
  final int Function(DateTime day) kcalOf;
  final Animation<double>? animation;

  @override
  State<_MonthCalendarDialog> createState() => _MonthCalendarDialogState();
}

class _MonthCalendarDialogState extends State<_MonthCalendarDialog> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  bool get _hasPrevious =>
      _month.isAfter(DateTime(widget.first.year, widget.first.month));
  bool get _hasNext =>
      _month.isBefore(DateTime(widget.last.year, widget.last.month));

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1; // Monday-first grid
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return FDialog(
      style: .context(),
      animation: widget.animation,
      builder: (context, style) => AppDialogContent(
        title: 'Food log calendar',
        style: style,
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    FButton.icon(
                      key: const Key('calendar-prev-month'),
                      variant: .ghost,
                      size: .sm,
                      onPress: _hasPrevious ? () => _shiftMonth(-1) : null,
                      child: const Icon(FLucideIcons.chevronLeft),
                    ),
                    Expanded(
                      child: Text(
                        '${monthNames[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                        ),
                      ),
                    ),
                    FButton.icon(
                      key: const Key('calendar-next-month'),
                      variant: .ghost,
                      size: .sm,
                      onPress: _hasNext ? () => _shiftMonth(1) : null,
                      child: const Icon(FLucideIcons.chevronRight),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final weekday in weekdayNames)
                      Expanded(
                        child: Text(
                          weekday.substring(0, 2),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var row = 0; row < cells.length; row += 7)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      spacing: 3,
                      children: [
                        for (final day in cells.sublist(row, row + 7))
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: day == null
                                  ? null
                                  : _DayCell(
                                      day: day,
                                      kcal: widget.kcalOf(day),
                                      selected: day == widget.selected,
                                      onTap:
                                          day.isBefore(widget.first) ||
                                              day.isAfter(widget.last)
                                          ? null
                                          : () => Navigator.pop(context, day),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Food logs are kept for the last ${FoodLog.keepDays} days.',
                  style: TextStyle(fontSize: 12, color: colors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// What was eaten on the shown day: total kcal and the three macros.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.eaten,
    required this.dayText,
    required this.tdee,
    required this.targets,
    required this.missing,
    required this.goal,
    required this.onChangeGoal,
  });

  static const _proteinColor = Color(0xFF2563EB);
  static const _carbsColor = Color(0xFFF59E0B);
  static const _fatColor = Color(0xFFEC4899);

  final ({int kcal, double proteinG, double carbsG, double fatG}) eaten;
  final String dayText;
  final double? tdee;
  final DailyTargets? targets;

  /// Why there are no targets, if there aren't; minors still get the
  /// goal row (the goal drives workout picks).
  final _NoTargets? missing;
  final String? goal;
  final VoidCallback onChangeGoal;

  /// Why [target] is held back, in words; null when it isn't.
  String? _limitText(DailyTargets target) => switch (target.limit) {
    TargetLimit.underweight =>
      'Your BMI is close to or under ${BodyMetrics.underweightBmi}, so '
          'FitFlow shrinks or removes the calorie deficit. Talk to a doctor '
          'or dietitian before trying to lose weight.',
    TargetLimit.floor =>
      'The deficit stops at ${thousands(target.kcal)} kcal, the lowest '
          'target FitFlow sets without medical supervision.',
    TargetLimit.lowMaintenance =>
      'Your estimated maintenance is below ${thousands(target.kcal)} kcal, '
          'the lowest target FitFlow sets without medical supervision, so '
          'the target is held there.'
          '${nutritionIntent(goal) == NutritionIntent.loseFat ? ' There is no deficit — talk to a doctor or dietitian about losing weight.' : ''}',
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final target = targets;
    final limitText = target == null ? null : _limitText(target);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: target == null
                ? '${eaten.kcal} kilocalories eaten $dayText'
                : '${eaten.kcal} of ${target.kcal} kilocalories eaten '
                      '$dayText',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  thousands(eaten.kcal),
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    target == null
                        ? 'kcal eaten $dayText'
                        : '/ ${thousands(target.kcal)} kcal eaten $dayText',
                    key: const Key('nutrition-eaten'),
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
          if (target != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _KcalProgress(eaten: eaten.kcal, target: target.kcal),
            const SizedBox(height: AppSpacing.xs),
            if (eaten.kcal <= target.kcal)
              Text(
                '${thousands(target.kcal - eaten.kcal)} kcal to go',
                style: muted,
              )
            // Stated plainly, not as a warning: above target is fine at
            // maintenance or in a surplus, and a suggested menu may land a
            // little over it.
            else
              Text(
                '${thousands(eaten.kcal - target.kcal)} kcal above target',
                key: const Key('nutrition-over-target'),
                style: muted,
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            key: const Key('nutrition-macros'),
            spacing: AppSpacing.md,
            children: [
              _macro(
                context,
                'Protein',
                eaten.proteinG,
                _proteinColor,
                target?.proteinG,
              ),
              _macro(
                context,
                'Carbs',
                eaten.carbsG,
                _carbsColor,
                target?.carbsG,
              ),
              _macro(context, 'Fat', eaten.fatG, _fatColor, target?.fatG),
            ],
          ),
          if (missing != _NoTargets.profile) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  FLucideIcons.target,
                  size: 16,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '${goal == null ? 'No goal' : goalLabel(goal!)}'
                    '${tdee == null ? '' : ' · TDEE ${thousands(tdee!)} kcal'}',
                    style: muted,
                  ),
                ),
                FButton(
                  key: const Key('nutrition-change-goal'),
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: onChangeGoal,
                  child: Text(goal == null ? 'Set goal' : 'Change'),
                ),
              ],
            ),
          ],
          if (limitText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              key: const Key('nutrition-target-limit'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FLucideIcons.shieldAlert, size: 16, color: colors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(limitText, style: textTheme.bodySmall)),
              ],
            ),
          ],
          // Only next to targets — the estimates it is about.
          if (target != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Estimates for healthy adults, not medical advice.',
              key: const Key('nutrition-disclaimer'),
              style: muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _macro(
    BuildContext context,
    String label,
    double grams,
    Color color, [
    int? target,
  ]) {
    final colors = context.theme.colors;
    return Expanded(
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 4, height: 32),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: colors.mutedForeground),
                ),
                Text(
                  target == null
                      ? '${grams.round()} g'
                      : '${grams.round()} / $target g',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three equal "add a meal" entry points.
class _AddButton extends StatelessWidget {
  const _AddButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => FButton(
    variant: .outline,
    size: .sm,
    onPress: onPress,
    prefix: icon,
    child: Flexible(
      child: FittedBox(fit: .scaleDown, child: Text(label)),
    ),
  );
}

/// One meal slot of the day: its total and the entries logged into it.
class _MealSlotCard extends StatelessWidget {
  const _MealSlotCard({
    required this.type,
    required this.entries,
    required this.onAdd,
    required this.onMore,
  });

  final String type;

  /// The slot's logged entries, oldest first.
  final List<FoodEntry> entries;
  final VoidCallback? onAdd;
  final ValueChanged<FoodEntry> onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final total = FoodLog.totals(entries.map((entry) => entry.meal));
    final empty = entries.isEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: empty ? colors.muted : colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    mealIcon(type),
                    size: 18,
                    color: empty ? colors.mutedForeground : colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      empty
                          ? 'Not logged yet'
                          : 'P ${total.proteinG.round()}g · '
                                'C ${total.carbsG.round()}g · '
                                'F ${total.fatG.round()}g',
                      style: muted,
                    ),
                  ],
                ),
              ),
              if (!empty)
                Text(
                  '${thousands(total.kcal)} kcal',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (onAdd != null)
                Semantics(
                  label: 'Add to $type',
                  child: FButton.icon(
                    key: Key('nutrition-add-$type'),
                    variant: .ghost,
                    size: .sm,
                    onPress: onAdd,
                    child: Icon(FLucideIcons.plus, color: colors.primary),
                  ),
                ),
            ],
          ),
          for (final entry in entries) ...[
            const SizedBox(height: AppSpacing.xs),
            _entryRow(context, entry),
          ],
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context, FoodEntry entry) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final meal = entry.meal;
    return Padding(
      padding: const EdgeInsets.only(left: 42),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in meal.items)
                  Text(item.name, style: textTheme.bodyMedium),
                if (mealTypeOf(meal) == otherMealType)
                  Text(meal.label, style: muted),
              ],
            ),
          ),
          Text(
            '${thousands(meal.kcal)} kcal',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          Semantics(
            label:
                'Actions for ${meal.items.isEmpty ? meal.label : meal.items.first.name}',
            child: FButton.icon(
              key: const Key('nutrition-meal-more'),
              variant: .ghost,
              size: .sm,
              onPress: () => onMore(entry),
              child: Icon(
                FLucideIcons.ellipsisVertical,
                size: 18,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(FLucideIcons.utensils, color: colors.mutedForeground),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Nothing logged this day.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The AI day-menu generator; its options stay folded until asked for.
class _AiPlanCard extends StatelessWidget {
  const _AiPlanCard({
    required this.configured,
    required this.targetKcal,
    required this.missing,
    required this.hasPlan,
    required this.generating,
    required this.showOptions,
    required this.onToggleOptions,
    required this.optionsSummary,
    required this.options,
    required this.onGenerate,
  });

  final bool configured;
  final int? targetKcal;

  /// Why there is no target to plan for, if there isn't; minors get no
  /// menu settings either.
  final _NoTargets? missing;
  final bool hasPlan;
  final bool generating;
  final bool showOptions;
  final VoidCallback onToggleOptions;
  final String optionsSummary;
  final Widget options;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final target = targetKcal;
    final subtitle = switch (missing) {
      _NoTargets.minor => 'Menu suggestions are for adults only.',
      _NoTargets.profile =>
        'Set up your body profile to get a menu for your target.',
      null => 'A full day menu for your ${thousands(target ?? 0)} kcal target.',
    };
    return AppCard(
      style: .delta(
        decoration: .boxDelta(
          color: colors.secondary,
          border: Border.all(width: 0, color: Colors.transparent),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FLucideIcons.sparkles, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'AI meal plan',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: muted),
          if (missing != _NoTargets.minor) ...[
            const SizedBox(height: AppSpacing.sm),
            FButton(
              key: const Key('nutrition-plan-options'),
              variant: .ghost,
              size: .sm,
              mainAxisSize: .min,
              onPress: onToggleOptions,
              prefix: const Icon(FLucideIcons.slidersHorizontal),
              suffix: Icon(
                showOptions ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
              ),
              child: Flexible(
                child: Text(
                  showOptions ? 'Options' : 'Options: $optionsSummary',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (showOptions) ...[
              const SizedBox(height: AppSpacing.sm),
              options,
            ],
          ],
          if (!configured) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'AI suggestions need an OpenAI API key '
              '(.env file or --dart-define=OPENAI_API_KEY=…).',
            ),
          ] else if (onGenerate != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FButton(
                key: const Key('nutrition-generate'),
                onPress: generating ? null : onGenerate,
                prefix: generating
                    ? const FCircularProgress()
                    : const Icon(FLucideIcons.sparkles),
                child: Text(
                  generating
                      ? 'Generating…'
                      : hasPlan
                      ? "Regenerate today's menu"
                      : "Suggest today's menu",
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, this.onLog});

  final Meal meal;

  /// One-tap logging of a suggested meal.
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    // A one-item meal would repeat the same kcal on both rows.
    final showItemKcal = meal.items.length > 1;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    mealIcon(meal.label),
                    size: 18,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.label,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'P ${meal.proteinG.round()}g · '
                      'C ${meal.carbsG.round()}g · '
                      'F ${meal.fatG.round()}g',
                      style: muted,
                    ),
                  ],
                ),
              ),
              Text(
                '${thousands(meal.kcal)} kcal',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
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
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in meal.items)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text(item.name, style: textTheme.bodyMedium)),
                  if (showItemKcal)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Text(
                        '${item.kcal} kcal',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
