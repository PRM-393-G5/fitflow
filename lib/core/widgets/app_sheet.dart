import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The surface of a bottom sheet: showFSheet draws none of its own, so
/// without this the page behind shows through the content.
class AppSheet extends StatelessWidget {
  const AppSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}
