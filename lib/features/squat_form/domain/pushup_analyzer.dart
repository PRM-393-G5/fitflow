import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Push-up rep counter driven by elbow angle. Reps only count while the
/// torso is roughly horizontal, with a sagging/piking hip check when the
/// ankles are also visible.
class PushupAnalyzer implements RepAnalyzer {
  PushupAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
    this.maxTorsoTiltDegrees = 45,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  /// Steepest shoulder-hip line (degrees from horizontal) still treated as
  /// a push-up position.
  final double maxTorsoTiltDegrees;

  /// Hip offset from the shoulder-ankle line, in torso lengths, beyond which
  /// the hips count as sagging or piking.
  static const _hipTolerance = 0.15;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedDepth = false;
  double? _elbow;
  int? _lastTimestampUs;

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
    _elbow = null;
    _lastTimestampUs = null;
  }

  @override
  void pauseTiming() => _lastTimestampUs = null;

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    if (side == null || !_armVisible(points, side)) {
      // Drop the half-done rep too: an armed depth would otherwise count a
      // phantom rep the first time straight arms come back into view.
      _phase = SquatPhase.findingBody;
      _candidate = null;
      _candidateFrames = 0;
      _reachedDepth = false;
      _elbow = null;
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: 'Lùi ra để thấy cánh tay',
        bodyVisible: false,
      );
    }

    if (!_torsoHorizontal(points, side)) {
      // Bending the elbows while standing or kneeling upright must not
      // count: drop any half-done rep until the body is horizontal again.
      _phase = SquatPhase.findingBody;
      _candidate = null;
      _candidateFrames = 0;
      _reachedDepth = false;
      _elbow = null;
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: 'Giữ thân nằm ngang để bắt đầu',
        bodyVisible: false,
      );
    }

    final shoulder = points[side.$1]!;
    final elbow = points[side.$2]!;
    final wrist = points[side.$3]!;
    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : 1 - math.exp(-(timestampUs - previousUs) / 180000);
    _elbow = _smooth(_elbow, angleDegrees(shoulder, elbow, wrist), alpha);

    final next = _classify(_elbow!);
    _transition(next);
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
    }

    final hipOffset = _hipOffset(points, side);
    final hipsOk = hipOffset == null || hipOffset.abs() < _hipTolerance;
    var score = 100;
    if (!hipsOk) score -= 30;
    if ((_phase == SquatPhase.bottom || _phase == SquatPhase.ascending) &&
        _elbow! > 95) {
      score -= 15;
    }

    final cue = hipOffset != null && hipOffset > _hipTolerance
        ? 'Đừng để hông xệ'
        : hipOffset != null && hipOffset < -_hipTolerance
        ? 'Hạ hông thấp hơn'
        : (_phase == SquatPhase.descending && _elbow! > 95)
        ? 'Hạ ngực thấp hơn'
        : _phase == SquatPhase.bottom
        ? 'Đẩy lên'
        : 'Giữ nhịp đều';

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score.clamp(0, 100),
      cue: cue,
      bodyVisible: true,
      kneeAngle: _elbow,
      label: _phase == SquatPhase.standing ? 'Ở đỉnh' : null,
    );
  }

  double _smooth(double? previous, double value, double alpha) =>
      previous == null ? value : previous + alpha * (value - previous);

  SquatPhase _classify(double elbow) {
    if (elbow >= 150) return SquatPhase.standing;
    if (elbow <= 95) return SquatPhase.bottom;
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
    final wrist = points[side.$3]!;
    final inFrame = [
      side.$1,
      side.$2,
      side.$3,
    ].map((joint) => points[joint]!.y).every((y) => y >= 0 && y <= 1);
    final armLength = math.sqrt(
      math.pow(shoulder.x - wrist.x, 2) + math.pow(shoulder.y - wrist.y, 2),
    );
    return inFrame && armLength > 0.12;
  }
}
