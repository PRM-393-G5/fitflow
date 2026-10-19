import 'dart:convert';
import 'dart:math' as math;

/// Landmarks needed by the squat analyzer. This model deliberately has no
/// Flutter or ML Kit dependency, so the movement logic stays unit-testable.
enum SquatJoint {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftFoot,
  rightFoot,
  leftHeel,
  rightHeel,
}

/// A landmark in isotropic frame space (see `PoseFrame`): both axes share
/// one unit, the upright image height, so angles match the real scene.
class SquatPoint {
  const SquatPoint(this.x, this.y, {this.confidence = 1});

  final double x;
  final double y;
  final double confidence;
}

enum SquatPhase { findingBody, standing, descending, bottom, ascending }

/// How the live cue reads: [warn] is a form correction, [good] praise,
/// [info] neutral guidance.
enum CueTone { info, good, warn }

class SquatAnalysis {
  const SquatAnalysis({
    required this.phase,
    required this.repetitions,
    required this.score,
    required this.cue,
    required this.bodyVisible,
    this.tone = CueTone.info,
    this.faultJoints = const {},
    this.nextRepTip,
    this.kneeAngle,
    this.hipAngle,
    this.trunkAngle,
    this.label,
  });

  final SquatPhase phase;
  final int repetitions;
  final int score;
  final String cue;
  final bool bodyVisible;
  final CueTone tone;

  /// Joints behind the current fault, highlighted on the skeleton.
  final Set<SquatJoint> faultJoints;

  /// What to fix on the next rep, set between reps after a faulty one.
  final String? nextRepTip;
  final double? kneeAngle;
  final double? hipAngle;
  final double? trunkAngle;
  final String? label;

  String get phaseLabel =>
      label ??
      switch (phase) {
        SquatPhase.findingBody => 'Đang tìm tư thế',
        SquatPhase.standing => 'Sẵn sàng',
        SquatPhase.descending => 'Đang xuống',
        SquatPhase.bottom => 'Đủ sâu',
        SquatPhase.ascending => 'Đang lên',
      };
}

double angleDegrees(SquatPoint a, SquatPoint vertex, SquatPoint c) {
  final ax = a.x - vertex.x;
  final ay = a.y - vertex.y;
  final cx = c.x - vertex.x;
  final cy = c.y - vertex.y;
  final denominator = math.sqrt((ax * ax + ay * ay) * (cx * cx + cy * cy));
  if (denominator == 0) return 0;
  final cosine = ((ax * cx + ay * cy) / denominator).clamp(-1.0, 1.0);
  return math.acos(cosine) * 180 / math.pi;
}

/// Smoothing weight for a frame [dtUs] after the previous one: a 180 ms
/// time constant, so smoothing behaves the same at any frame rate.
double smoothingAlpha(int dtUs) => 1 - math.exp(-dtUs / 180000);

/// Every point inside the frame vertically.
bool allInFrame(Iterable<SquatPoint> points) =>
    points.every((point) => point.y >= 0 && point.y <= 1);

double pointDistance(SquatPoint a, SquatPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// A prone body (push-up, plank) pointing at the camera: the torso is so
/// foreshortened that the shoulders look far wider than it is long, so the
/// hip line and elbow bend can't be read. Standing upright facing the
/// camera the shoulders are ~0.8 torso lengths wide, well under the 1.2
/// needed here. False when the shoulders or a hip aren't confident.
bool proneHeadOn(
  Map<SquatJoint, SquatPoint> points, {
  required double minimumConfidence,
}) {
  final left = points[SquatJoint.leftShoulder];
  final right = points[SquatJoint.rightShoulder];
  final hip = points[SquatJoint.leftHip] ?? points[SquatJoint.rightHip];
  if (left == null || right == null || hip == null) return false;
  if ([left, right, hip].any((p) => p.confidence < minimumConfidence)) {
    return false;
  }
  final mid = SquatPoint((left.x + right.x) / 2, (left.y + right.y) / 2);
  return pointDistance(left, right) > pointDistance(mid, hip) * 1.2;
}

/// Knee angle (degrees) at or below which a squat enters `bottom`, so the
/// rep counts when the user stands back up.
const squatCountDepthDegrees = 105.0;

/// Knee angle at or below which depth is good. The live cue, live score and
/// the review's `shallowDepth` fault all use this, so they always agree.
const squatGoodDepthDegrees = 100.0;

/// Shortest controlled descent. Measured from the last frame seen standing
/// (158°) to reaching the count depth (105°) — the fast middle of the
/// lowering — so 360 ms is a whole descent of roughly 0.7 s.
const squatFastDescentMs = 360;

enum FormExercise {
  squat('Squat'),
  pushup('Push-up'),
  plank('Plank'),
  shoulderPress('Shoulder press');

  const FormExercise(this.label);
  final String label;

  /// The analyzer that can count a planned exercise, by name and kind, or
  /// null when none fits. Variants the analyzers can't judge are left out:
  /// split squats (one leg forward), side planks (not prone).
  static FormExercise? match(String name, {required bool timed}) {
    final lower = name.toLowerCase();
    if (timed) {
      return lower.contains('plank') && !lower.contains('side') ? plank : null;
    }
    if (RegExp(r'push[\s-]?ups?\b').hasMatch(lower)) return pushup;
    // Standing presses only: a bench press lies down out of view.
    if (RegExp(r'\b(shoulder|overhead|military)[\s-]?press\b|\bohp\b')
        .hasMatch(lower)) {
      return shoulderPress;
    }
    if (lower.contains('squat') && !lower.contains('split')) return squat;
    return null;
  }
}

/// Telemetry for one completed rep — the data behind "was that rep
/// clean?" Used by the post-set review and the AI coach prompt.
class RepRecord {
  const RepRecord({
    required this.number,
    this.minKneeAngle,
    required this.descentMs,
    required this.ascentMs,
    required this.faults,
  });

  final int number;

  /// Deepest knee angle of a squat; null for exercises judged otherwise.
  final double? minKneeAngle;
  final int descentMs;
  final int ascentMs;
  final List<String> faults;

  Map<String, Object> toJson() => {
    'rep': number,
    if (minKneeAngle case final angle?) 'minKneeAngleDeg': angle.round(),
    'descentMs': descentMs,
    'ascentMs': ascentMs,
    'faults': faults,
  };
}

/// Short coaching fix for each fault code, phrased to follow "Rep sau:".
const faultTips = {
  'shallowDepth': 'xuống sâu hơn',
  'kneeValgus': 'đẩy gối ra theo mũi chân',
  'forwardLean': 'giữ ngực thẳng',
  'heelsUp': 'giữ gót chạm sàn',
  'asymmetry': 'dồn đều lực hai chân',
  'fastEccentric': 'hạ người chậm hơn',
  'hipSag': 'siết bụng, giữ hông thẳng',
  'hipPike': 'hạ hông xuống thẳng hàng',
  'noLockout': 'đẩy thẳng tay lên hết',
  'unevenArms': 'đẩy đều hai tay',
  'partialRange': 'hạ khuỷu xuống ngang vai',
};

/// The between-reps cue after [last]: praise for a clean rep, otherwise
/// the fix for its first fault.
({String cue, CueTone tone, String? tip}) betweenRepsCue(RepRecord last) {
  final fault = last.faults.firstOrNull;
  if (fault == null) return (cue: 'Rep chuẩn!', tone: CueTone.good, tip: null);
  final tip = faultTips[fault] ?? fault;
  // Info, not warn: the tip is said once with the count, and must not hold
  // off a real warning on the next rep (see CueStabilizer).
  return (cue: 'Rep sau: $tip', tone: CueTone.info, tip: tip);
}

abstract interface class RepAnalyzer {
  SquatAnalysis analyze(Map<SquatJoint, SquatPoint> points, {int? timestampUs});
  int get repetitions;
  String get countLabel;
  List<RepRecord> get repRecords;
  void reset();

  /// Forgets the last frame timestamp so the next frame after a pause,
  /// camera switch or app background does not count the gap as elapsed.
  void pauseTiming();
}

class SquatAnalyzer implements RepAnalyzer {
  SquatAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
    this.dropoutFrames = 8,
    this.heelRiseFrames = 3,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  /// Frames the body may drop out of view mid-set before the phase resets.
  final int dropoutFrames;

  /// Consecutive frames the heel must stay raised to flag `heelsUp`.
  final int heelRiseFrames;

  /// Shoulder-to-ankle height needed to start tracking (frame units).
  static const _acquireBodySpan = 0.35;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedDepth = false;
  double? _knee;
  double? _hip;
  double? _trunk;
  int? _lastTimestampUs;
  int _missingFrames = 0;
  double? _standingSpan;
  final _repRecords = <RepRecord>[];
  int? _repStartUs;
  int? _lastStandingUs;
  int? _repBottomUs;
  int? _repAscentUs;
  double? _otherKnee;

  /// Consecutive frames the far leg was measured / missed. A flicker of a
  /// frame or two keeps its smoothing; a longer loss restarts it, and it is
  /// only compared once it has caught up — never a raw or stale angle
  /// against this leg's smoothed one.
  int _otherKneeSeenFrames = 0;
  int _otherKneeMissedFrames = 0;
  static const _otherKneeSettleFrames = 5;

  /// False once a pause interrupts the rep in progress: its timing would
  /// include the pause.
  bool _repTimed = false;
  double _repMinKnee = 180;
  SquatJoint? _heelJoint;
  double? _heelY;
  double? _repHeelBaseY;
  int _repHeelRiseFrames = 0;
  bool _repHeelsLifted = false;
  int _repFrames = 0;
  int _repValgusFrames = 0;
  int _repLeanFrames = 0;
  int _repAsymmetryFrames = 0;
  int _repAsymmetryJudged = 0;
  int _asymmetryStreak = 0;
  int _valgusStreak = 0;
  double? _viewRatio;
  double? _hipGap;
  int _turnedStreak = 0;
  static const _turnedCueFrames = 5;

  /// Consecutive faulty frames before a live cue shows: one jittery frame
  /// must never put a correction on screen, let alone say it aloud.
  static const _asymmetryCueFrames = 3;
  static const _valgusCueFrames = 3;

  /// On-screen hip width over torso length above which the user should
  /// turn further side-on: ~0.4 facing, ~0 side-on, 0.17 is about 25° off
  /// side-on, still clear of 15° off (~0.10). Beyond that the knee bend foreshortens fast (a 75° squat
  /// reads ~98° at 30° off), so depth is misjudged.
  static const _frontalViewRatio = 0.17;

  @override
  int get repetitions => _repetitions;
  SquatPhase get phase => _phase;
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
    _knee = _hip = _trunk = _otherKnee = _heelY = _viewRatio = _hipGap = null;
    _turnedStreak = 0;
    _heelJoint = null;
    _lastTimestampUs = _lastStandingUs = null;
    _missingFrames = 0;
    _standingSpan = null;
    _repRecords.clear();
    _clearRepTracking();
  }

  @override
  void pauseTiming() {
    _lastTimestampUs = _lastStandingUs = null;
    _repTimed = false;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    if (side == null || !_wholeBodyVisible(points, side)) {
      // Brief dropouts (a joint occluded at the bottom, a blurry frame)
      // keep the phase and the rep in progress; only a sustained loss
      // resets, so a user walking away can't complete a phantom rep.
      if (++_missingFrames > dropoutFrames) {
        _phase = SquatPhase.findingBody;
        _candidate = null;
        _candidateFrames = 0;
        _reachedDepth = false;
        _clearRepTracking();
      }
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: 'Lùi ra để thấy toàn thân',
        bodyVisible: false,
      );
    }

    final shoulder = points[side.$1]!;
    final hip = points[side.$2]!;
    final knee = points[side.$3]!;
    final ankle = points[side.$4]!;
    _missingFrames = 0;
    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : smoothingAlpha(timestampUs - previousUs);
    _knee = _smooth(_knee, angleDegrees(hip, knee, ankle), alpha);
    _hip = _smooth(_hip, angleDegrees(shoulder, hip, knee), alpha);
    _trunk = _smooth(
      _trunk,
      angleDegrees(shoulder, hip, SquatPoint(hip.x, hip.y - 1)),
      alpha,
    );

    final next = _classify(_knee!, _phase);
    if (_phase == SquatPhase.findingBody && next != SquatPhase.standing) {
      // Tracking starts from standing only: acquiring the body already
      // crouched would arm depth and count a phantom rep on the first stand.
      _candidate = null;
      _candidateFrames = 0;
    } else {
      _transition(next);
    }
    if (_phase == SquatPhase.standing) {
      _lastStandingUs = timestampUs;
      // Standing height calibrates how small the body may get at depth.
      _standingSpan = _smooth(_standingSpan, (ankle.y - shoulder.y).abs(), .2);
    }
    final otherRaw = _otherKneeAngle(points, side);
    if (otherRaw != null) {
      _otherKneeSeenFrames++;
      _otherKneeMissedFrames = 0;
      _otherKnee = _smooth(_otherKnee, otherRaw, alpha);
    } else {
      _otherKneeSeenFrames = 0;
      if (++_otherKneeMissedFrames > 2) _otherKnee = null;
    }
    _trackHeel(points, side, alpha);
    // Judged only while bending: standing in a wide stance the knees sit
    // inside the ankles without caving.
    final bending =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    final hipWidth = _hipWidth(points);
    // Signed and smoothed, so landmark jitter around a true zero averages
    // out instead of reading as hips apart.
    final leftHip = _reliable(points, SquatJoint.leftHip);
    final rightHip = _reliable(points, SquatJoint.rightHip);
    _hipGap = leftHip == null || rightHip == null
        ? null
        : _smooth(_hipGap, leftHip.x - rightHip.x, alpha);
    final hipGap = _hipGap;
    final legsSideOn = hipGap == null || hipGap.abs() < _sideOnHipWidth;
    final kneeTrackingOk = !bending || _kneeTracking(points, hipWidth);
    _valgusStreak = kneeTrackingOk ? 0 : _valgusStreak + 1;
    // The rep's fault share counts every frame; the live cue waits for a
    // sustained cave-in.
    final caving = _valgusStreak >= _valgusCueFrames;
    _trackRep(side, timestampUs, kneeTrackingOk, legsSideOn);
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
      _closeRep(timestampUs);
    }
    if (_phase == SquatPhase.standing) _clearRepTracking();
    final stableTrunk = _trunk! < 45;
    // Depth is judged by the deepest point of the rep so far: leaving the
    // bottom, the knee is past the depth line by definition.
    final repDeep = _repMinKnee <= squatGoodDepthDegrees;
    final heelsUp = _repHeelRiseFrames >= heelRiseFrames;
    final uneven = _asymmetryStreak >= _asymmetryCueFrames;
    final bottomUs = _repBottomUs;
    // Same timing rules as the rep's fastEccentric fault (see _closeRep).
    final fastRep =
        _repTimed &&
        (_phase == SquatPhase.bottom || _phase == SquatPhase.ascending) &&
        bottomUs != null &&
        _repStartUs != null &&
        (bottomUs - _repStartUs!) ~/ 1000 < squatFastDescentMs;
    final shallowRep = _phase == SquatPhase.ascending && !repDeep;
    _viewRatio = _smooth(
      _viewRatio,
      (hipWidth ?? 0) / math.max(pointDistance(shoulder, hip), 1e-6),
      alpha,
    );
    // Facing the camera the knee bend is invisible, so reps never count.
    _turnedStreak = _viewRatio! > _frontalViewRatio ? _turnedStreak + 1 : 0;
    // Sustained, so a jittery first frame (smoothing starts raw) can't
    // greet the user with a camera warning.
    final facingCamera =
        _turnedStreak >= _turnedCueFrames &&
        (_phase == SquatPhase.standing || _phase == SquatPhase.descending);

    var score = 100;
    if (caving) score -= 25;
    if (!stableTrunk) score -= 20;
    if (heelsUp) score -= 15;
    if (uneven) score -= 10;
    // Only once the user stands back up is a shallow rep final; at the
    // bottom they may still sink deeper.
    if (shallowRep) score -= 20;
    if (fastRep) score -= 10;

    final last = _repRecords.lastOrNull;
    final between = _phase == SquatPhase.standing && last != null
        ? betweenRepsCue(last)
        : null;
    // One cue at a time, most important first: injury risk, then camera
    // setup, then technique, then encouragement.
    final (cue, tone) = caving
        ? ('Giữ gối theo hướng mũi chân', CueTone.warn)
        : _phase == SquatPhase.findingBody
        ? ('Đứng thẳng để bắt đầu', CueTone.info)
        : !stableTrunk
        ? ('Giữ thân ổn định', CueTone.warn)
        : heelsUp
        ? ('Giữ gót chân chạm sàn', CueTone.warn)
        : uneven
        ? ('Dồn đều lực hai chân', CueTone.warn)
        : facingCamera
        ? ('Xoay nghiêng người về phía camera', CueTone.warn)
        : fastRep
        ? ('Hạ người chậm hơn', CueTone.warn)
        : _phase == SquatPhase.descending ||
              (_phase == SquatPhase.bottom && !repDeep)
        ? ('Xuống thêm một chút', CueTone.info)
        : _phase == SquatPhase.bottom
        ? ('Độ sâu tốt, đứng lên', CueTone.good)
        : between != null
        ? (between.cue, between.tone)
        : _phase == SquatPhase.standing
        ? ('Sẵn sàng, bắt đầu squat', CueTone.info)
        : ('Giữ nhịp đều', CueTone.info);

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score.clamp(0, 100),
      cue: cue,
      tone: tone,
      faultJoints: {
        if (caving || uneven) ...const {
          SquatJoint.leftKnee,
          SquatJoint.rightKnee,
        },
        if (!stableTrunk) ...const {
          SquatJoint.leftShoulder,
          SquatJoint.rightShoulder,
          SquatJoint.leftHip,
          SquatJoint.rightHip,
        },
        if (heelsUp) ...const {
          SquatJoint.leftHeel,
          SquatJoint.rightHeel,
          SquatJoint.leftAnkle,
          SquatJoint.rightAnkle,
        },
        if (shallowRep) ...const {SquatJoint.leftHip, SquatJoint.rightHip},
      },
      nextRepTip: between?.tip,
      bodyVisible: true,
      kneeAngle: _knee,
      hipAngle: _hip,
      trunkAngle: _trunk,
      label: _phase == SquatPhase.bottom && !repDeep ? 'Chưa đủ sâu' : null,
    );
  }

  double _smooth(double? previous, double value, [double? alpha]) =>
      previous == null
      ? value
      : previous + (alpha ?? smoothingFactor) * (value - previous);

  SquatPhase _classify(double knee, SquatPhase current) {
    if (knee >= 158) return SquatPhase.standing;
    if (knee <= squatCountDepthDegrees) return SquatPhase.bottom;
    if (current == SquatPhase.bottom || current == SquatPhase.ascending) {
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

  (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint)? _bestSide(
    Map<SquatJoint, SquatPoint> points,
  ) {
    const left = (
      SquatJoint.leftShoulder,
      SquatJoint.leftHip,
      SquatJoint.leftKnee,
      SquatJoint.leftAnkle,
      SquatJoint.leftFoot,
    );
    const right = (
      SquatJoint.rightShoulder,
      SquatJoint.rightHip,
      SquatJoint.rightKnee,
      SquatJoint.rightAnkle,
      SquatJoint.rightFoot,
    );
    double confidence(
      (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
    ) => [
      side.$1,
      side.$2,
      side.$3,
      side.$4,
    ].map((joint) => points[joint]?.confidence ?? 0).reduce(math.min);
    final leftConfidence = confidence(left);
    final rightConfidence = confidence(right);
    final best = leftConfidence >= rightConfidence ? left : right;
    return confidence(best) >= minimumConfidence ? best : null;
  }

  bool _wholeBodyVisible(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final joints = [
      side.$1,
      side.$2,
      side.$3,
      side.$4,
    ].map((joint) => points[joint]!).toList();
    if (!allInFrame(joints)) return false;
    final ys = [for (final joint in joints) joint.y];
    // Acquire only with the whole body standing tall in frame. Once
    // tracking, the body legitimately shrinks at the bottom of a squat, so
    // accept down to a fraction of the calibrated standing height.
    final minimumSpan = _phase == SquatPhase.findingBody
        ? _acquireBodySpan
        : math.max(0.15, (_standingSpan ?? _acquireBodySpan) * 0.4);
    return (ys.last - ys.first).abs() > minimumSpan;
  }

  /// Samples fault signals while a rep is in progress (started when the
  /// user leaves `standing`, closed by [_closeRep] on rep completion).
  void _trackRep(
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
    int? timestampUs,
    bool kneeTrackingOk,
    bool legsSideOn,
  ) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    // Start on any non-standing phase — frames can jump straight to
    // bottom when pose frames are sparse.
    if (inRep && _repStartUs == null) {
      // From the last frame seen standing: with sparse frames the rep can
      // appear straight at the bottom, which must read as slow, not 0 ms.
      _repStartUs = _lastStandingUs ?? timestampUs;
      _repTimed = true;
      _repMinKnee = _knee!;
      _repHeelBaseY = _heelY;
      _repHeelRiseFrames = 0;
      _repHeelsLifted = false;
      _repFrames = _repValgusFrames = _repLeanFrames = 0;
      _repAsymmetryFrames = _repAsymmetryJudged = 0;
    }
    if (_repStartUs == null || !inRep) return;
    _repFrames++;
    _repMinKnee = math.min(_repMinKnee, _knee!);
    if (!kneeTrackingOk) _repValgusFrames++;
    if (_trunk! > 45) _repLeanFrames++;
    // Both legs smoothed alike, so neither lags the other on a fast
    // descent. Only judged side-on (hips overlapping): from an angle the
    // two legs are foreshortened differently and always read as uneven.
    final otherKnee = _otherKneeSeenFrames >= _otherKneeSettleFrames
        ? _otherKnee
        : null;
    if (otherKnee != null && legsSideOn) {
      _repAsymmetryJudged++;
      if ((_knee! - otherKnee).abs() > 15) {
        _repAsymmetryFrames++;
        _asymmetryStreak++;
      } else {
        _asymmetryStreak = 0;
      }
    } else {
      // Unmeasured is not uneven: a stale streak would keep the cue up.
      _asymmetryStreak = 0;
    }
    _trackHeelRise();
    if (_phase == SquatPhase.bottom && _repBottomUs == null) {
      _repBottomUs = timestampUs;
    }
    if (_phase == SquatPhase.ascending && _repAscentUs == null) {
      _repAscentUs = timestampUs;
    }
  }

  /// Finalizes the in-progress rep into a [RepRecord]. A rep that never
  /// reached bottom is discarded by [_clearRepTracking] instead.
  void _closeRep(int? timestampUs) {
    if (_repStartUs == null || _repFrames == 0) return;
    final ascentUs = _repAscentUs;
    final bottomUs = _repBottomUs ?? ascentUs;
    final hasTiming =
        _repTimed &&
        timestampUs != null &&
        ascentUs != null &&
        bottomUs != null;
    // Descent ends on reaching the bottom, so a pause there isn't
    // mistaken for a slow, controlled lowering.
    final descentMs = hasTiming ? (bottomUs - _repStartUs!) ~/ 1000 : 0;
    final ascentMs = hasTiming ? (timestampUs - ascentUs) ~/ 1000 : 0;
    _repRecords.add(
      RepRecord(
        number: _repetitions,
        minKneeAngle: _repMinKnee,
        descentMs: descentMs,
        ascentMs: ascentMs,
        faults: [
          if (_repMinKnee > squatGoodDepthDegrees) 'shallowDepth',
          if (_repValgusFrames / _repFrames > 0.3) 'kneeValgus',
          if (_repLeanFrames / _repFrames > 0.3) 'forwardLean',
          if (_repHeelsLifted) 'heelsUp',
          // Needs most of the rep seen side-on: a few stray side-on frames
          // in an angled view are not enough to judge.
          if (_repAsymmetryJudged * 2 >= _repFrames &&
              _repAsymmetryFrames / _repAsymmetryJudged > 0.3)
            'asymmetry',
          if (hasTiming && descentMs < squatFastDescentMs) 'fastEccentric',
        ],
      ),
    );
  }

  /// Smoothed heel height, tracked every frame so a rep starts from a
  /// steady baseline: prefers the heel landmark, falls back to the ankle,
  /// and restarts whenever the tracked joint changes (side switch or heel
  /// confidence dropping).
  void _trackHeel(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
    double alpha,
  ) {
    final heelJoint = side.$4 == SquatJoint.leftAnkle
        ? SquatJoint.leftHeel
        : SquatJoint.rightHeel;
    final heel = points[heelJoint];
    final (joint, point) = heel != null && heel.confidence >= minimumConfidence
        ? (heelJoint, heel)
        : (side.$4, points[side.$4]!);
    if (joint != _heelJoint) {
      _heelJoint = joint;
      _heelY = point.y;
      // A baseline from another joint is meaningless.
      _repHeelBaseY = _repStartUs == null ? null : point.y;
      _repHeelRiseFrames = 0;
      return;
    }
    _heelY = _smooth(_heelY, point.y, alpha);
  }

  /// A lift must hold for [heelRiseFrames] frames so one jittery frame
  /// can't flag it.
  void _trackHeelRise() {
    final base = _repHeelBaseY;
    if (base == null) {
      _repHeelBaseY = _heelY;
      return;
    }
    if (base - _heelY! > 0.015) {
      if (++_repHeelRiseFrames >= heelRiseFrames) _repHeelsLifted = true;
    } else {
      _repHeelRiseFrames = 0;
    }
  }

  void _clearRepTracking() {
    _repStartUs = _repBottomUs = _repAscentUs = null;
    _repHeelBaseY = null;
    _repHeelRiseFrames = 0;
    _repHeelsLifted = false;
    _repMinKnee = 180;
    _repFrames = _repValgusFrames = _repLeanFrames = 0;
    _repAsymmetryFrames = _repAsymmetryJudged = _asymmetryStreak = 0;
  }

  /// Knee angle of the *other* leg, when its landmarks are confident —
  /// drives the left/right asymmetry fault.
  double? _otherKneeAngle(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
  ) {
    final joints = side.$3 == SquatJoint.leftKnee
        ? (SquatJoint.rightHip, SquatJoint.rightKnee, SquatJoint.rightAnkle)
        : (SquatJoint.leftHip, SquatJoint.leftKnee, SquatJoint.leftAnkle);
    final hip = points[joints.$1];
    final knee = points[joints.$2];
    final ankle = points[joints.$3];
    if (hip == null || knee == null || ankle == null) return null;
    if (math.min(hip.confidence, math.min(knee.confidence, ankle.confidence)) <
        minimumConfidence) {
      return null;
    }
    return angleDegrees(hip, knee, ankle);
  }

  SquatPoint? _reliable(Map<SquatJoint, SquatPoint> points, SquatJoint joint) {
    final point = points[joint];
    return point != null && point.confidence >= minimumConfidence
        ? point
        : null;
  }

  /// Hips at least this far apart on screen tell left from right well
  /// enough to judge knee valgus.
  static const _minHipWidth = 0.04;

  /// Hips closer than this mean the camera is squarely side-on (within
  /// ~10°): only then are both legs, each turned out with its toes, seen
  /// from a similar enough angle to compare their knees. At 15° off they
  /// already read uneven on a symmetric squat.
  static const _sideOnHipWidth = 0.015;

  /// On-screen distance between confident hips, or null.
  double? _hipWidth(Map<SquatJoint, SquatPoint> points) {
    final leftHip = _reliable(points, SquatJoint.leftHip);
    final rightHip = _reliable(points, SquatJoint.rightHip);
    if (leftHip == null || rightHip == null) return null;
    return (leftHip.x - rightHip.x).abs();
  }

  /// False on knee valgus: a knee caving *medially* (toward the body
  /// midline) past its ankle. Knees pushed out are fine. From an angled
  /// camera, knees travelling forward over the toes shift both legs the
  /// same way on screen — one leg reads as caving, the other as pushed out
  /// by the same amount. So a cave-in must show on the worse leg *and*
  /// stay positive on average across both legs, where that shared shift
  /// cancels: one leg caving still counts even with the other pushed out,
  /// a forward shift alone never does. Side-on views (hips overlapping)
  /// and unconfident legs are never flagged.
  bool _kneeTracking(Map<SquatJoint, SquatPoint> points, double? hipWidth) {
    if (hipWidth == null || hipWidth < _minHipWidth) return true;
    final leftHip = points[SquatJoint.leftHip]!;
    final rightHip = points[SquatJoint.rightHip]!;
    final leftKnee = _reliable(points, SquatJoint.leftKnee);
    final rightKnee = _reliable(points, SquatJoint.rightKnee);
    final leftAnkle = _reliable(points, SquatJoint.leftAnkle);
    final rightAnkle = _reliable(points, SquatJoint.rightAnkle);
    if (leftKnee == null ||
        rightKnee == null ||
        leftAnkle == null ||
        rightAnkle == null) {
      return true;
    }
    // +1 when the left leg's medial side (toward the right hip) is +x.
    final medial = rightHip.x >= leftHip.x ? 1 : -1;
    final left = (leftKnee.x - leftAnkle.x) * medial;
    final right = (rightKnee.x - rightAnkle.x) * -medial;
    final limit = hipWidth * 0.3;
    return math.max(left, right) <= limit || (left + right) / 2 <= limit / 4;
  }
}

/// Prompt contract for the AI post-set form review — sends per-rep
/// telemetry (or a plank's hold breakdown), asks for coach-style feedback.
abstract final class AiFormReviewPrompt {
  static const system = '''
You are a strength coach reviewing telemetry from a phone pose detector.
Rules:
- summary: 2-3 sentences on overall form quality this set.
- tips: 1-3 concrete coaching cues addressing the detected faults.
- Reference rep numbers when calling out specific reps.
- Fault codes: shallowDepth, kneeValgus (knees caved in), forwardLean,
  heelsUp, asymmetry (one leg dominant), fastEccentric (dropped too fast),
  hipSag (hips sagging below the body line), hipPike (hips too high),
  noLockout (arms not straightened overhead), unevenArms (one arm lagging),
  partialRange (pressed again before lowering to the shoulders).
- For a plank, judge how much of the hold was in good form.
- Be direct and encouraging; plain text only.''';

  static const schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'summary': {'type': 'string'},
      'tips': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['summary', 'tips'],
    'additionalProperties': false,
  };

  static String user({
    required String exercise,
    required List<RepRecord> reps,
    Map<String, Object>? hold,
  }) => hold != null
      ? 'Exercise: $exercise\nHold telemetry: ${jsonEncode(hold)}'
      : 'Exercise: $exercise\nRep telemetry: ${jsonEncode([for (final rep in reps) rep.toJson()])}';
}
