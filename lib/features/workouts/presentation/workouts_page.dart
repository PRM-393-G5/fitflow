import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout.dart';
import 'ai_workout_page.dart';
import 'workout_builder_page.dart';
import 'workout_detail_page.dart';
import '../../../core/widgets/app_card.dart';

class WorkoutsPage extends StatefulWidget {
  const WorkoutsPage({super.key});

  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  static const _all = 'All';
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  final _searchCtrl = TextEditingController();
  String _category = _all;
  String _level = _all;

  /// The onboarding goal last applied as the category filter. The filter
  /// follows goal changes (including onboarding finishing after the first
  /// build) without overriding a choice the user made since.
  String? _appliedGoal;

  String get _query => _searchCtrl.text.trim().toLowerCase();
  bool get _filtered =>
      _query.isNotEmpty || _category != _all || _level != _all;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final goal = AppScope.of(context).goal;
    if (goal == _appliedGoal) return;
    _appliedGoal = goal;
    if (goal != null) _category = goal;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _searchCtrl.clear();
    _category = _all;
    _level = _all;
  });

  bool _matches(Workout workout) {
    if (_category != _all && workout.category != _category) return false;
    if (_level != _all && workout.level != _level) return false;
    final query = _query;
    if (query.isEmpty) return true;
    return [
      workout.name,
      workout.category,
      workout.level,
      for (final exercise in workout.exercises) ...[
        exercise.name,
        exercise.muscleGroup,
      ],
    ].any((text) => text.toLowerCase().contains(query));
  }

  /// Opens the builder or AI page; a newly saved plan comes back as the
  /// result, so show it instead of letting the filters hide it.
  Future<void> _create(Widget page) async {
    final saved = await Navigator.of(context)
        .push(MaterialPageRoute<Workout>(builder: (_) => page));
    if (saved == null || !mounted) return;
    setState(() {
      _searchCtrl.clear();
      _category = saved.category;
      _level = _all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workouts = controller.workouts.where(_matches).toList();
    final categories = {
      _all,
      ...controller.workouts.map((item) => item.category),
      _category,
    };

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workouts', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text('Choose a plan that fits your time and energy.'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FTextField(
                  key: const Key('workout-search'),
                  hint: 'Search plans, exercises, muscles',
                  control: .managed(controller: _searchCtrl),
                  prefixBuilder: (context, style, variants) =>
                      FTextField.prefixIconBuilder(
                        context,
                        style,
                        variants,
                        const Icon(FLucideIcons.search),
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FButton.icon(
                key: const Key('open-ai-workout'),
                variant: .secondary,
                onPress: () => _create(const AiWorkoutPage()),
                child: const Icon(FLucideIcons.sparkles),
              ),
              const SizedBox(width: AppSpacing.sm),
              FButton.icon(
                key: const Key('open-workout-builder'),
                onPress: () => _create(const WorkoutBuilderPage()),
                child: const Icon(FLucideIcons.plus),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _chips(
            categories,
            _category,
            (value) => setState(() => _category = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          _chips(
            {_all, ..._levels},
            _level,
            (value) => setState(() => _level = value),
            labelFor: (value) => value == _all ? 'All levels' : value,
          ),
          if (_filtered) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${workouts.length} of ${controller.workouts.length} plans'
                    '${_category != _all && _category == controller.goal ? ' • filtered by your goal' : ''}',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
                FButton(
                  key: const Key('clear-workout-filters'),
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: _clearFilters,
                  prefix: const Icon(FLucideIcons.x),
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (controller.error != null)
            _Message(icon: FLucideIcons.circleAlert, text: controller.error!)
          else if (controller.loading && controller.workouts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: FCircularProgress(),
              ),
            )
          else if (workouts.isEmpty)
            const _Message(
              icon: FLucideIcons.searchX,
              text: 'No workouts match your filters.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: workouts.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 150,
                  ),
                  itemBuilder: (_, index) =>
                      _WorkoutCard(workout: workouts[index]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _chips(
    Iterable<String> values,
    String selected,
    ValueChanged<String> onSelect, {
    String Function(String value)? labelFor,
  }) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FButton(
              variant: selected == value ? .primary : .outline,
              size: .sm,
              onPress: () => onSelect(value),
              child: Text(labelFor?.call(value) ?? value),
            ),
          ),
      ],
    ),
  );
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout});
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: colors.mutedForeground);
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: FTappable(
        onPress: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailPage(workout: workout),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      FLucideIcons.dumbbell,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${workout.duration.inMinutes} min',
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                workout.name,
                style: textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${workout.category} • ${workout.level} • '
                '${workout.exercises.length} exercises • '
                '${workout.totalSets} sets',
                style: muted,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 64),
          const SizedBox(height: AppSpacing.md),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
