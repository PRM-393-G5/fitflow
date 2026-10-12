import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/workout_stats.dart';

/// Shows the share card; "Share" renders it to a PNG and hands it (plus a
/// text summary) to the system share sheet, falling back to text only.
Future<void> showShareSummaryDialog(BuildContext context) {
  final controller = AppScope.of(context);
  return showFDialog<void>(
    context: context,
    builder: (context, style, animation) => FDialog(
      style: style,
      animation: animation,
      builder: (context, style) => _ShareSummaryContent(controller: controller),
    ),
  );
}

/// The numbers on the card and in the text, computed once so they agree.
typedef _Summary = ({
  int streak,
  int workouts,
  int minutes,
  String volume,
  String unit,
});

_Summary _summary(AppController controller) {
  final sessions = controller.sessions;
  final volume = WorkoutStats.totalVolume(sessions);
  final display = controller.useMetric ? volume : volume * 2.20462;
  return (
    streak: WorkoutStats.weeklyStreak(sessions, controller.weeklyGoal).current,
    workouts: WorkoutStats.training(sessions).length,
    minutes: WorkoutStats.totalMinutes(sessions),
    volume: '${display.round()}',
    unit: controller.useMetric ? 'kg' : 'lb',
  );
}

String _summaryText(_Summary summary) =>
    'FitFlow — ${summary.workouts} workouts, '
    '${summary.minutes} minutes, '
    '${summary.volume} ${summary.unit} lifted, '
    'current streak: ${summary.streak} '
    '${summary.streak == 1 ? 'week' : 'weeks'}';

class _ShareSummaryContent extends StatefulWidget {
  const _ShareSummaryContent({required this.controller});

  final AppController controller;

  @override
  State<_ShareSummaryContent> createState() => _ShareSummaryContentState();
}

class _ShareSummaryContentState extends State<_ShareSummaryContent> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<Uint8List?> _renderCard() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Rect? _origin() {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share(String text) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final origin = _origin();
    try {
      Uint8List? png;
      try {
        png = await _renderCard();
      } catch (e) {
        debugPrint('Could not render share card: $e');
      }
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            files: png == null
                ? null
                : [
                    XFile.fromData(
                      png,
                      mimeType: 'image/png',
                      name: 'fitflow.png',
                    ),
                  ],
            sharePositionOrigin: origin,
          ),
        );
      } catch (e) {
        // Image sharing unsupported here — share the text alone.
        debugPrint('Image share failed, sharing text: $e');
        await SharePlus.instance.share(
          ShareParams(text: text, sharePositionOrigin: origin),
        );
      }
    } catch (e) {
      debugPrint('Share failed: $e');
      await _copy(text, 'Sharing is unavailable — summary copied instead.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copy(String text, [String message = 'Summary copied.']) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showFToast(context: context, title: Text(message));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary(widget.controller);
    final text = _summaryText(summary);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: _ShareCard(summary: summary),
          ),
          const SizedBox(height: AppSpacing.md),
          FButton(
            key: const Key('share-summary'),
            onPress: _sharing ? null : () => _share(text),
            prefix: _sharing
                ? const FCircularProgress()
                : const Icon(FLucideIcons.share2),
            child: const Text('Share'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FButton(
            variant: .outline,
            onPress: () => _copy(text),
            prefix: const Icon(FLucideIcons.copy),
            child: const Text('Copy summary'),
          ),
          const SizedBox(height: AppSpacing.sm),
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

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.summary});

  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('${summary.streak}', 'week streak'),
      ('${summary.workouts}', 'workouts'),
      ('${summary.minutes}', 'minutes'),
      (summary.volume, '${summary.unit} lifted'),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(28)),
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
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
