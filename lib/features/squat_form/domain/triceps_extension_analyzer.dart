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
    start: 'Đưa tạ thẳng lên trên đầu để bắt đầu',
    ready: 'Sẵn sàng, hạ tạ ra sau đầu',
    go: 'Hạ tạ ra sau đầu',
    far: 'Tốt, duỗi tay lên',
    back: 'Duỗi thẳng tay lên',
    short: 'Hạ tạ sâu hơn ra sau đầu',
    incomplete: 'Duỗi thẳng tay hết trên đầu',
    faults: {'elbowFlare': 'Khép khuỷu tay lại'},
  );

  @override
  String? phaseLabel(SquatPhase phase) => switch (phase) {
    SquatPhase.findingBody => null,
    SquatPhase.standing => 'Tay thẳng',
    SquatPhase.descending => 'Đang hạ',
    SquatPhase.bottom => 'Sau đầu',
    SquatPhase.ascending => 'Đang duỗi',
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
            ? 'Đưa khuỷu tay lên cạnh đầu'
            : 'Lùi ra để thấy hai tay và đầu',
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
