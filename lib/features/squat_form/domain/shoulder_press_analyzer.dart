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

  /// Turned well away from the camera the horizontal upper arm
  /// foreshortens and the rack reads up to ~0.7, but the elbow still bends
  /// ~90°: with the elbow at or under [_rackElbowDegrees], a lift up to
  /// this still counts as the rack.
  static const _rackLiftBent = 0.72;
  static const _rackElbowDegrees = 110.0;

  /// A press reaching at least this lift, with the elbow opened past
  /// [_attemptElbowDegrees], without getting overhead was a real attempt
  /// that stopped short (around the forehead). The elbow rule keeps a rack
  /// misread from an angle (lift ~0.7, elbow ~115°) from counting.
  static const _attemptLift = 0.68;
  static const _attemptElbowDegrees = 120.0;

  /// Lift at or above which the press is overhead: ~1.0 locked out, ~0.93
  /// even with the elbows still bent to 140°.
  static const _topLift = 0.8;

  /// Elbow angle the weaker arm must reach overhead to count as locked out.
  static const lockoutDegrees = 160.0;

  /// Lift difference between the arms beyond which they're uneven.
  static const _unevenLift = 0.2;

  /// Shoulder ratio (see [_facingRatio]) the user must be at or above for
  /// unevenness to be judged: just past the facing limit the near and far
  /// arms foreshorten differently and would read uneven when they're not.
  static const _unevenFacingRatio = 0.6;
  static const _unevenCueFrames = 3;

  /// Shoulder width over torso length (shoulders to hips) below which the
  /// user is turned too far from the camera: ~0.76 facing, ~0.62 at 35°
  /// off, ~0.54 at 45°, ~0.46 at 60°, 0 side-on. From ~40° the arms
  /// foreshorten unevenly (reading as uneven) and then the rack misreads,
  /// so the user is asked to face the camera. Torso length doesn't change as the arms move, unlike
  /// arm length; the ratio is smoothed so jitter near the line can't flip
  /// it frame to frame.
  static const _facingRatio = 0.56;

  /// Once turned away, the ratio must climb back to this to count as
  /// facing again: hysteresis, so standing right on the limit (~45°) gives
  /// a steady "face the camera" rather than counting half the frames.
  static const _facingAgainRatio = 0.62;
  bool _turnedAway = false;
  int? _facingUs;

  /// Without hips in frame: shoulder width over the arm's on-screen length,
  /// ~0.65 facing, ~0 side-on. Looser, since arm length varies with pose.
  static const _facingRatioArm = 0.35;

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
  double _repMaxLift = 0;
  double _repMaxElbow = 0;
  double _repLowestLift = double.infinity;
  int? _repLowestUs;

  /// The last press turned back before getting overhead; cleared when the
  /// next press starts.
  bool _shortPress = false;

  /// Highest wrist (frame y) when last seen, to tell hands leaving the top
  /// of the frame from a lost detection.
  double? _wristY;
  double? _shoulderRatio;

  /// Wrists last seen this close to the top of the frame, while pressing
  /// or overhead, went out of the top rather than being lost.
  static const _frameTopMargin = 0.3;

  /// ...and already lifting off the shoulders (the rack reads ~0.47).
  static const _exitLift = 0.55;
  double? _lastLift;

  /// The hands left the frame during this rep: its lockout went unseen, so
  /// it isn't judged.
  bool _repOutOfFrame = false;

  /// The arms are currently out over the top of the frame.
  bool _outOverTop = false;

  /// The last rack frame had the hands at the shoulders with elbows bent,
  /// and whether the rep in progress started from there.
  bool _rackReady = false;
  bool _repFromRack = false;

  /// The last "rep" was a straight-arm raise from hanging arms.
  bool _notFromRack = false;
  static const _rackMinLift = 0.25;
  static const _rackReadyElbowDegrees = 125.0;
  double? _armRatio;

  /// Without hips: shoulder width over arm length at or above which the
  /// user is squarely facing (~0.67 facing, ~0.55 at 40° off).
  static const _unevenFacingRatioArm = 0.6;

  @override
  int get repetitions => _repetitions;
  @override
  String get countLabel => 'REPS';
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
    _shortPress = _notFromRack = _rackReady = _outOverTop = false;
    _shoulderRatio = _armRatio = _wristY = _lastLift = null;
    _turnedAway = false;
    _facingUs = null;
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
    // Side-on, the detector loses confidence in the hidden arm altogether,
    // shoulder included, so one arm seen alone reads as side-on too. A
    // hand merely out of the top of the frame keeps its shoulder.
    final hiddenShoulder =
        points[left == null
            ? SquatJoint.leftShoulder
            : SquatJoint.rightShoulder];
    final oneArmHidden =
        (left == null) != (right == null) &&
        (hiddenShoulder == null ||
            hiddenShoulder.confidence < minimumConfidence);
    final previousUs = _lastTimestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : smoothingAlpha(timestampUs - previousUs);
    // The facing check runs on every frame, side-on ones included, so it
    // keeps its own clock rather than the both-arms-seen one above.
    final facingUs = _facingUs;
    _facingUs = timestampUs;
    final facingAlpha = timestampUs == null || facingUs == null
        ? smoothingFactor
        : smoothingAlpha(timestampUs - facingUs);
    final sideOn = _sideOn(points, left ?? right, facingAlpha) || oneArmHidden;
    if (left == null || right == null || sideOn) {
      // Hands pressed up out of the top of the frame stay out for the
      // whole lockout pause: ride that out much longer than a glitch. A
      // quick press can leave before the phase even turns to pressing.
      // The shoulders must still be there: a lost pose is a glitch, and
      // a side-on user should hear about it, not be waited out.
      final shouldersSeen = [
        points[SquatJoint.leftShoulder],
        points[SquatJoint.rightShoulder],
      ].every((p) => p != null && p.confidence >= minimumConfidence);
      final exitedTop =
          !sideOn &&
          shouldersSeen &&
          _phase != SquatPhase.findingBody &&
          (_wristY ?? 1) < _frameTopMargin &&
          (_lastLift ?? 0) >= _exitLift;
      if (exitedTop) {
        // Hands gone over the top while lifting: they're overhead, whatever
        // the phase had caught up to (a quick press can leave still
        // reading as the rack). The rep counts once, back at the
        // shoulders; its lockout and tempo went unseen.
        _outOverTop = true;
        if (_phase != SquatPhase.bottom) {
          if (_repStartUs == null) {
            _repStartUs = timestampUs ?? 0;
            _repFromRack = _rackReady;
            _shortPress = _notFromRack = false;
          }
          _phase = SquatPhase.bottom;
          _candidate = null;
          _candidateFrames = 0;
        }
        _reachedTop = _repOutOfFrame = true;
        _repTimed = false;
        _repFrames = math.max(_repFrames, 1);
      }
      // Sticky until the arms are back: a dropped frame while the hands
      // are out mustn't fall back to the short limit.
      final limit = _phase == SquatPhase.bottom || _outOverTop
          ? dropoutFrames * 6
          : dropoutFrames;
      if (++_missingFrames > limit) {
        _phase = SquatPhase.findingBody;
        _candidate = null;
        _candidateFrames = 0;
        _reachedTop = false;
        _leftLift = _rightLift = _elbow = _wristY = _lastLift = null;
        _outOverTop = _rackReady = _turnedAway = false;
        // Whoever comes back may stand differently: no stale view state.
        _shoulderRatio = _armRatio = _facingUs = null;
        _unevenStreak = 0;
        _shortPress = false;
        _clearRep();
      }
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        score: 0,
        cue: sideOn ? 'Face the camera' : 'Step back so both arms are in view',
        // Side-on reps never count: worth saying, not just showing.
        tone: sideOn ? CueTone.warn : CueTone.info,
        bodyVisible: false,
        label: _label(null),
      );
    }
    _missingFrames = 0;
    _outOverTop = false;
    _wristY = math.min(left.wristY, right.wristY);
    _lastLift = (left.lift + right.lift) / 2;

    _lastTimestampUs = timestampUs;
    _leftLift = _smooth(_leftLift, left.lift, alpha);
    _rightLift = _smooth(_rightLift, right.lift, alpha);
    // Lockout is as good as the weaker arm.
    _elbow = _smooth(_elbow, math.min(left.elbow, right.elbow), alpha);
    final lift = (_leftLift! + _rightLift!) / 2;
    // Lockout is judged on the raw angle: a quick press with a short pause
    // overhead never lets the smoothed one catch up.
    final rawElbow = math.min(left.elbow, right.elbow);

    final before = _phase;
    final next = _classify(lift, _elbow!);
    if (_phase == SquatPhase.findingBody && next != SquatPhase.standing) {
      // Tracking starts at the shoulders (or arms down), never mid-press.
      _candidate = null;
      _candidateFrames = 0;
    } else {
      _transition(next);
    }
    if (before == SquatPhase.ascending && _phase == SquatPhase.bottom) {
      // Pressed again without reaching the shoulders: the rep is partial,
      // and this press is judged on its own from here.
      _repShortLower = true;
      _repLocked = false;
      _repLockFrames = _repFrames = _repUnevenFrames = 0;
      _repOutOfFrame = false;
      // This press started at the lowest point of the partial lowering.
      _repStartUs = _repLowestUs ?? timestampUs;
      _repTopUs = _repLowerUs = _repLowestUs = null;
      _repLowestLift = double.infinity;
    }

    // Only mid-rep: getting set, one hand can be up before the other.
    final uneven =
        (_phase == SquatPhase.descending ||
            _phase == SquatPhase.bottom ||
            _phase == SquatPhase.ascending) &&
        (_shoulderRatio != null
            ? _shoulderRatio! >= _unevenFacingRatio
            : (_armRatio ?? 1) >= _unevenFacingRatioArm) &&
        (_leftLift! - _rightLift!).abs() > _unevenLift;
    _unevenStreak = uneven ? _unevenStreak + 1 : 0;
    final unevenLive = _unevenStreak >= _unevenCueFrames;
    _trackRep(timestampUs, uneven: uneven, rawElbow: rawElbow, lift: lift);
    if (_phase == SquatPhase.bottom) _reachedTop = true;
    if (_phase == SquatPhase.standing && _reachedTop && !_repFromRack) {
      // Arms raised from hanging, never bent at the shoulders: a raise,
      // not a press. Say how to start rather than count it.
      _reachedTop = false;
      _notFromRack = true;
    } else if (_phase == SquatPhase.standing && _reachedTop) {
      _repetitions++;
      _reachedTop = false;
      _closeRep(timestampUs);
    } else if (_phase == SquatPhase.standing &&
        _repFrames > 0 &&
        _repMaxLift >= _attemptLift &&
        _repMaxElbow >= _attemptElbowDegrees) {
      // Back at the shoulders without getting overhead: no rep, but the
      // user must hear why rather than see the count just not move.
      _shortPress = true;
    }
    if (_phase == SquatPhase.standing) {
      _clearRep();
      // Ready to press once the hands have been up at the shoulders with
      // the elbows bent; only dropping the arms undoes it (the last rack
      // frame may already be opening into the press).
      if (lift >= _rackMinLift && _elbow! <= _rackReadyElbowDegrees) {
        _rackReady = true;
      } else if (lift < _rackMinLift) {
        _rackReady = false;
      }
    }

    // Overhead the arms may still be straightening: only a hint. Once
    // lowering, a press that never locked out is final.
    final bentOverhead = _phase == SquatPhase.bottom && !_repLocked;
    final missedLockout =
        _phase == SquatPhase.ascending && !_repLocked && !_repOutOfFrame;
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
        ? ('Press both arms evenly', CueTone.warn)
        : shortLower
        ? ('Lower your elbows to shoulder height', CueTone.warn)
        : _phase == SquatPhase.findingBody
        ? ('Bring your hands to shoulder height to start', CueTone.info)
        : bentOverhead
        // Guidance at the top; the miss itself is said with the count.
        ? ('Press all the way up', CueTone.info)
        : _phase == SquatPhase.descending
        ? ('Press up', CueTone.info)
        : _phase == SquatPhase.bottom
        ? ('Good, lower slowly', CueTone.good)
        : _phase == SquatPhase.ascending
        ? ('Lower to shoulder height', CueTone.info)
        : _notFromRack
        ? ('Bend your elbows, hands to shoulders, then press', CueTone.warn)
        : _shortPress
        ? ('Press as high as you can', CueTone.warn)
        : between != null
        ? (between.cue, between.tone)
        : lift < 0
        ? ('Bring your hands to shoulder height to start', CueTone.info)
        : ('Ready, press up', CueTone.info);

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
      label: _label(lift),
    );
  }

  /// Press wording for the phase; [lift] null when the arms aren't seen.
  String? _label(double? lift) => switch (_phase) {
    SquatPhase.findingBody => null,
    SquatPhase.standing => (lift ?? 0) < 0 ? 'Arms down' : 'At shoulders',
    SquatPhase.descending => 'Pressing',
    SquatPhase.bottom => 'Overhead',
    SquatPhase.ascending => 'Lowering',
  };

  double _smooth(double? previous, double value, double alpha) =>
      previous == null ? value : previous + alpha * (value - previous);

  SquatPhase _classify(double lift, double elbow) {
    if (lift >= _topLift) return SquatPhase.bottom;
    if (lift <= _rackLift ||
        (lift <= _rackLiftBent && elbow <= _rackElbowDegrees)) {
      return SquatPhase.standing;
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

  void _trackRep(
    int? timestampUs, {
    required bool uneven,
    required double rawElbow,
    required double lift,
  }) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    if (!inRep) return;
    if (_repStartUs == null) {
      _repStartUs = timestampUs ?? 0;
      _repTimed = true;
      _shortPress = _notFromRack = false;
      _repFromRack = _rackReady;
    }
    _repFrames++;
    _repMaxLift = math.max(_repMaxLift, lift);
    _repMaxElbow = math.max(_repMaxElbow, rawElbow);
    if (_phase == SquatPhase.ascending && lift < _repLowestLift) {
      _repLowestLift = lift;
      _repLowestUs = timestampUs;
    }
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
          if (!_repLocked && !_repOutOfFrame) 'noLockout',
          if (_repShortLower) 'partialRange',
        ],
      ),
    );
  }

  void _clearRep() {
    _repStartUs = _repTopUs = _repLowerUs = null;
    _repLocked = false;
    _repMaxLift = _repMaxElbow = 0;
    _repOutOfFrame = false;
    _repLowestLift = double.infinity;
    _repLowestUs = null;
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
      wristY: wrist.y,
    );
  }

  double? _torso(Map<SquatJoint, SquatPoint> points) {
    final ls = points[SquatJoint.leftShoulder];
    final rs = points[SquatJoint.rightShoulder];
    final lh = points[SquatJoint.leftHip];
    final rh = points[SquatJoint.rightHip];
    if (ls == null || rs == null || lh == null || rh == null) return null;
    if (!allInFrame([lh, rh]) ||
        [ls, rs, lh, rh].any((p) => p.confidence < minimumConfidence)) {
      return null;
    }
    final length = pointDistance(
      SquatPoint((ls.x + rs.x) / 2, (ls.y + rs.y) / 2),
      SquatPoint((lh.x + rh.x) / 2, (lh.y + rh.y) / 2),
    );
    return length > 0.02 ? length : null;
  }

  /// Shoulders narrow on screen: the user is turned away from the camera,
  /// so one arm foreshortens or hides the other.
  bool _sideOn(Map<SquatJoint, SquatPoint> points, _Arm? arm, double alpha) {
    final left = points[SquatJoint.leftShoulder];
    final right = points[SquatJoint.rightShoulder];
    if (left == null || right == null) return false;
    if (math.min(left.confidence, right.confidence) < minimumConfidence) {
      return false;
    }
    final width = pointDistance(left, right);
    final torso = _torso(points);
    if (torso != null) {
      final ratio = width / torso;
      final previous = _shoulderRatio;
      final smoothed = _shoulderRatio = _smooth(previous, ratio, alpha);
      _turnedAway = _turnedAway
          ? smoothed < _facingAgainRatio
          : smoothed < _facingRatio;
      return _turnedAway;
    }
    // Without hips the torso ratio can't be refreshed: don't let a stale
    // one keep gating unevenness; the arm ratio stands in.
    _shoulderRatio = null;
    if (arm == null) return false;
    final armRatio = _armRatio = _smooth(_armRatio, width / arm.length, alpha);
    // Same hysteresis as the torso path: arm length swings between rack
    // and lockout, which would flip a bare threshold frame to frame.
    _turnedAway = _turnedAway
        ? armRatio < _facingRatioArm + .05
        : armRatio < _facingRatioArm;
    return _turnedAway;
  }
}

typedef _Arm = ({double lift, double elbow, double length, double wristY});
