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
  double? _hipOffsetSmoothed;
  int? _lastTimestampUs;
  int _missingFrames = 0;
  final _repRecords = <RepRecord>[];
  int? _repStartUs;
  int? _repBottomUs;
  int? _repAscentUs;
  int _repFrames = 0;
  int _repSagFrames = 0;
  int _repPikeFrames = 0;

  @override
  int get repetitions => _repetitions;
  @override
  String get countLabel => 'SỐ REP';

  @override
  List<RepRecord> get repRecords => _repRecords;

  @override
  void reset() {
    _phase = SquatPhase.findingBody;
    _candidate = null;
    _candidateFrames = 0;
    _repetitions = 0;
    _reachedDepth = false;
    _elbow = _height = _topHeight = _hipOffsetSmoothed = null;
    _lastTimestampUs = null;
    _missingFrames = 0;
    _repRecords.clear();
    _clearRep();
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
        _elbow = _height = _topHeight = _hipOffsetSmoothed = null;
        _clearRep();
      }
      final headOn =
          armVisible &&
          proneHeadOn(points, minimumConfidence: minimumConfidence);
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: !armVisible
            ? 'Lùi ra để thấy cánh tay'
            : headOn
            ? 'Xoay người nằm ngang so với camera'
            : 'Giữ thân nằm ngang để bắt đầu',
        // Lying on the floor the user can't read the screen: say it.
        tone: headOn ? CueTone.warn : CueTone.info,
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
    // well below it are mostly the start of a descent (flared elbows still
    // read as straight there), so they only pull it down slowly — enough
    // to follow a user who settles lower, not enough to drift each rep.
    if (_phase == SquatPhase.standing) {
      final top = _topHeight;
      _topHeight = _smooth(
        top,
        _height!,
        top == null || _height! > top * .95 ? .2 : .02,
      );
    }
    // Smoothed like the angles, so one jittery hip can't flash a warning.
    final rawHipOffset = _hipOffset(points, side);
    final hipOffset = _hipOffsetSmoothed = rawHipOffset == null
        ? null
        : _smooth(_hipOffsetSmoothed, rawHipOffset, alpha);
    final sagging = hipOffset != null && hipOffset > _hipTolerance;
    final piking = hipOffset != null && hipOffset < -_hipTolerance;
    _trackRep(timestampUs, sagging: sagging, piking: piking);
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
      _closeRep(timestampUs);
    }
    if (_phase == SquatPhase.standing) _clearRep();

    final hipsOk = !sagging && !piking;
    // No depth penalty: a shallow rep never reaches bottom, so it simply
    // doesn't count, and on the way up the arms straighten by definition.
    final score = hipsOk ? 100 : 70;

    final last = _repRecords.lastOrNull;
    final between = _phase == SquatPhase.standing && last != null
        ? betweenRepsCue(last)
        : null;
    final (cue, tone) = sagging
        ? ('Đừng để hông xệ', CueTone.warn)
        : piking
        ? ('Hạ hông thấp hơn', CueTone.warn)
        : _phase == SquatPhase.findingBody
        ? ('Duỗi thẳng tay để bắt đầu', CueTone.info)
        : _phase == SquatPhase.descending
        ? ('Hạ ngực thấp hơn', CueTone.info)
        : _phase == SquatPhase.bottom
        ? ('Đẩy lên', CueTone.good)
        : between != null
        ? (between.cue, between.tone)
        : _phase == SquatPhase.standing
        ? ('Sẵn sàng, bắt đầu hít đất', CueTone.info)
        : ('Giữ nhịp đều', CueTone.info);

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score,
      cue: cue,
      tone: tone,
      faultJoints: hipsOk
          ? const {}
          : const {SquatJoint.leftHip, SquatJoint.rightHip},
      nextRepTip: between?.tip,
      bodyVisible: true,
      kneeAngle: _elbow,
      label: _phase == SquatPhase.standing ? 'Ở đỉnh' : null,
    );
  }

  /// Samples hip faults while a rep is in progress (left straight arms,
  /// not yet back).
  void _trackRep(
    int? timestampUs, {
    required bool sagging,
    required bool piking,
  }) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    if (!inRep) return;
    _repStartUs ??= timestampUs ?? 0;
    _repFrames++;
    if (sagging) _repSagFrames++;
    if (piking) _repPikeFrames++;
    if (_phase == SquatPhase.bottom) _repBottomUs ??= timestampUs;
    if (_phase == SquatPhase.ascending) _repAscentUs ??= timestampUs;
  }

  void _closeRep(int? timestampUs) {
    if (_repFrames == 0) return;
    final start = _repStartUs, bottom = _repBottomUs, ascent = _repAscentUs;
    final hasTiming =
        timestampUs != null &&
        start != null &&
        bottom != null &&
        ascent != null;
    _repRecords.add(
      RepRecord(
        number: _repetitions,
        descentMs: hasTiming ? (bottom - start) ~/ 1000 : 0,
        ascentMs: hasTiming ? (timestampUs - ascent) ~/ 1000 : 0,
        faults: [
          if (_repSagFrames / _repFrames > 0.3) 'hipSag',
          if (_repPikeFrames / _repFrames > 0.3) 'hipPike',
        ],
      ),
    );
  }

  void _clearRep() {
    _repStartUs = _repBottomUs = _repAscentUs = null;
    _repFrames = _repSagFrames = _repPikeFrames = 0;
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
    final armLength =
        pointDistance(shoulder, elbow) + pointDistance(elbow, wrist);
    return inFrame && armLength > 0.12;
  }
}
