import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout.dart';
import 'workout_builder_page.dart';
import 'workout_detail_page.dart';

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
          Text(
            'Workouts',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Choose a plan that fits your time and energy.'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search workouts',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                key: const Key('open-workout-builder'),
                tooltip: 'Create workout',
                icon: const Icon(Icons.add),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkoutBuilderPage(),
                  ),
                ),
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
                      child: FilterChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (controller.error != null)
            _Message(icon: Icons.error_outline, text: controller.error!)
          else if (workouts.isEmpty)
            const _Message(
              icon: Icons.search_off,
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
                    mainAxisExtent: 190,
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
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
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
                Icon(
                  Icons.fitness_center,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const Spacer(),
                Text('${workout.duration.inMinutes} min'),
              ],
            ),
            const Spacer(),
            Text(
              workout.name,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('${workout.category} • ${workout.level}'),
            Text(
              '${workout.exercises.length} exercises • ${workout.totalSets} sets',
            ),
          ],
        ),
      ),
    ),
  );
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
