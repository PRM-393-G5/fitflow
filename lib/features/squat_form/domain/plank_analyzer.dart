import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Plank hold timer: scores how straight the shoulder-hip-ankle line is and
/// accumulates the seconds the body holds good form.
class PlankAnalyzer implements RepAnalyzer {
  PlankAnalyzer({this.minimumConfidence = 0.55});

  final double minimumConfidence;

  int _goodHoldUs = 0;
  int? _lastTimestampUs;

  @override
  int get repetitions => _goodHoldUs ~/ 1000000;
  @override
  String get countLabel => 'GIÂY GIỮ';

  @override
  List<RepRecord> get repRecords => const [];

  @override
  void reset() {
    _goodHoldUs = 0;
    _lastTimestampUs = null;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    final offset = side == null ? null : _hipOffset(points, side);
    if (side == null || offset == null) {
      _lastTimestampUs = timestampUs;
      return const SquatAnalysis(
        phase: SquatPhase.findingBody,
        repetitions: 0,
        score: 0,
        cue: 'Lùi ra để thấy toàn thân',
        bodyVisible: false,
      );
    }

    final score = (100 - offset.abs() * 500).round().clamp(0, 100);
    final good = score >= 70;
    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    if (good && previousUs != null && timestampUs != null) {
      _goodHoldUs += timestampUs - previousUs;
    }

    return SquatAnalysis(
      phase: SquatPhase.standing,
      repetitions: repetitions,
      score: score,
      cue: offset > 0.06
          ? 'Đừng để hông xệ'
          : offset < -0.06
          ? 'Hạ hông thấp hơn'
          : 'Tốt lắm, giữ nguyên',
      bodyVisible: true,
      hipAngle: offset * 100,
      label: 'Đang giữ plank',
    );
  }

  /// Signed distance of the hip from the shoulder-ankle line, normalized by
  /// torso length. Null when a joint is missing or the body is too upright.
  double? _hipOffset(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final shoulder = points[side.$1]!;
    final hip = points[side.$2]!;
    final ankle = points[side.$3]!;
    if ([shoulder, hip, ankle].any((joint) => joint.y < 0 || joint.y > 1)) {
      return null;
    }
    final spanX = ankle.x - shoulder.x;
    if (spanX.abs() < 0.15) return null;
    final expectedY =
        shoulder.y + (hip.x - shoulder.x) / spanX * (ankle.y - shoulder.y);
    return hip.y - expectedY;
  }

  (SquatJoint, SquatJoint, SquatJoint)? _bestSide(
    Map<SquatJoint, SquatPoint> points,
  ) {
    const left = (
      SquatJoint.leftShoulder,
      SquatJoint.leftHip,
      SquatJoint.leftAnkle,
    );
    const right = (
      SquatJoint.rightShoulder,
      SquatJoint.rightHip,
      SquatJoint.rightAnkle,
    );
    double confidence((SquatJoint, SquatJoint, SquatJoint) side) => [
      side.$1,
      side.$2,
      side.$3,
    ].map((joint) => points[joint]?.confidence ?? 0).reduce(math.min);
    final best = confidence(left) >= confidence(right) ? left : right;
    return confidence(best) >= minimumConfidence ? best : null;
  }
}
