import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Push-up rep counter. Depth is how far the shoulder drops toward the
/// hand, relative to its straight-arm height; the elbow angle alone misreads
/// side-on, where flared elbows foreshorten and a 70° bend can look like
/// 100°. Reps only count while the torso is roughly horizontal, with a
/// sagging/piking hip check when the ankles are also visible.
class PushupAnalyzer implements RepAnalyzer {
  PushupAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
    this.maxTorsoTiltDegrees = 45,
    this.dropoutFrames = 8,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  /// Steepest shoulder-hip line (degrees from horizontal) still treated as
  /// a push-up position.
  final double maxTorsoTiltDegrees;

  /// Frames the arm may drop out of view, or the torso leave horizontal,
  /// before the rep in progress is dropped. The bottom of a push-up, chest
  /// near the floor, is exactly where the detector loses landmarks.
  final int dropoutFrames;

  /// Hip offset from the shoulder-ankle line, in torso lengths, beyond which
  /// the hips count as sagging or piking.
  static const _hipTolerance = 0.15;

  /// Shoulder height over the wrist, as a share of the straight-arm height,
  /// at or below which the rep has reached depth: a 90° elbow counts even
  /// without a pause at the bottom, 100° does not.
  static const _depthRatio = 0.77;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedDepth = false;
  double? _elbow;
  double? _height;
  double? _topHeight;
  int? _lastTimestampUs;
  int _missingFrames = 0;

  @override
  int get repetitions => _repetitions;
  @override
  String get countLabel => 'SỐ REP';

  @override
  List<RepRecord> get repRecords => const [];

  @override
  void reset() {
    _phase = SquatPhase.findingBody;
    _candidate = null;
    _candidateFrames = 0;
    _repetitions = 0;
    _reachedDepth = false;
    _elbow = _height = _topHeight = null;
    _lastTimestampUs = null;
    _missingFrames = 0;
  }

  @override
  void pauseTiming() => _lastTimestampUs = null;

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    final armVisible = side != null && _armVisible(points, side);
    if (!armVisible || !_torsoHorizontal(points, side)) {
      // Brief dropouts keep the phase and the rep in progress; only a
      // sustained loss resets. The reset drops the half-done rep too: an
      // armed depth would otherwise count a phantom rep the first time
      // straight arms come back, and bending the elbows while standing or
      // kneeling upright must never count.
      if (++_missingFrames > dropoutFrames) {
        _phase = SquatPhase.findingBody;
        _candidate = null;
        _candidateFrames = 0;
        _reachedDepth = false;
        // The user may come back at another distance: recalibrate.
        _elbow = _height = _topHeight = null;
      }
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: armVisible
            ? 'Giữ thân nằm ngang để bắt đầu'
            : 'Lùi ra để thấy cánh tay',
        bodyVisible: false,
      );
    }
    _missingFrames = 0;

    final shoulder = points[side.$1]!;
    final elbow = points[side.$2]!;
    final wrist = points[side.$3]!;
    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : 1 - math.exp(-(timestampUs - previousUs) / 180000);
    _elbow = _smooth(_elbow, angleDegrees(shoulder, elbow, wrist), alpha);
    _height = _smooth(_height, wrist.y - shoulder.y, alpha);
    final topHeight = _topHeight;
    final depth = topHeight == null || topHeight <= 0
        ? null
        : _height! / topHeight;

    final next = _classify(_elbow!, depth);
    if (_phase == SquatPhase.findingBody && next != SquatPhase.standing) {
      // Tracking starts from straight arms only: acquiring the body at the
      // bottom would arm depth and count a phantom rep on the first push.
      _candidate = null;
      _candidateFrames = 0;
    } else {
      _transition(next);
    }
    // Straight-arm height calibrates depth, as in the squat's span. Frames
    // already well below it are the start of a descent (flared elbows still
    // read as straight there), not the top.
    if (_phase == SquatPhase.standing &&
        (_topHeight == null || _height! > _topHeight! * .95)) {
      _topHeight = _smooth(_topHeight, _height!, .2);
    }
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
    }

    final hipOffset = _hipOffset(points, side);
    final hipsOk = hipOffset == null || hipOffset.abs() < _hipTolerance;
    // No depth penalty: a shallow rep never reaches bottom, so it simply
    // doesn't count, and on the way up the arms straighten by definition.
    final score = hipsOk ? 100 : 70;

    final cue = hipOffset != null && hipOffset > _hipTolerance
        ? 'Đừng để hông xệ'
        : hipOffset != null && hipOffset < -_hipTolerance
        ? 'Hạ hông thấp hơn'
        : _phase == SquatPhase.descending
        ? 'Hạ ngực thấp hơn'
        : _phase == SquatPhase.bottom
        ? 'Đẩy lên'
        : 'Giữ nhịp đều';

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score,
      cue: cue,
      bodyVisible: true,
      kneeAngle: _elbow,
      label: _phase == SquatPhase.standing ? 'Ở đỉnh' : null,
    );
  }

  double _smooth(double? previous, double value, double alpha) =>
      previous == null ? value : previous + alpha * (value - previous);

  SquatPhase _classify(double elbow, double? depth) {
    if (elbow >= 150) return SquatPhase.standing;
    if (elbow <= 95 || (depth != null && depth <= _depthRatio)) {
      return SquatPhase.bottom;
    }
    if (_phase == SquatPhase.bottom || _phase == SquatPhase.ascending) {
      return SquatPhase.ascending;
    }
    return SquatPhase.descending;
  }

  void _transition(SquatPhase next) {
    if (next == _phase) {
      _candidate = null;
      _candidateFrames = 0;
      return;
    }
    if (_candidate != next) {
      _candidate = next;
      _candidateFrames = 1;
      return;
    }
    _candidateFrames++;
    if (_candidateFrames >= transitionFrames) {
      _phase = next;
      _candidate = null;
      _candidateFrames = 0;
    }
  }

  /// True when the hip is confident and the shoulder-hip line is within
  /// [maxTorsoTiltDegrees] of horizontal.
  bool _torsoHorizontal(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final shoulder = points[side.$1]!;
    final hip = points[side.$4];
    if (hip == null || hip.confidence < minimumConfidence) return false;
    final tilt =
        math.atan2((hip.y - shoulder.y).abs(), (hip.x - shoulder.x).abs()) *
        180 /
        math.pi;
    return tilt <= maxTorsoTiltDegrees;
  }

  /// Signed distance of the hip from the shoulder-ankle line, in torso
  /// lengths. Positive means the hips sag below the line, negative means
  /// they pike above it. Returns null when the torso joints are missing or
  /// the body is too upright to measure reliably.
  double? _hipOffset(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final shoulder = points[side.$1];
    final hip = points[side.$4];
    final ankle = points[side.$5];
    if (shoulder == null || hip == null || ankle == null) return null;
    if (ankle.confidence < minimumConfidence) return null;
    final spanX = ankle.x - shoulder.x;
    if (spanX.abs() < 0.15) return null;
    final torso = math.sqrt(
      math.pow(hip.x - shoulder.x, 2) + math.pow(hip.y - shoulder.y, 2),
    );
    if (torso == 0) return null;
    final expectedY =
        shoulder.y + (hip.x - shoulder.x) / spanX * (ankle.y - shoulder.y);
    return (hip.y - expectedY) / torso;
  }

  (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint)? _bestSide(
    Map<SquatJoint, SquatPoint> points,
  ) {
    const left = (
      SquatJoint.leftShoulder,
      SquatJoint.leftElbow,
      SquatJoint.leftWrist,
      SquatJoint.leftHip,
      SquatJoint.leftAnkle,
    );
    const right = (
      SquatJoint.rightShoulder,
      SquatJoint.rightElbow,
      SquatJoint.rightWrist,
      SquatJoint.rightHip,
      SquatJoint.rightAnkle,
    );
    double confidence(
      (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
    ) => [
      side.$1,
      side.$2,
      side.$3,
    ].map((joint) => points[joint]?.confidence ?? 0).reduce(math.min);
    final best = confidence(left) >= confidence(right) ? left : right;
    return confidence(best) >= minimumConfidence ? best : null;
  }

  bool _armVisible(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final shoulder = points[side.$1]!;
    final elbow = points[side.$2]!;
    final wrist = points[side.$3]!;
    final inFrame = [
      shoulder,
      elbow,
      wrist,
    ].every((point) => point.y >= 0 && point.y <= 1);
    // Upper arm plus forearm: the shoulder-wrist distance shrinks as the
    // elbow bends and would read as "arm too small" at every bottom.
    final armLength = _distance(shoulder, elbow) + _distance(elbow, wrist);
    return inFrame && armLength > 0.12;
  }

  static double _distance(SquatPoint a, SquatPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
}
