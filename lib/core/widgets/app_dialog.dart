import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Shared Forui dialog shell — title, optional body, stacked actions.
/// [actions] render full-width, in the given order.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  Widget? body,
  List<Widget> actions = const [],
}) => showFDialog<T>(
  context: context,
  builder: (context, style, animation) => FDialog(
    style: style,
    animation: animation,
    builder: (context, style) => AppDialogContent(
      title: title,
      style: style,
      body: body,
      actions: actions,
    ),
  ),
);

/// Lays out title + body + actions inside an [FDialog]. Reuse this when the
/// dialog needs its own state: build an [FDialog] whose builder returns this.
class AppDialogContent extends StatelessWidget {
  const AppDialogContent({
    super.key,
    required this.title,
    required this.style,
    this.body,
    this.actions = const [],
  });

  final String title;
  final FDialogStyle style;
  final Widget? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Text(title, style: style.titleTextStyle),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DefaultTextStyle(style: style.bodyTextStyle, child: body!),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final action in actions) ...[
            if (!identical(action, actions.first))
              const SizedBox(height: AppSpacing.sm),
            action,
          ],
        ],
      ],
    ),
  );
}
