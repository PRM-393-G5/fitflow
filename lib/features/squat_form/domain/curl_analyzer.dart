import 'dart:math' as math;

import 'arm_rep_analyzer.dart';
import 'squat_analyzer.dart';

/// Standing curls (dumbbell, hammer, barbell), facing the camera or side-on.
/// Progress is how high the wrist has come up past the elbow, in forearm
/// lengths: hanging is -1, a 90° elbow 0, curled to the shoulder ~+0.8.
/// Only the vertical is used, so a forearm swinging toward the camera
/// reads true from the front.
///
/// The more curled arm leads each frame: both arms together count once,
/// alternating arms count each curl.
class CurlAnalyzer extends ArmRepAnalyzer {
  CurlAnalyzer({
    super.minimumConfidence,
    super.smoothingFactor,
    super.transitionFrames,
    super.dropoutFrames,
  });

  // Elbow angles below are with the phone at chest height, 2 m away;
  // from a phone up high looking down, a curl must come up further.

  /// Elbow ~150°: straight enough at the bottom.
  @override
  double get fullStart => 0.08;

  /// Elbow ~130°: back down.
  @override
  double get start => 0.2;

  /// Elbow ~95°: a real curl that stopped short.
  @override
  double get attempt => 0.5;

  /// Elbow ~75°: curled up.
  @override
  double get far => 0.8;

  @override
  String get incompleteFault => 'noFullExtension';

  /// The upper arm swung forward past this from hanging (its vertical drop
  /// under the shoulder shrinks to cos of it): the curl is using momentum
  /// or the shoulder rather than the biceps.
  static const driftDegrees = 35.0;

  /// The forearm is this share of the upper arm on an adult.
  static const _forearmRatio = .9;

  /// Each arm's upper-arm drop with the arm hanging: the reference for
  /// forearm length and elbow drift, refreshed at every rest.
  final _hangingDrop = <bool, double>{};

  @override
  ArmCues get cues => const ArmCues(
    start: 'Đứng thẳng, buông tay để bắt đầu',
    ready: 'Sẵn sàng, cuộn tạ lên',
    go: 'Cuộn lên',
    far: 'Tốt, hạ tạ từ từ',
    back: 'Hạ xuống, duỗi thẳng tay',
    short: 'Cuộn tạ lên cao hết',
    incomplete: 'Duỗi thẳng tay hết ở dưới',
    faults: {'elbowDrift': 'Giữ khuỷu tay sát người'},
  );

  @override
  String? phaseLabel(SquatPhase phase) => switch (phase) {
    SquatPhase.findingBody => null,
    SquatPhase.standing => 'Tay duỗi',
    SquatPhase.descending => 'Đang cuộn',
    SquatPhase.bottom => 'Đỉnh',
    SquatPhase.ascending => 'Đang hạ',
  };

  @override
  void resetView() => _hangingDrop.clear();

  @override
  ArmFrame read(Map<SquatJoint, SquatPoint> points, double alpha) {
    ({ArmJoints arm, double progress, bool drift})? lead;
    for (final left in const [true, false]) {
      final arm = this.arm(points, left: left);
      if (arm == null) continue;
      final drop = arm.elbow.y - arm.shoulder.y;
      if (drop <= 0) continue;
      // Until tracking starts, the reference follows the current frame:
      // one taken while stepping in close would make the arms never read
      // as hanging from further back, and so never refresh.
      if (phase == SquatPhase.findingBody) _hangingDrop[left] = drop;
      final reference = _hangingDrop[left] ?? drop;
      final forearm = reference * _forearmRatio;
      final rise = (arm.elbow.y - arm.wrist.y) / forearm;
      final progress = (rise + 1) / 1.8;
      if (progress <= start) {
        // Hanging: recalibrate, so stepping closer or further away
        // between reps doesn't skew the next one.
        _hangingDrop[left] = _hangingDrop[left] == null
            ? drop
            : _hangingDrop[left]! + .2 * (drop - _hangingDrop[left]!);
      }
      final drift =
          progress >= attempt &&
          drop < reference * math.cos(driftDegrees * math.pi / 180);
      if (lead == null || progress > lead.progress) {
        lead = (arm: arm, progress: progress, drift: drift);
      }
    }
    if (lead == null) return const ArmFrame.missed('Lùi ra để thấy hai tay');
    return ArmFrame.seen(
      lead.progress,
      fault: lead.drift ? 'elbowDrift' : null,
      faultJoints: armJoints(lead.arm),
    );
  }
}
