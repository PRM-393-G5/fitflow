import 'package:flutter/material.dart';
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
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: EdgeInsets.zero,
      content: SizedBox(width: 320, child: _ShareCard(controller: controller)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: _summaryText(controller)),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Summary copied.')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy summary'),
        ),
      ],
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
          colors: [Color(0xFF6558D3), Color(0xFF2B2457)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.white),
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
