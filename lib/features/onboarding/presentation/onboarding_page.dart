import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/training_options.dart';

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
  static const _levels = trainingLevels;

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
            _LevelPicker(
              levels: _levels,
              selected: _level,
              onChanged: (level) => setState(() => _level = level),
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

/// Experience levels as equal buttons: one row when every label fits a
/// third of the width at the user's text scale, otherwise stacked — so
/// labels keep one size and are never shrunk below the chosen scale.
class _LevelPicker extends StatelessWidget {
  const _LevelPicker({
    required this.levels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> levels;
  final String? selected;
  final ValueChanged<String> onChanged;

  /// Room a small button needs around its label (padding + border).
  static const _chrome = 24.0;

  @override
  Widget build(BuildContext context) {
    final style = context.theme.typography.body.xs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 480.0);
        final painter = TextPainter(
          text: TextSpan(
            text: levels.reduce((a, b) => a.length >= b.length ? a : b),
            style: style,
          ),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final column =
            (width - AppSpacing.sm * (levels.length - 1)) / levels.length;
        final fitsRow = painter.width + _chrome <= column;
        painter.dispose();
        final buttons = [
          for (final level in levels)
            FButton(
              variant: level == selected ? .primary : .outline,
              size: .sm,
              onPress: () => onChanged(level),
              child: Text(level, style: style),
            ),
        ];
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: fitsRow
              ? Row(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final button in buttons) Expanded(child: button),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.sm,
                  children: buttons,
                ),
        );
      },
    );
  }
}
