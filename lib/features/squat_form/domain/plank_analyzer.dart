import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Where a plank's time went, for the post-set review.
class HoldSummary {
  const HoldSummary({
    required this.trackedMs,
    required this.goodMs,
    required this.sagMs,
    required this.pikeMs,
  });

  /// Time spent in a supported plank position, good form or not.
  final int trackedMs;
  final int goodMs;
  final int sagMs;
  final int pikeMs;

  Map<String, Object> toJson() => {
    'trackedMs': trackedMs,
    'goodFormMs': goodMs,
    'hipSagMs': sagMs,
    'hipPikeMs': pikeMs,
  };
}

/// Plank hold timer: scores how straight the shoulder-hip-ankle line is and
/// accumulates the seconds the body holds good form.
class PlankAnalyzer implements RepAnalyzer {
  PlankAnalyzer({this.minimumConfidence = 0.55, this.maxFrameGapUs = 500000});

  final double minimumConfidence;

  /// Longest frame-to-frame gap credited as hold time. Larger gaps (pause,
  /// camera switch, app background) are skipped instead of counted.
  final int maxFrameGapUs;

  /// Hip offset from the shoulder-ankle line, in torso lengths, beyond which
  /// the hips count as sagging or piking. Matches the score's 70 cut-off.
  static const _hipTolerance = 0.15;

  int _goodHoldUs = 0;
  int _trackedUs = 0;
  int _sagUs = 0;
  int _pikeUs = 0;
  int? _lastTimestampUs;
  double? _offset;
  int? _plankUs;

  /// Out of the plank this long, the next hold starts fresh instead of
  /// blending in the hips from before; shorter gaps are detector glitches
  /// and keep the smoothing.
  static const _restartUs = 600000;

  HoldSummary get summary => HoldSummary(
    trackedMs: _trackedUs ~/ 1000,
    goodMs: _goodHoldUs ~/ 1000,
    sagMs: _sagUs ~/ 1000,
    pikeMs: _pikeUs ~/ 1000,
  );

  @override
  int get repetitions => _goodHoldUs ~/ 1000000;
  @override
  String get countLabel => 'GIÂY GIỮ';

  @override
  List<RepRecord> get repRecords => const [];

  @override
  void reset() {
    _goodHoldUs = _trackedUs = _sagUs = _pikeUs = 0;
    _lastTimestampUs = _plankUs = null;
    _offset = null;
  }

  @override
  void pauseTiming() {
    _lastTimestampUs = null;
    _offset = null;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    final rawOffset = side == null ? null : _hipOffset(points, side);
    if (side == null || rawOffset == null) {
      _lastTimestampUs = timestampUs;
      final inFrame = side != null && _inFrame(points, side);
      final headOn =
          inFrame && proneHeadOn(points, minimumConfidence: minimumConfidence);
      // Keep the accumulated hold: a dropped frame must not flash 0.
      return SquatAnalysis(
        phase: SquatPhase.findingBody,
        repetitions: repetitions,
        score: 0,
        cue: headOn
            ? 'Xoay người nằm ngang so với camera'
            : !inFrame
            ? 'Lùi ra để thấy toàn thân'
            : 'Vào tư thế plank để bắt đầu',
        // Lying on the floor the user can't read the screen: say it.
        tone: headOn ? CueTone.warn : CueTone.info,
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
    final plankUs = _plankUs;
    _plankUs = timestampUs;
    if (timestampUs != null &&
        plankUs != null &&
        timestampUs - plankUs > _restartUs) {
      _offset = null;
    }
    final previous = _offset;
    final offset = _offset = previous == null
        ? rawOffset
        : previousUs == null || timestampUs == null
        ? (previous + rawOffset) / 2
        // Smoothed so one jittery landmark can't flash a bad score or cost
        // hold time.
        : previous +
              smoothingAlpha(timestampUs - previousUs) * (rawOffset - previous);
    final score = (100 - offset.abs() * 200).round().clamp(0, 100);
    final good = score >= 70;
    final sagging = offset > _hipTolerance;
    final piking = offset < -_hipTolerance;
    if (previousUs != null && timestampUs != null) {
      final gapUs = timestampUs - previousUs;
      if (gapUs > 0 && gapUs <= maxFrameGapUs) {
        _trackedUs += gapUs;
        if (good) _goodHoldUs += gapUs;
        if (sagging) _sagUs += gapUs;
        if (piking) _pikeUs += gapUs;
      }
    }

    return SquatAnalysis(
      phase: SquatPhase.standing,
      repetitions: repetitions,
      score: score,
      cue: sagging
          ? 'Đừng để hông xệ'
          : piking
          ? 'Hạ hông thấp hơn'
          : 'Tốt lắm, giữ nguyên',
      tone: sagging || piking ? CueTone.warn : CueTone.good,
      faultJoints: sagging || piking
          ? const {SquatJoint.leftHip, SquatJoint.rightHip}
          : const {},
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
    if (!_inFrame(points, side)) return null;
    final spanX = ankle.x - shoulder.x;
    if (spanX.abs() < 0.15) return null;
    final torso = pointDistance(shoulder, hip);
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
    final margin = pointDistance(shoulder, points[side.$2]!) * 0.35;
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

  bool _inFrame(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint) side,
  ) => allInFrame([points[side.$1]!, points[side.$2]!, points[side.$3]!]);

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
