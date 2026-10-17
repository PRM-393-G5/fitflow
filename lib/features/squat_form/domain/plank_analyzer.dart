import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Plank hold timer: scores how straight the shoulder-hip-ankle line is and
/// accumulates the seconds the body holds good form.
class PlankAnalyzer implements RepAnalyzer {
  PlankAnalyzer({this.minimumConfidence = 0.55, this.maxFrameGapUs = 500000});

  final double minimumConfidence;

  /// Smoothing time constant for the hip offset, so one jittery landmark
  /// can't flash a bad score or cost hold time.
  static const _smoothingUs = 180000;

  /// Longest frame-to-frame gap credited as hold time. Larger gaps (pause,
  /// camera switch, app background) are skipped instead of counted.
  final int maxFrameGapUs;

  /// Hip offset from the shoulder-ankle line, in torso lengths, beyond which
  /// the hips count as sagging or piking. Matches the score's 70 cut-off.
  static const _hipTolerance = 0.15;

  int _goodHoldUs = 0;
  int? _lastTimestampUs;
  double? _offset;

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
    _offset = null;
  }

  @override
  void pauseTiming() => _lastTimestampUs = null;

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    final rawOffset = side == null ? null : _hipOffset(points, side);
    if (side == null || rawOffset == null) {
      _lastTimestampUs = timestampUs;
      // Keep the accumulated hold: a dropped frame must not flash 0.
      return SquatAnalysis(
        phase: SquatPhase.findingBody,
        repetitions: repetitions,
        score: 0,
        cue: 'Lùi ra để thấy toàn thân',
        bodyVisible: false,
      );
    }
    if (!_supported(points, side)) {
      _lastTimestampUs = timestampUs;
      return SquatAnalysis(
        phase: SquatPhase.findingBody,
        repetitions: repetitions,
        score: 0,
        cue: 'Chống khuỷu tay dưới vai',
        bodyVisible: false,
      );
    }

    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final previous = _offset;
    final offset = _offset = previous == null
        ? rawOffset
        : previousUs == null || timestampUs == null
        ? (previous + rawOffset) / 2
        : previous +
              (1 - math.exp(-(timestampUs - previousUs) / _smoothingUs)) *
                  (rawOffset - previous);
    final score = (100 - offset.abs() * 200).round().clamp(0, 100);
    final good = score >= 70;
    if (good && previousUs != null && timestampUs != null) {
      final gapUs = timestampUs - previousUs;
      if (gapUs > 0 && gapUs <= maxFrameGapUs) _goodHoldUs += gapUs;
    }

    return SquatAnalysis(
      phase: SquatPhase.standing,
      repetitions: repetitions,
      score: score,
      cue: offset > _hipTolerance
          ? 'Đừng để hông xệ'
          : offset < -_hipTolerance
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
    final torso = _distance(shoulder, hip);
    if (torso == 0) return null;
    final expectedY =
        shoulder.y + (hip.x - shoulder.x) / spanX * (ankle.y - shoulder.y);
    return (hip.y - expectedY) / torso;
  }

  /// Body held up on the arms: a confident elbow or wrist on the tracked
  /// side sits clearly below the shoulder. Rejects lying flat on the floor,
  /// where the arms rest level with the shoulders.
  bool _supported(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final shoulder = points[side.$1]!;
    final margin = _distance(shoulder, points[side.$2]!) * 0.35;
    final arm = side.$1 == SquatJoint.leftShoulder
        ? const [SquatJoint.leftElbow, SquatJoint.leftWrist]
        : const [SquatJoint.rightElbow, SquatJoint.rightWrist];
    return arm
        .map((joint) => points[joint])
        .any(
          (point) =>
              point != null &&
              point.confidence >= minimumConfidence &&
              point.y - shoulder.y > margin,
        );
  }

  static double _distance(SquatPoint a, SquatPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

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
