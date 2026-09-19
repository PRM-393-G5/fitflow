import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter/services.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/workout_stats.dart';

/// ponytail: renders the share card and copies a text summary via the
/// clipboard — capturing the card as an image and sending it to other apps
/// needs share_plus (roadmap item).
Future<void> showShareSummaryDialog(BuildContext context) {
  final controller = AppScope.of(context);
  return showFDialog<void>(
    context: context,
    builder: (context, style, animation) => FDialog(
      style: style,
      animation: animation,
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            _ShareCard(controller: controller),
            const SizedBox(height: AppSpacing.md),
            FButton(
              variant: .ghost,
              onPress: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FButton(
              onPress: () async {
                await Clipboard.setData(
                  ClipboardData(text: _summaryText(controller)),
                );
                if (context.mounted) {
                  showFToast(
                    context: context,
                    title: const Text('Summary copied.'),
                  );
                }
              },
              prefix: const Icon(FLucideIcons.copy),
              child: const Text('Copy summary'),
            ),
          ],
        ),
      ),
    ),
  );
}

String _summaryText(AppController controller) =>
    'FitFlow — ${controller.sessions.length} workouts, '
    '${WorkoutStats.totalMinutes(controller.sessions)} minutes, '
    '${WorkoutStats.streak(controller.sessions)}-day streak';

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.sessions;
    final volume = WorkoutStats.totalVolume(sessions);
    final displayVolume = controller.useMetric ? volume : volume * 2.20462;
    final unit = controller.useMetric ? 'kg' : 'lb';
    final stats = [
      ('${WorkoutStats.streak(sessions)}', 'day streak'),
      ('${sessions.length}', 'workouts'),
      ('${WorkoutStats.totalMinutes(sessions)}', 'minutes'),
      ('${displayVolume.round()}', unit),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(FLucideIcons.zap, color: Colors.white),
              SizedBox(width: AppSpacing.sm),
              Text(
                'FITFLOW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.4,
            children: [
              for (final stat in stats)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.$1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      stat.$2,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
