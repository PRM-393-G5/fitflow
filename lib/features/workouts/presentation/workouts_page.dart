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
  String _query = '';
  String _category = 'All';
  bool _appliedGoal = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedGoal) return;
    _appliedGoal = true;
    final goal = AppScope.of(context).goal;
    if (goal != null) _category = goal;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workouts = controller.workouts.where((workout) {
      final queryMatches = workout.name.toLowerCase().contains(
        _query.toLowerCase(),
      );
      return queryMatches &&
          (_category == 'All' || workout.category == _category);
    }).toList();
    final categories = {
      'All',
      ...controller.workouts.map((item) => item.category),
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
                  hint: 'Search workouts',
                  control: .managed(
                    onChange: (value) => setState(() => _query = value.text),
                  ),
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
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiWorkoutPage(),
                  ),
                ),
                child: const Icon(FLucideIcons.sparkles),
              ),
              const SizedBox(width: AppSpacing.sm),
              FButton.icon(
                key: const Key('open-workout-builder'),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkoutBuilderPage(),
                  ),
                ),
                child: const Icon(FLucideIcons.plus),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories
                  .map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: FButton(
                        variant: _category == category ? .primary : .outline,
                        size: .sm,
                        onPress: () => setState(() => _category = category),
                        child: Text(category),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (controller.error != null)
            _Message(icon: FLucideIcons.circleAlert, text: controller.error!)
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
