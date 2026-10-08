import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

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
  bool _saving = false;

  static const _goals = [
    (label: 'Build muscle', category: 'Strength', icon: FLucideIcons.dumbbell),
    (label: 'Lose fat', category: 'Cardio', icon: FLucideIcons.flame),
    (label: 'Stay mobile', category: 'Mobility', icon: FLucideIcons.activity),
  ];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  Future<void> _finish({bool skip = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      await AppScope.of(context).completeOnboarding(
        goal: skip ? null : _goal,
        level: skip ? null : _level,
      );
    } finally {
      _saving = false;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // System back counts as "Skip for now" — otherwise onboarding would be
  // dismissed unsaved and reappear on every launch.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _finish(skip: true);
    },
    child: FScaffold(
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(
              FLucideIcons.zap,
              size: 48,
              color: context.theme.colors.primary,
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
            FTileGroup(
              children: [
                for (final item in _goals)
                  FTile(
                    prefix: Icon(item.icon),
                    title: Text(item.label),
                    suffix: _goal == item.category
                        ? Icon(
                            FLucideIcons.circleCheckBig,
                            color: context.theme.colors.primary,
                          )
                        : null,
                    onPress: () => setState(() => _goal = item.category),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Experience level',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              spacing: AppSpacing.sm,
              children: [
                for (final item in _levels)
                  Expanded(
                    child: FButton(
                      variant: _level == item ? .primary : .outline,
                      size: .sm,
                      // Smaller text and side padding so all three labels fit
                      // a third of a phone width at the same size.
                      style: const .delta(
                        contentStyle: .delta(
                          padding: .add(EdgeInsets.symmetric(horizontal: -4)),
                        ),
                      ),
                      onPress: () => setState(() => _level = item),
                      child: Flexible(
                        child: FittedBox(
                          fit: .scaleDown,
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FButton(
                onPress: _goal == null || _level == null
                    ? null
                    : () => _finish(),
                child: const Text('Start training'),
              ),
            ),
            Center(
              child: FButton(
                variant: .ghost,
                onPress: () => _finish(skip: true),
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
