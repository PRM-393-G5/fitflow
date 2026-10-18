import 'dart:math' as math;

import 'squat_analyzer.dart';

/// Standing overhead press, facing the camera; needs only the upper body.
/// A rep goes from the rack (hands up at shoulder height) to arms straight
/// overhead and back. Progress is how high the wrists sit over the
/// shoulders as a share of arm length: both arms move in the plane facing
/// the camera, so this reads true even from a phone mounted up high.
///
/// Phases reuse [SquatPhase]: `standing` is the rack, `descending` pressing
/// up, `bottom` overhead (the far end of the rep), `ascending` lowering.
class ShoulderPressAnalyzer implements RepAnalyzer {
  ShoulderPressAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
    this.dropoutFrames = 8,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  /// Frames the arms may drop out of view before the rep in progress is
  /// dropped (hands overhead can leave the top of the frame briefly).
  final int dropoutFrames;

  /// Wrist lift (height over the shoulder / arm length) at or below which
  /// the hands are back at the shoulders: ~0.47 with a 90° elbow there.
  static const _rackLift = 0.6;

  /// Lift at or above which the press is overhead: ~1.0 locked out, ~0.93
  /// even with the elbows still bent to 140°.
  static const _topLift = 0.8;

  /// Elbow angle the weaker arm must reach overhead to count as locked out.
  static const lockoutDegrees = 160.0;

  /// Lift difference between the arms beyond which they're uneven.
  static const _unevenLift = 0.2;
  static const _unevenCueFrames = 3;

  /// Shoulder width over arm length below which the user stands side-on:
  /// ~0.65 facing the camera, ~0 side-on.
  static const _facingRatio = 0.35;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedTop = false;
  double? _leftLift;
  double? _rightLift;
  double? _elbow;
  int? _lastTimestampUs;
  int _missingFrames = 0;
  int _unevenStreak = 0;
  final _repRecords = <RepRecord>[];
  int? _repStartUs;
  int? _repTopUs;
  int? _repLowerUs;
  bool _repTimed = false;
  bool _repLocked = false;
  int _repLockFrames = 0;
  int _repFrames = 0;
  int _repUnevenFrames = 0;

  /// Pressed again before reaching the shoulders: a partial range rep.
  bool _repShortLower = false;

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
    _reachedTop = false;
    _leftLift = _rightLift = _elbow = null;
    _lastTimestampUs = null;
    _missingFrames = _unevenStreak = 0;
    _repRecords.clear();
    _clearRep();
  }

  @override
  void pauseTiming() {
    _lastTimestampUs = null;
    // The rep in progress would count the pause as press time.
    _repTimed = false;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final left = _arm(
      points,
      SquatJoint.leftShoulder,
      SquatJoint.leftElbow,
      SquatJoint.leftWrist,
    );
    final right = _arm(
      points,
      SquatJoint.rightShoulder,
      SquatJoint.rightElbow,
      SquatJoint.rightWrist,
    );
    final sideOn = _sideOn(points, left ?? right);
    if (left == null || right == null || sideOn) {
      if (++_missingFrames > dropoutFrames) {
        _phase = SquatPhase.findingBody;
        _candidate = null;
        _candidateFrames = 0;
        _reachedTop = false;
        _leftLift = _rightLift = _elbow = null;
        _unevenStreak = 0;
        _clearRep();
      }
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: sideOn ? 'Quay mặt về phía camera' : 'Lùi ra để thấy hai tay',
        // Side-on reps never count: worth saying, not just showing.
        tone: sideOn ? CueTone.warn : CueTone.info,
        bodyVisible: false,
      );
    }
    _missingFrames = 0;

    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : smoothingAlpha(timestampUs - previousUs);
    _leftLift = _smooth(_leftLift, left.lift, alpha);
    _rightLift = _smooth(_rightLift, right.lift, alpha);
    // Lockout is as good as the weaker arm.
    _elbow = _smooth(_elbow, math.min(left.elbow, right.elbow), alpha);
    final lift = (_leftLift! + _rightLift!) / 2;
    // Lockout is judged on the raw angle: a quick press with a short pause
    // overhead never lets the smoothed one catch up.
    final rawElbow = math.min(left.elbow, right.elbow);

    final before = _phase;
    final next = _classify(lift);
    if (_phase == SquatPhase.findingBody && next != SquatPhase.standing) {
      // Tracking starts at the shoulders (or arms down), never mid-press.
      _candidate = null;
      _candidateFrames = 0;
    } else {
      _transition(next);
    }
    if (before == SquatPhase.ascending && _phase == SquatPhase.bottom) {
      _repShortLower = true;
    }

    final uneven = (_leftLift! - _rightLift!).abs() > _unevenLift;
    _unevenStreak = uneven ? _unevenStreak + 1 : 0;
    final unevenLive = _unevenStreak >= _unevenCueFrames;
    _trackRep(timestampUs, uneven: uneven, rawElbow: rawElbow);
    if (_phase == SquatPhase.bottom) _reachedTop = true;
    if (_phase == SquatPhase.standing && _reachedTop) {
      _repetitions++;
      _reachedTop = false;
      _closeRep(timestampUs);
    }
    if (_phase == SquatPhase.standing) _clearRep();

    // Overhead the arms may still be straightening: only a hint. Once
    // lowering, a press that never locked out is final.
    final bentOverhead = _phase == SquatPhase.bottom && !_repLocked;
    final missedLockout = _phase == SquatPhase.ascending && !_repLocked;
    final shortLower = _repShortLower && _phase != SquatPhase.standing;
    var score = 100;
    if (unevenLive) score -= 15;
    if (shortLower) score -= 15;
    if (missedLockout) score -= 20;

    final last = _repRecords.lastOrNull;
    final between = _phase == SquatPhase.standing && last != null
        ? betweenRepsCue(last)
        : null;
    final (cue, tone) = unevenLive
        ? ('Đẩy đều hai tay', CueTone.warn)
        : shortLower
        ? ('Hạ khuỷu xuống ngang vai', CueTone.warn)
        : _phase == SquatPhase.findingBody
        ? ('Đưa tay lên ngang vai để bắt đầu', CueTone.info)
        : bentOverhead
        // Guidance at the top; the miss itself is said with the count.
        ? ('Đẩy thẳng tay lên hết', CueTone.info)
        : _phase == SquatPhase.descending
        ? ('Đẩy lên', CueTone.info)
        : _phase == SquatPhase.bottom
        ? ('Tốt, hạ xuống từ từ', CueTone.good)
        : _phase == SquatPhase.ascending
        ? ('Hạ xuống ngang vai', CueTone.info)
        : between != null
        ? (between.cue, between.tone)
        : lift < 0
        ? ('Đưa tay lên ngang vai để bắt đầu', CueTone.info)
        : ('Sẵn sàng, đẩy tay lên', CueTone.info);

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score,
      cue: cue,
      tone: tone,
      faultJoints: {
        if (unevenLive) ...const {
          SquatJoint.leftElbow,
          SquatJoint.rightElbow,
          SquatJoint.leftWrist,
          SquatJoint.rightWrist,
        },
        if (shortLower || missedLockout) ...const {
          SquatJoint.leftElbow,
          SquatJoint.rightElbow,
        },
      },
      nextRepTip: between?.tip,
      bodyVisible: true,
      kneeAngle: _elbow,
      label: switch (_phase) {
        SquatPhase.findingBody => null,
        SquatPhase.standing => lift < 0 ? 'Tay buông' : 'Ở vai',
        SquatPhase.descending => 'Đang đẩy',
        SquatPhase.bottom => 'Trên đầu',
        SquatPhase.ascending => 'Đang hạ',
      },
    );
  }

  double _smooth(double? previous, double value, double alpha) =>
      previous == null ? value : previous + alpha * (value - previous);

  SquatPhase _classify(double lift) {
    if (lift >= _topLift) return SquatPhase.bottom;
    if (lift <= _rackLift) return SquatPhase.standing;
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

  void _trackRep(
    int? timestampUs, {
    required bool uneven,
    required double rawElbow,
  }) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    if (!inRep) return;
    if (_repStartUs == null) {
      _repStartUs = timestampUs ?? 0;
      _repTimed = true;
    }
    _repFrames++;
    // Two straight frames in a row, so one jittery frame can't lock out.
    _repLockFrames = rawElbow >= lockoutDegrees ? _repLockFrames + 1 : 0;
    if (_repLockFrames >= 2) _repLocked = true;
    if (uneven) _repUnevenFrames++;
    if (_phase == SquatPhase.bottom) _repTopUs ??= timestampUs;
    if (_phase == SquatPhase.ascending) _repLowerUs ??= timestampUs;
  }

  void _closeRep(int? timestampUs) {
    if (_repFrames == 0) return;
    final start = _repStartUs, top = _repTopUs;
    // Sparse frames can jump from overhead straight to the rack.
    final lower = _repLowerUs ?? timestampUs;
    final hasTiming =
        _repTimed &&
        timestampUs != null &&
        start != null &&
        top != null &&
        lower != null;
    _repRecords.add(
      RepRecord(
        number: _repetitions,
        // Press up, then lower: the same fields as a squat's down and up.
        descentMs: hasTiming ? (top - start) ~/ 1000 : 0,
        ascentMs: hasTiming ? (timestampUs - lower) ~/ 1000 : 0,
        faults: [
          // First fault becomes the spoken tip: one arm lagging is the
          // more specific fix than "lock out", which it also causes.
          if (_repUnevenFrames / _repFrames > 0.3) 'unevenArms',
          if (!_repLocked) 'noLockout',
          if (_repShortLower) 'partialRange',
        ],
      ),
    );
  }

  void _clearRep() {
    _repStartUs = _repTopUs = _repLowerUs = null;
    _repLocked = false;
    _repFrames = _repUnevenFrames = _repLockFrames = 0;
    _repShortLower = false;
  }

  /// One arm's lift and elbow angle, or null when a joint is missing,
  /// unconfident or out of frame.
  _Arm? _arm(
    Map<SquatJoint, SquatPoint> points,
    SquatJoint shoulderJoint,
    SquatJoint elbowJoint,
    SquatJoint wristJoint,
  ) {
    final joints = [
      points[shoulderJoint],
      points[elbowJoint],
      points[wristJoint],
    ];
    if (joints.any((p) => p == null || p.confidence < minimumConfidence)) {
      return null;
    }
    final [shoulder!, elbow!, wrist!] = joints;
    if (!allInFrame([shoulder, elbow, wrist])) return null;
    final length = pointDistance(shoulder, elbow) + pointDistance(elbow, wrist);
    if (length < 0.05) return null;
    return (
      lift: (shoulder.y - wrist.y) / length,
      elbow: angleDegrees(shoulder, elbow, wrist),
      length: length,
    );
  }

  /// Shoulders overlapping relative to arm length: the user stands side-on,
  /// where one arm hides the other.
  bool _sideOn(Map<SquatJoint, SquatPoint> points, _Arm? arm) {
    final left = points[SquatJoint.leftShoulder];
    final right = points[SquatJoint.rightShoulder];
    if (arm == null || left == null || right == null) return false;
    if (math.min(left.confidence, right.confidence) < minimumConfidence) {
      return false;
    }
    return pointDistance(left, right) < arm.length * _facingRatio;
  }
}

typedef _Arm = ({double lift, double elbow, double length});
