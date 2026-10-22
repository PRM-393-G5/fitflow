import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../domain/muscle_volume.dart';
import '../theme/app_theme.dart';

part 'muscle_body_map_paths.dart';

/// Credits the body art on the app's license page; call once at startup.
void registerMuscleMapLicense() => LicenseRegistry.addLicense(
  () => Stream.value(
    const LicenseEntryWithLineBreaks([
      'react-native-body-highlighter',
    ], _bodyArtLicense),
  ),
);

/// [color] flattened onto the card, so a body part looks the same whatever
/// is painted beneath it (muscles sit on the torso).
Color muscleMapSolid(FColors colors, Color color) =>
    Color.alphaBlend(color, colors.card);

/// The fill of a muscle with nothing to show.
Color muscleMapUntrained(FColors colors) =>
    muscleMapSolid(colors, colors.mutedForeground.withValues(alpha: .35));

Color _neutral(FColors colors) =>
    muscleMapSolid(colors, colors.mutedForeground.withValues(alpha: .12));

/// Front and back anatomy side by side, each muscle painted with its
/// [fills] colour (untrained grey when absent). Tapping a muscle calls
/// [onTap].
class MuscleBodyMap extends StatelessWidget {
  const MuscleBodyMap({
    required this.fills,
    required this.onTap,
    required this.semanticsLabel,
    this.height = 280,
    super.key,
  });

  final Map<Muscle, Color> fills;
  final ValueChanged<Muscle> onTap;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (side, front) in [('Front', true), ('Back', false)])
            Column(
              children: [
                SizedBox(
                  height: height,
                  child: AspectRatio(
                    aspectRatio: _BodyPainter.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) => GestureDetector(
                        key: Key('muscle-map-${side.toLowerCase()}'),
                        onTapUp: (details) {
                          final muscle = _muscleAt(
                            front ? _front : _back,
                            constraints.biggest,
                            details.localPosition,
                          );
                          if (muscle != null) onTap(muscle);
                        },
                        child: CustomPaint(
                          size: constraints.biggest,
                          painter: _BodyPainter(
                            front: front,
                            fills: fills,
                            untrained: muscleMapUntrained(colors),
                            neutral: _neutral(colors),
                            outline: colors.border,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(side, style: labelStyle),
              ],
            ),
        ],
      ),
    );
  }
}

/// A small colour swatch for chips and legends.
class MuscleDot extends StatelessWidget {
  const MuscleDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// One SVG path of the body art. [muscle] is null for parts we don't
/// track (head, hands, joints), which stay neutral.
class _BodyPath {
  const _BodyPath(this.muscle, this.data);

  final Muscle? muscle;
  final String data;
}

typedef _View = ({
  Path outline,
  List<(Muscle?, Path)> parts,

  /// Everything drawn: the outline leaves out the head.
  Rect bounds,
});

_View _parse(String outline, List<_BodyPath> paths) {
  final body = parseSvgPathData(outline);
  final parts = [
    for (final path in paths) (path.muscle, parseSvgPathData(path.data)),
  ];
  return (
    outline: body,
    parts: parts,
    bounds: parts.fold(
      body.getBounds(),
      (bounds, part) => bounds.expandToInclude(part.$2.getBounds()),
    ),
  );
}

// Parsed once, on first use.
final _front = _parse(_frontOutline, _frontPaths);
final _back = _parse(_backOutline, _backPaths);

/// Maps art coordinates of [view] into a [size] box, centred.
Matrix4 _fit(_View view, Size size) {
  final bounds = view.bounds;
  final scale = (size.width / bounds.width) < (size.height / bounds.height)
      ? size.width / bounds.width
      : size.height / bounds.height;
  return Matrix4.identity()
    ..translateByDouble(
      (size.width - bounds.width * scale) / 2,
      (size.height - bounds.height * scale) / 2,
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
}

/// The tracked muscle under [position], topmost first.
Muscle? _muscleAt(_View view, Size size, Offset position) {
  final inverse = Matrix4.tryInvert(_fit(view, size));
  if (inverse == null) return null;
  final point = MatrixUtils.transformPoint(inverse, position);
  for (final (muscle, path) in view.parts.reversed) {
    if (path.contains(point)) return muscle;
  }
  return null;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.front,
    required this.fills,
    required this.untrained,
    required this.neutral,
    required this.outline,
  });

  /// Width / height of the figure (both views are the same size).
  static double get aspectRatio => _front.bounds.size.aspectRatio;

  final bool front;
  final Map<Muscle, Color> fills;
  final Color untrained;
  final Color neutral;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final view = front ? _front : _back;
    final transform = _fit(view, size);
    canvas
      ..save()
      ..transform(transform.storage)
      ..drawPath(view.outline, Paint()..color = neutral);
    for (final (muscle, path) in view.parts) {
      canvas.drawPath(
        path,
        Paint()..color = muscle == null ? neutral : fills[muscle] ?? untrained,
      );
    }
    canvas
      ..drawPath(
        view.outline,
        Paint()
          ..style = PaintingStyle.stroke
          // Constant on screen whatever the figure's size.
          ..strokeWidth = 1 / transform.getMaxScaleOnAxis()
          ..color = outline,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.front != front ||
      old.untrained != untrained ||
      old.neutral != neutral ||
      old.outline != outline ||
      !_sameFills(old.fills);

  bool _sameFills(Map<Muscle, Color> other) =>
      Muscle.values.every((muscle) => fills[muscle] == other[muscle]);
}
