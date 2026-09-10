import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String? _goal;
  String? _level;

  static const _goals = [
    (label: 'Build muscle', category: 'Strength', icon: Icons.fitness_center),
    (label: 'Lose fat', category: 'Cardio', icon: Icons.local_fire_department),
    (label: 'Stay mobile', category: 'Mobility', icon: Icons.self_improvement),
  ];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  Future<void> _finish({bool skip = false}) async {
    await AppScope.of(context).completeOnboarding(
      goal: skip ? null : _goal,
      level: skip ? null : _level,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(
              Icons.bolt,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Welcome to FitFlow',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Text('Two quick questions to personalize your plan.'),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'What is your goal?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._goals.map(
              (item) => Card(
                child: ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.label),
                  trailing: _goal == item.category
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const Icon(Icons.circle_outlined),
                  onTap: () => setState(() => _goal = item.category),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Experience level',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: _levels
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item),
                      selected: _level == item,
                      onSelected: (_) => setState(() => _level = item),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _goal == null || _level == null
                    ? null
                    : () => _finish(),
                child: const Text('Start training'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => _finish(skip: true),
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
