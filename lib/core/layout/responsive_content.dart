import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: child,
      ),
    ),
  );
}
