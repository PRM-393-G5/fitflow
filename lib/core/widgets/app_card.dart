import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// FCard that actually applies `FCardStyle.padding` to its child.
///
/// Stock [FCard] renders only a [DecoratedBox] around the child — the style's
/// padding exists but is never applied, so content hugs the card edges.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.style = const .context(),
    this.clipBehavior = .none,
    required this.child,
  });

  final FCardStyleDelta style;
  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) => FCard(
    style: style,
    clipBehavior: clipBehavior,
    builder: (context, style, child) =>
        Padding(padding: style.padding, child: child),
    child: child,
  );
}
