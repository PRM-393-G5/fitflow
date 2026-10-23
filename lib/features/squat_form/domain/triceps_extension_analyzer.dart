import 'arm_rep_analyzer.dart';
import 'squat_analyzer.dart';

/// Standing (or seated) overhead triceps extension, facing the camera:
/// elbows stay up by the head while the forearms lower the weight behind
/// it and press it back up. One arm or both.
///
/// Progress is how far the wrist has dropped from straight on along the
/// upper arm, in forearm lengths: arms straight ~0, a deep 60° elbow
/// ~1.1. Measured along the upper arm's own line, so elbows leaning
/// out read the same; the upper arm points up, square to a camera in
/// front, so its on-screen length is the true one and sizes the forearm.
class TricepsExtensionAnalyzer extends ArmRepAnalyzer {
  TricepsExtensionAnalyzer({
    super.minimumConfidence,
    super.smoothingFactor,
    super.transitionFrames,
    super.dropoutFrames,
  });

  // Thresholds measured on simulated sets with the phone at chest height,
  // 2 m away: the wrist going back behind the head also drops on screen
  // (further from the camera), so a bend reads deeper than the bare
  // geometry says. Elbow angles below are at that setup.

  /// Elbow ~160°: locked out overhead.
  @override
  double get fullStart => 0.15;

  /// Elbow ~140°: back up.
  @override
  double get start => 0.35;

  /// Elbow ~130°: a real lowering that stopped short.
  @override
  double get attempt => 0.45;

  /// Elbow ~100°: lowered deep enough behind the head.
  @override
  double get far => 0.74;

  @override
  String get incompleteFault => 'noLockout';

  /// The elbow sits this many upper-arm lengths out to the side of its
  /// shoulder (~30°): the elbows flare and the shoulders take the load.
  static const flareRatio = .5;

  /// Shoulder width over upper-arm length at or above which the user faces
  /// the camera enough for flaring to show (~1.27 square on, ~0.9 at 45°).
  static const _facingWidthRatio = .9;

  static const _forearmRatio = .9;

  /// Each raised arm's upper-arm length, measured with the arm straight.
  final _upperArm = <bool, double>{};

  @override
  ArmCues get cues => const ArmCues(
    start: 'Hold the weight straight overhead to start',
    ready: 'Ready, lower it behind your head',
    go: 'Lower it behind your head',
    far: 'Good, extend up',
    back: 'Straighten your arms up',
    short: 'Lower it deeper behind your head',
    incomplete: 'Lock out fully overhead',
    faults: {'elbowFlare': 'Keep your elbows in'},
  );

  @override
  String? phaseLabel(SquatPhase phase) => switch (phase) {
    SquatPhase.findingBody => null,
    SquatPhase.standing => 'Arms straight',
    SquatPhase.descending => 'Lowering',
    SquatPhase.bottom => 'Behind head',
    SquatPhase.ascending => 'Extending',
  };

  @override
  void resetView() => _upperArm.clear();

  @override
  ArmFrame read(Map<SquatJoint, SquatPoint> points, double alpha) {
    ({ArmJoints arm, double progress, bool flare})? lead;
    var armsSeen = false;
    for (final left in const [true, false]) {
      final arm = this.arm(points, left: left);
      if (arm == null) continue;
      armsSeen = true;
      final length = pointDistance(arm.shoulder, arm.elbow);
      // Elbow well above the shoulder: the arm is up in position. A
      // hanging arm (single-arm extensions) is ignored.
      if (arm.shoulder.y - arm.elbow.y < length * .5) continue;
      // Until tracking starts, the reference follows the current frame:
      // one taken from another distance would never let the arms read as
      // straight, and so never refresh.
      if (phase == SquatPhase.findingBody) _upperArm[left] = length;
      final reference = _upperArm[left] ?? length;
      final forearm = reference * _forearmRatio;
      // Forearm along the upper arm's direction (shoulder to elbow).
      final along =
          ((arm.wrist.x - arm.elbow.x) * (arm.elbow.x - arm.shoulder.x) +
              (arm.wrist.y - arm.elbow.y) * (arm.elbow.y - arm.shoulder.y)) /
          length;
      final rise = along / forearm;
      final progress = (1 - rise) / 1.5;
      if (progress <= start) {
        _upperArm[left] = _upperArm[left] == null
            ? length
            : _upperArm[left]! + .2 * (length - _upperArm[left]!);
      }
      final flare =
          _facing(points, reference) &&
          (arm.elbow.x - arm.shoulder.x).abs() > reference * flareRatio;
      // Lockout is as good as the weaker arm.
      if (lead == null || progress > lead.progress) {
        lead = (arm: arm, progress: progress, flare: flare);
      }
    }
    if (lead == null) {
      return ArmFrame.missed(
        armsSeen
            ? 'Raise your elbows beside your head'
            : 'Step back so your arms and head are in view',
      );
    }
    return ArmFrame.seen(
      lead.progress,
      fault: lead.flare ? 'elbowFlare' : null,
      faultJoints: armJoints(lead.arm),
    );
  }

  /// Both shoulders confidently seen and wide on screen.
  bool _facing(Map<SquatJoint, SquatPoint> points, double upperArm) {
    final left = points[SquatJoint.leftShoulder];
    final right = points[SquatJoint.rightShoulder];
    if (left == null || right == null) return false;
    if (left.confidence < minimumConfidence ||
        right.confidence < minimumConfidence) {
      return false;
    }
    return pointDistance(left, right) >= upperArm * _facingWidthRatio;
  }
}
