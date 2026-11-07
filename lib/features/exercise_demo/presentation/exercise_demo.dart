import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/muscle_body_map.dart';
import '../../../domain/models/exercise_motion.dart';
import '../../../domain/motion_rig.dart';
import 'anatomy_figure.dart';

/// The colour of the muscles a demo works.
const workedMuscleColor = Color(0xFFF97316);

/// The muscle map's colours for a demo; [onDark] for the camera's dark
/// overlays, whatever the app's theme.
class DemoPalette {
  const DemoPalette({
    required this.stage,
    required this.body,
    required this.muscle,
    required this.outline,
    required this.floor,
    required this.gear,
  });

  factory DemoPalette.of(BuildContext context) {
    final colors = context.theme.colors;
    return DemoPalette(
      stage: colors.card,
      body: muscleMapSolid(
        colors,
        colors.mutedForeground.withValues(alpha: .12),
      ),
      muscle: muscleMapUntrained(colors),
      outline: muscleMapSolid(
        colors,
        colors.mutedForeground.withValues(alpha: .45),
      ),
      floor: colors.border,
      gear: colors.mutedForeground,
    );
  }

  static const onDark = DemoPalette(
    stage: Color(0xFF151A22),
    body: Color(0xFF2A3240),
    muscle: Color(0xFF465166),
    outline: Color(0xFF5B6880),
    floor: Color(0xFF2A3240),
    gear: Color(0xFF9AA6B8),
  );

  final Color stage;
  final Color body;
  final Color muscle;
  final Color outline;
  final Color floor;
  final Color gear;
}

/// The muscle map's body doing [motion] on a loop, the muscles it works
/// lit up, with the current cue on top. [showAngles] adds a switch between
/// the angles the motion reads well from (side, front, back).
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    required this.motion,
    this.showCue = true,
    this.showAngles = false,
    this.onDark = false,
    super.key,
  });

  final ExerciseMotion motion;
  final bool showCue;
  final bool showAngles;

  /// Drawn on a dark overlay (the camera view), in [DemoPalette.onDark].
  final bool onDark;

  /// Whether demos play. Tests switch this off (see
  /// test/flutter_test_config.dart): a looping animation never lets
  /// `pumpAndSettle` settle. Stopped demos, like ones under the system's
  /// reduce-motion setting, hold their second keyframe (the bottom of a
  /// squat), which shows more than the start.
  static bool autoplay = true;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this)
    ..addListener(_trackKeyframe);
  late final _keyframe = ValueNotifier(0);
  late MotionAngle _angle = MotionAngle.of(widget.motion.view);
  bool _reduceMotion = false;

  double get _ms => _controller.value * widget.motion.loopMs;

  void _trackKeyframe() =>
      _keyframe.value = widget.motion.frameAt(_ms).keyframe;

  void _play() {
    final motion = widget.motion;
    final loop = motion.loopMs;
    if (ExerciseDemo.autoplay && !_reduceMotion && loop > 0) {
      _controller.duration = Duration(milliseconds: loop);
      if (!_controller.isAnimating) _controller.repeat();
      return;
    }
    _controller.stop();
    final still = motion.keyframes.length > 1 ? 1 : 0;
    var start = 0;
    for (final frame in motion.keyframes.take(still)) {
      start += frame.holdMs + frame.moveMs;
    }
    _controller.value = loop == 0 ? 0 : start / loop;
    _trackKeyframe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _play();
  }

  @override
  void didUpdateWidget(ExerciseDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion.id != widget.motion.id) {
      _angle = MotionAngle.of(widget.motion.view);
    }
    if (oldWidget.motion != widget.motion) {
      _controller.stop();
      _play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyframe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion;
    final palette = widget.onDark
        ? DemoPalette.onDark
        : DemoPalette.of(context);
    final angles = MotionRig.angles(motion);
    final angle = angles.contains(_angle) ? _angle : angles.first;
    final switchable = widget.showAngles && angles.length > 1;
    return Semantics(
      label: 'Demo of ${motion.name}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: palette.stage,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: widget.showCue ? 30 : 0,
                  bottom: switchable ? 34 : 0,
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: AnatomyPainter(
                      motion: motion,
                      progress: _controller,
                      angle: angle,
                      worked: motion.muscles,
                      body: palette.body,
                      muscle: palette.muscle,
                      workedColor: workedMuscleColor,
                      outline: palette.outline,
                      floor: palette.floor,
                      gear: palette.gear,
                    ),
                  ),
                ),
              ),
              if (widget.showCue)
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: ValueListenableBuilder(
                    valueListenable: _keyframe,
                    builder: (context, index, _) {
                      final cue = motion.keyframes[index].cue;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: cue == null
                            ? const SizedBox.shrink()
                            : Align(
                                key: ValueKey(index),
                                alignment: Alignment.centerLeft,
                                child: _CuePill(cue),
                              ),
                      );
                    },
                  ),
                ),
              if (switchable)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: _AngleSwitch(
                      angles: angles,
                      selected: angle,
                      onDark: widget.onDark,
                      onChanged: (value) => setState(() => _angle = value),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuePill extends StatelessWidget {
  const _CuePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCC111827),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        text,
        key: const Key('exercise-demo-cue'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Side · Front · Back, as small pills.
class _AngleSwitch extends StatelessWidget {
  const _AngleSwitch({
    required this.angles,
    required this.selected,
    required this.onDark,
    required this.onChanged,
  });

  final List<MotionAngle> angles;
  final MotionAngle selected;
  final bool onDark;
  final ValueChanged<MotionAngle> onChanged;

  static String _label(MotionAngle angle) => switch (angle) {
    MotionAngle.side => 'Side',
    MotionAngle.front => 'Front',
    MotionAngle.back => 'Back',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF222A36) : colors.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final angle in angles)
              Semantics(
                button: true,
                selected: angle == selected,
                child: FTappable(
                  key: Key('demo-angle-${angle.name}'),
                  onPress: () => onChanged(angle),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: angle == selected
                          ? (onDark ? const Color(0xFF3A4556) : colors.card)
                          : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _label(angle),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: angle == selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: onDark
                            ? Colors.white
                            : angle == selected
                            ? colors.foreground
                            : colors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
