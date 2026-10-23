import 'arm_rep_analyzer.dart';
import 'squat_analyzer.dart';

/// Bench, chair or bar dips, side-on to the camera. Progress is the elbow
/// bend of the arm nearer the camera: side-on, both the upper arm (swinging
/// back) and the forearm move in the image plane, so the angle reads true.
/// Arms straight (~172°) is 0, a 92° elbow 1.
class DipAnalyzer extends ArmRepAnalyzer {
  DipAnalyzer({
    super.minimumConfidence,
    super.smoothingFactor,
    super.transitionFrames,
    super.dropoutFrames,
  });

  /// Elbow ~164°: locked out at the top.
  @override
  double get fullStart => 0.1;

  /// Elbow ~148°: back up. Well clear of a missed lockout (~158°), so a
  /// set that never straightens still counts each dip.
  @override
  double get start => 0.3;

  /// Elbow ~140°: a real dip that stopped short.
  @override
  double get attempt => 0.4;

  /// Elbow ~108°: deep enough (upper arms near parallel to the floor).
  @override
  double get far => 0.8;

  @override
  String get incompleteFault => 'noLockout';

  static const _straightDegrees = 172.0;
  static const _rangeDegrees = 80.0;

  /// Shoulder width over torso length above which the user faces the
  /// camera too squarely to read the elbow (~0.76 facing, ~0 side-on;
  /// 0.45 is about 35° off side-on); back under [_sideOnAgainRatio] to
  /// read again, so standing on the line can't flicker.
  static const _facingRatio = .45;
  static const _sideOnAgainRatio = .38;
  double? _ratio;
  bool _facing = false;

  /// Consecutive frames read as facing: one outlier frame (the first one
  /// has no smoothing yet) must not tell a side-on user to turn.
  int _facingFrames = 0;
  static const _facingCueFrames = 3;

  @override
  ArmCues get cues => const ArmCues(
    start: 'Arms straight on the bars to start',
    ready: 'Ready, lower yourself',
    go: 'Lower yourself',
    far: 'Good, push up',
    back: 'Push up to straight arms',
    short: 'Go deeper, elbows to 90°',
    incomplete: 'Lock out fully at the top',
  );

  @override
  String? phaseLabel(SquatPhase phase) => switch (phase) {
    SquatPhase.findingBody => null,
    SquatPhase.standing => 'Top',
    SquatPhase.descending => 'Going down',
    SquatPhase.bottom => 'Depth reached',
    SquatPhase.ascending => 'Coming up',
  };

  @override
  void resetView() {
    _ratio = null;
    _facing = false;
    _facingFrames = 0;
  }

  @override
  ArmFrame read(Map<SquatJoint, SquatPoint> points, double alpha) {
    if (shoulderRatio(points) case final ratio?) {
      final smoothed = _ratio = _ratio == null
          ? ratio
          : _ratio! + alpha * (ratio - _ratio!);
      _facing = _facing
          ? smoothed > _sideOnAgainRatio
          : smoothed > _facingRatio;
    }
    _facingFrames = _facing ? _facingFrames + 1 : 0;
    if (_facingFrames >= _facingCueFrames) {
      return const ArmFrame.missed(
        'Turn side-on to the camera',
        missTone: CueTone.warn,
      );
    }
    // The nearer arm is the surer one; the far one is mostly guessed.
    ArmJoints? near;
    var nearConfidence = 0.0;
    for (final left in const [true, false]) {
      final arm = this.arm(points, left: left);
      if (arm == null) continue;
      final confidence =
          arm.shoulder.confidence + arm.elbow.confidence + arm.wrist.confidence;
      if (near == null || confidence > nearConfidence) {
        near = arm;
        nearConfidence = confidence;
      }
    }
    if (near == null) {
      return const ArmFrame.missed(
        'Step back so your arms and hips are in view',
      );
    }
    final elbow = angleDegrees(near.shoulder, near.elbow, near.wrist);
    return ArmFrame.seen((_straightDegrees - elbow) / _rangeDegrees);
  }
}
