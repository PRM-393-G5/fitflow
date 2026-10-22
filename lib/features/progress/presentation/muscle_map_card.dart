import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/muscle_volume.dart';

part 'muscle_map_paths.dart';

/// Credits the body art on the app's license page; call once at startup.
void registerMuscleMapLicense() => LicenseRegistry.addLicense(
  () => Stream.value(
    const LicenseEntryWithLineBreaks([
      'react-native-body-highlighter',
    ], _bodyArtLicense),
  ),
);

/// This week's sets per muscle, painted on a front and back body outline,
/// with each muscle's count and change from last week listed underneath.
/// Tapping a muscle (on the body or in the list) shows what trained it.
class MuscleMapCard extends StatelessWidget {
  const MuscleMapCard({required this.weeks, super.key});

  final Map<Muscle, MuscleWeek> weeks;

  static const _figureHeight = 280.0;

  MuscleWeek _week(Muscle muscle) =>
      weeks[muscle] ?? const MuscleWeek(sets: 0, previous: 0, exercises: []);

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.mutedForeground);
    final fills = {
      for (final muscle in Muscle.values)
        muscle: _fill(colors, _week(muscle).sets),
    };
    final summary = [
      for (final muscle in Muscle.values)
        '${muscle.label} ${MuscleVolume.sets(_week(muscle).sets)}',
    ].join(', ');
    void open(Muscle muscle) => _showDetail(context, muscle, _week(muscle));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Muscle map this week: $summary',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (side, front) in [('Front', true), ('Back', false)])
                Column(
                  children: [
                    SizedBox(
                      height: _figureHeight,
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
                              if (muscle != null) open(muscle);
                            },
                            child: CustomPaint(
                              size: constraints.biggest,
                              painter: _BodyPainter(
                                front: front,
                                fills: fills,
                                untrained: _untrained(colors),
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
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Tap a muscle for details · change vs last week',
          textAlign: TextAlign.center,
          style: labelStyle,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final muscle in Muscle.values)
              _MuscleChip(
                key: Key('muscle-${muscle.name}'),
                muscle: muscle,
                week: _week(muscle),
                color: fills[muscle]!,
                onPress: () => open(muscle),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (label, color) in [
              ('None', _untrained(colors)),
              ('<${MuscleVolume.targetMin}', _low),
              ('${MuscleVolume.targetMin}–${MuscleVolume.targetMax}', _optimal),
              ('>${MuscleVolume.targetMax}', _high),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Text(label, style: labelStyle),
                ],
              ),
            Text('sets / week', style: labelStyle),
          ],
        ),
      ],
    );
  }
}

Future<void> _showDetail(BuildContext context, Muscle muscle, MuscleWeek week) {
  const format = MuscleVolume.format;
  final advice = switch (week.level) {
    VolumeLevel.none =>
      'Not trained yet this week. Aim for '
          '${MuscleVolume.targetMin}–${MuscleVolume.targetMax} sets.',
    VolumeLevel.low =>
      '${format(week.missing)} more ${week.missing == 1 ? 'set' : 'sets'} to reach '
          '${MuscleVolume.targetMin} this week.',
    VolumeLevel.optimal =>
      'In the ${MuscleVolume.targetMin}–${MuscleVolume.targetMax} '
          'sets range. Nice work.',
    VolumeLevel.high =>
      'Above ${MuscleVolume.targetMax} sets. Make sure it recovers.',
  };
  return showAppDialog<void>(
    context: context,
    title: muscle.label,
    body: Column(
      key: Key('muscle-detail-${muscle.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${MuscleVolume.sets(week.sets)} this week · '
          '${format(week.previous)} last week',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(advice),
        if (week.exercises.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final row in week.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.primary ? row.exercise : '${row.exercise} (assists)',
                    ),
                  ),
                  Text(MuscleVolume.sets(row.sets)),
                ],
              ),
            ),
          if (week.exercises.any((row) => !row.primary))
            Text(
              'Assisting exercises count as half a set.',
              style: TextStyle(
                fontSize: 12,
                color: context.theme.colors.mutedForeground,
              ),
            ),
        ],
      ],
    ),
    actions: [
      FButton(
        variant: .outline,
        onPress: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

const _low = Color(0xFFE2A03F);
const _optimal = Color(0xFF22A06B);
const _high = Color(0xFFD9534F);

/// Greys and faded fills are flattened onto the card, so a part looks the
/// same whatever is painted beneath it (muscles sit on the torso).
Color _solid(FColors colors, Color color) =>
    Color.alphaBlend(color, colors.card);

Color _neutral(FColors colors) =>
    _solid(colors, colors.mutedForeground.withValues(alpha: .12));

Color _untrained(FColors colors) =>
    _solid(colors, colors.mutedForeground.withValues(alpha: .35));

/// Under target fades in as sets build up, so 8 sets reads closer to the
/// goal than 2.
Color _fill(FColors colors, double sets) => switch (MuscleVolume.level(sets)) {
  VolumeLevel.none => _untrained(colors),
  VolumeLevel.low => _solid(
    colors,
    _low.withValues(alpha: 0.35 + 0.65 * sets / MuscleVolume.targetMin),
  ),
  VolumeLevel.optimal => _optimal,
  VolumeLevel.high => _high,
};

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({
    required this.muscle,
    required this.week,
    required this.color,
    required this.onPress,
    super.key,
  });

  final Muscle muscle;
  final MuscleWeek week;
  final Color color;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final change = week.change;
    return FTappable(
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: color),
            const SizedBox(width: AppSpacing.xs),
            // Narrow screens and large text: shrink rather than overflow.
            Flexible(
              child: Text(
                '${muscle.label} ${MuscleVolume.format(week.sets)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (change != 0) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                change > 0
                    ? '+${MuscleVolume.format(change)}'
                    : '−${MuscleVolume.format(-change)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: change > 0 ? _optimal : colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
