import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/workout_category_style.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/muscle_volume.dart';
import '../../../domain/training_options.dart';
import 'ai_workout_page.dart';
import 'workout_builder_page.dart';
import 'workout_detail_page.dart';
import '../../../core/widgets/app_sheet.dart';

class WorkoutsPage extends StatefulWidget {
  const WorkoutsPage({super.key});

  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  final _searchCtrl = TextEditingController();
  var _filter = const _PlanFilter();

  String get _query => _searchCtrl.text.trim().toLowerCase();
  bool get _filtered => _query.isNotEmpty || _filter.active;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _searchCtrl.clear();
    _filter = const _PlanFilter();
  });

  Future<void> _openFilters(List<Workout> searched) async {
    final picked = await showFSheet<_PlanFilter>(
      context: context,
      side: .btt,
      mainAxisMaxRatio: .infinity,
      builder: (context) => AppSheet(
        child: _FilterSheet(initial: _filter, workouts: searched),
      ),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  bool _matchesQuery(Workout workout) {
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
    _clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final searched = controller.workouts.where(_matchesQuery).toList();
    final workouts = searched.where(_filter.matches).toList();

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
                key: const Key('open-workout-filters'),
                variant: _filter.active ? .primary : .outline,
                onPress: () => _openFilters(searched),
                child: const Icon(FLucideIcons.slidersHorizontal),
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
          if (_filtered) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${workouts.length} of ${controller.workouts.length} plans'
                    '${_filter.active ? ' • ${_filter.summary}' : ''}',
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
                // Cards size to their text (large system fonts wrap), so
                // a Wrap rather than a fixed-height grid.
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                final width =
                    (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final workout in workouts)
                      SizedBox(
                        width: width,
                        child: _WorkoutCard(workout: workout),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout});
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: colors.mutedForeground);
    final accent = workoutCategoryColor(workout.category, colors.primary);
    final groups = MuscleGroup.trainedBy(workout.exercises);
    // Stock FCard (no padding of its own): the padding goes inside the
    // tappable so the whole card opens the plan.
    return FCard(
      clipBehavior: Clip.antiAlias,
      child: FTappable(
        onPress: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailPage(workout: workout),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  workoutCategoryIcon(workout.category),
                  size: 24,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workout.level} · ${workout.duration.inMinutes} min',
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (groups.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        // Body order, the same as the filter.
                        [
                          for (final group in MuscleGroup.values)
                            if (groups.contains(group)) group.label,
                        ].join(' · '),
                        style: textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                FLucideIcons.chevronRight,
                size: 20,
                color: colors.mutedForeground,
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

/// The sheet's picks: plans training any chosen muscle group, at any
/// chosen level. Empty sets don't filter.
class _PlanFilter {
  const _PlanFilter({this.groups = const {}, this.levels = const {}});

  final Set<MuscleGroup> groups;
  final Set<String> levels;

  bool get active => groups.isNotEmpty || levels.isNotEmpty;

  /// 'Arms, Legs • Beginner', in display order.
  String get summary => [
    if (groups.isNotEmpty)
      [
        for (final group in MuscleGroup.values)
          if (groups.contains(group)) group.label,
      ].join(', '),
    if (levels.isNotEmpty)
      [
        for (final level in trainingLevels)
          if (levels.contains(level)) level,
      ].join(', '),
  ].join(' • ');

  bool matches(Workout workout) =>
      (levels.isEmpty || levels.contains(workout.level)) &&
      (groups.isEmpty ||
          MuscleGroup.trainedBy(workout.exercises).any(groups.contains));
}

/// Bottom sheet that edits a [_PlanFilter] and pops it on "Show"; the
/// button counts the plans the picks would leave.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.workouts});

  final _PlanFilter initial;

  /// The plans the search already leaves.
  final List<Workout> workouts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _groups = {...widget.initial.groups};
  late final _levels = {...widget.initial.levels};

  void _toggle<T>(Set<T> set, T value) =>
      setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final filter = _PlanFilter(groups: _groups, levels: _levels);
    final count = widget.workouts.where(filter.matches).length;

    Widget section(String title, List<Widget> chips) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: chips,
        ),
      ],
    );

    Widget chip(String label, bool selected, VoidCallback onPress) => FButton(
      key: Key('filter-$label'),
      variant: selected ? .primary : .outline,
      size: .sm,
      mainAxisSize: .min,
      onPress: onPress,
      child: Text(label),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filter plans',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            section('Muscle group', [
              for (final group in MuscleGroup.values)
                chip(
                  group.label,
                  _groups.contains(group),
                  () => _toggle(_groups, group),
                ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            section('Level', [
              for (final level in trainingLevels)
                chip(
                  level,
                  _levels.contains(level),
                  () => _toggle(_levels, level),
                ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                FButton(
                  key: const Key('reset-workout-filters'),
                  variant: .outline,
                  mainAxisSize: .min,
                  onPress: filter.active
                      ? () => setState(() {
                          _groups.clear();
                          _levels.clear();
                        })
                      : null,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FButton(
                    key: const Key('apply-workout-filters'),
                    onPress: count == 0
                        ? null
                        : () => Navigator.pop(context, filter),
                    child: Text(
                      count == 0
                          ? 'No plans match'
                          : 'Show $count plan${count == 1 ? '' : 's'}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
