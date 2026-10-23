import 'dart:math' as math;

import 'squat_analyzer.dart';

/// What one frame shows of an arm exercise: how far through the rep the
/// arms are, or why they can't be read.
class ArmFrame {
  const ArmFrame.seen(this.progress, {this.fault, this.faultJoints = const {}})
    : missCue = null,
      missTone = CueTone.info;

  const ArmFrame.missed(String this.missCue, {this.missTone = CueTone.info})
    : progress = null,
      fault = null,
      faultJoints = const {};

  /// 0 with the arms straight at the start of a rep, 1 at its far end
  /// (curled up, lowered behind the head, dipped down). May overshoot.
  final double? progress;

  /// A fault code seen on this frame (say `elbowDrift`); judged per rep.
  final String? fault;
  final Set<SquatJoint> faultJoints;
  final String? missCue;
  final CueTone missTone;
}

/// The words one arm exercise uses. Faults map a code to its live
/// warning.
class ArmCues {
  const ArmCues({
    required this.start,
    required this.ready,
    required this.go,
    required this.far,
    required this.back,
    required this.short,
    required this.incomplete,
    this.faults = const {},
  });

  /// Before tracking: how to get into the start position.
  final String start;

  /// At the start, between reps.
  final String ready;

  /// Moving toward the far end.
  final String go;

  /// At the far end (praise).
  final String far;

  /// Coming back to the start.
  final String back;

  /// Turned back before the far end: the rep didn't count.
  final String short;

  /// Went again before getting the arms straight.
  final String incomplete;
  final Map<String, String> faults;
}

/// Rep counting for the arm exercises (curls, triceps extensions, dips).
/// Subclasses read a frame into [ArmFrame.progress]; this runs the phases
/// on it, the same way the shoulder press does, and judges each rep.
///
/// Phases reuse [SquatPhase]: `standing` is the start (arms straight),
/// `descending` heading to the far end, `bottom` the far end, `ascending`
/// coming back. A rep counts when it gets back to the start after reaching
/// the far end.
abstract class ArmRepAnalyzer implements RepAnalyzer {
  ArmRepAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
    this.dropoutFrames = 8,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  /// Frames the arms may drop out of view before the rep in progress is
  /// dropped. At the far end it's longer: a dumbbell behind the head or a
  /// hand behind the hips hides the wrist for the whole pause there.
  final int dropoutFrames;

  /// Progress at or below which the arms are fully straight.
  double get fullStart;

  /// Progress at or below which the arms are back at the start.
  double get start;

  /// Progress reached without the far end: a real attempt that stopped
  /// short.
  double get attempt;

  /// Progress at or above which the rep reached its far end.
  double get far;

  /// The fault for a rep that went again before the arms got straight.
  String get incompleteFault;
  ArmCues get cues;

  /// The phase in this exercise's words; null while finding the body.
  String? phaseLabel(SquatPhase phase);

  /// Reads one frame. [alpha] is the frame's smoothing weight, for any
  /// view state the subclass smooths itself.
  ArmFrame read(Map<SquatJoint, SquatPoint> points, double alpha);

  /// Forgets the subclass's calibration (arm length, view), for whoever
  /// steps in next.
  void resetView();

  /// Consecutive faulty frames before a live warning shows.
  static const _faultCueFrames = 3;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedFar = false;
  double? _progress;
  int? _lastTimestampUs;
  int _missingFrames = 0;
  int _faultStreak = 0;
  int _lastScore = 100;
  String? _streakFault;
  final _repRecords = <RepRecord>[];

  /// The last attempt turned back before the far end; cleared when the
  /// next one starts.
  bool _short = false;

  /// Lowest progress since the last rep: whether the arms got straight
  /// before the next one.
  double _restLowest = double.infinity;

  int? _repStartUs;
  int? _repFarUs;
  int? _repBackUs;
  bool _repTimed = false;
  int _repFrames = 0;
  double _repMax = 0;
  final _repFaultFrames = <String, int>{};

  /// Went back toward the far end before getting straight: a partial rep.
  bool _repIncomplete = false;
  double _repLowestBack = double.infinity;
  int? _repLowestBackUs;

  SquatPhase get phase => _phase;
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
    _reachedFar = _short = false;
    _progress = null;
    _lastTimestampUs = null;
    _missingFrames = _faultStreak = 0;
    _streakFault = null;
    _restLowest = double.infinity;
    _repRecords.clear();
    _clearRep();
    resetView();
  }

  @override
  void pauseTiming() {
    _lastTimestampUs = null;
    // The rep in progress would count the pause as movement time.
    _repTimed = false;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final previousUs = _lastTimestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : smoothingAlpha(timestampUs - previousUs);
    final frame = read(points, alpha);
    final raw = frame.progress;
    if (raw == null) {
      final atFar = _phase == SquatPhase.bottom;
      final limit = atFar ? dropoutFrames * 4 : dropoutFrames;
      if (++_missingFrames > limit) {
        _phase = SquatPhase.findingBody;
        _candidate = null;
        _candidateFrames = 0;
        _reachedFar = _short = false;
        _progress = null;
        _faultStreak = 0;
        _restLowest = double.infinity;
        _clearRep();
        resetView();
      }
      // Hidden at the far end is expected (wrist behind the head or the
      // hips): keep coaching the rep rather than asking to step back.
      final holding = atFar && _missingFrames <= limit;
      return SquatAnalysis(
        phase: _phase,
        repetitions: _repetitions,
        // Nothing new to judge while hidden at the far end.
        score: holding ? _lastScore : 0,
        cue: holding ? cues.far : frame.missCue!,
        tone: holding ? CueTone.good : frame.missTone,
        bodyVisible: holding,
        label: phaseLabel(_phase),
      );
    }
    _missingFrames = 0;
    _lastTimestampUs = timestampUs;
    final progress = _progress = _smooth(_progress, raw, alpha);

    final before = _phase;
    final next = _classify(progress);
    if (_phase == SquatPhase.findingBody && next != SquatPhase.standing) {
      // Tracking starts with the arms straight, never mid-rep.
      _candidate = null;
      _candidateFrames = 0;
    } else {
      _transition(next);
    }
    if (before == SquatPhase.ascending &&
        (_phase == SquatPhase.descending || _phase == SquatPhase.bottom)) {
      // Went again without getting straight: the rep is partial, and this
      // one is judged on its own from where it turned.
      _repIncomplete = true;
      _repFrames = 0;
      _repFaultFrames.clear();
      _repStartUs = _repLowestBackUs ?? timestampUs;
      _repFarUs = _repBackUs = _repLowestBackUs = null;
      _repLowestBack = double.infinity;
    }

    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    final fault = inRep ? frame.fault : null;
    if (fault != null && fault == _streakFault) {
      _faultStreak++;
    } else {
      _streakFault = fault;
      _faultStreak = fault == null ? 0 : 1;
    }
    final liveFault = _faultStreak >= _faultCueFrames ? _streakFault : null;
    _trackRep(timestampUs, progress, raw, fault);

    if (_phase == SquatPhase.bottom) _reachedFar = true;
    if (_phase == SquatPhase.standing && _reachedFar) {
      _repetitions++;
      _reachedFar = false;
      _closeRep(timestampUs);
    } else if (_phase == SquatPhase.standing &&
        _repFrames > 0 &&
        _repMax >= attempt) {
      // Back at the start without reaching the far end: no rep, but the
      // user must hear why rather than see the count just not move.
      _short = true;
    }
    if (_phase == SquatPhase.standing) {
      _clearRep();
      _restLowest = math.min(_restLowest, raw);
    }

    final incompleteLive = _repIncomplete && _phase != SquatPhase.standing;
    var score = 100;
    if (liveFault != null) score -= 15;
    if (incompleteLive) score -= 15;
    _lastScore = score;

    final last = _repRecords.lastOrNull;
    final between = _phase == SquatPhase.standing && last != null
        ? betweenRepsCue(last)
        : null;
    final (cue, tone) = liveFault != null
        ? (cues.faults[liveFault] ?? liveFault, CueTone.warn)
        : incompleteLive
        ? (cues.incomplete, CueTone.warn)
        : _phase == SquatPhase.findingBody
        ? (cues.start, CueTone.info)
        : _phase == SquatPhase.descending
        ? (cues.go, CueTone.info)
        : _phase == SquatPhase.bottom
        ? (cues.far, CueTone.good)
        : _phase == SquatPhase.ascending
        ? (cues.back, CueTone.info)
        : _short
        ? (cues.short, CueTone.warn)
        : between != null
        ? (between.cue, between.tone)
        : (cues.ready, CueTone.info);

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score,
      cue: cue,
      tone: tone,
      faultJoints: {
        if (liveFault != null) ...frame.faultJoints,
        if (incompleteLive) ...const {
          SquatJoint.leftElbow,
          SquatJoint.rightElbow,
        },
      },
      nextRepTip: between?.tip,
      bodyVisible: true,
      label: phaseLabel(_phase),
    );
  }

  double _smooth(double? previous, double value, double alpha) =>
      previous == null ? value : previous + alpha * (value - previous);

  SquatPhase _classify(double progress) {
    if (progress >= far) return SquatPhase.bottom;
    if (progress <= start) return SquatPhase.standing;
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

  void _trackRep(int? timestampUs, double progress, double raw, String? fault) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    if (!inRep) return;
    if (_repStartUs == null) {
      _repStartUs = timestampUs ?? 0;
      _repTimed = true;
      _short = false;
      // Every rep must start straight: the rest before it shows whether
      // it did (the first one is acquired straight).
      if (_restLowest > fullStart && _repetitions > 0) _repIncomplete = true;
      _restLowest = double.infinity;
    }
    _repFrames++;
    _repMax = math.max(_repMax, progress);
    if (fault != null) {
      _repFaultFrames[fault] = (_repFaultFrames[fault] ?? 0) + 1;
    }
    if (_phase == SquatPhase.bottom) _repFarUs ??= timestampUs;
    if (_phase == SquatPhase.ascending) {
      _repBackUs ??= timestampUs;
      if (raw < _repLowestBack) {
        _repLowestBack = raw;
        _repLowestBackUs = timestampUs;
      }
    }
  }

  void _closeRep(int? timestampUs) {
    if (_repFrames == 0) return;
    final start = _repStartUs, farUs = _repFarUs;
    // Sparse frames can jump from the far end straight back to the start.
    final back = _repBackUs ?? timestampUs;
    final hasTiming =
        _repTimed &&
        timestampUs != null &&
        start != null &&
        farUs != null &&
        back != null;
    _repRecords.add(
      RepRecord(
        number: _repetitions,
        // Out to the far end, then back: the same fields as a squat's down
        // and up.
        descentMs: hasTiming ? (farUs - start) ~/ 1000 : 0,
        ascentMs: hasTiming ? (timestampUs - back) ~/ 1000 : 0,
        faults: [
          for (final MapEntry(key: code, value: frames)
              in _repFaultFrames.entries)
            if (frames / _repFrames > 0.3) code,
          if (_repIncomplete) incompleteFault,
        ],
      ),
    );
  }

  void _clearRep() {
    _repStartUs = _repFarUs = _repBackUs = null;
    _repLowestBackUs = null;
    _repLowestBack = double.infinity;
    _repMax = 0;
    _repFrames = 0;
    _repFaultFrames.clear();
    _repIncomplete = false;
  }

  /// One arm's shoulder, elbow and wrist, or null when one is missing,
  /// unconfident or out of frame.
  ArmJoints? arm(Map<SquatJoint, SquatPoint> points, {required bool left}) {
    final joints = left
        ? const [
            SquatJoint.leftShoulder,
            SquatJoint.leftElbow,
            SquatJoint.leftWrist,
          ]
        : const [
            SquatJoint.rightShoulder,
            SquatJoint.rightElbow,
            SquatJoint.rightWrist,
          ];
    final found = [for (final joint in joints) points[joint]];
    if (found.any((p) => p == null || p.confidence < minimumConfidence)) {
      return null;
    }
    final [shoulder!, elbow!, wrist!] = found;
    if (!allInFrame([shoulder, elbow, wrist])) return null;
    if (pointDistance(shoulder, elbow) < 0.03) return null;
    return (left: left, shoulder: shoulder, elbow: elbow, wrist: wrist);
  }

  /// Shoulder width over torso length (~0.76 facing the camera, ~0
  /// side-on), or null without both shoulders and hips.
  double? shoulderRatio(Map<SquatJoint, SquatPoint> points) {
    final joints = [
      points[SquatJoint.leftShoulder],
      points[SquatJoint.rightShoulder],
      points[SquatJoint.leftHip],
      points[SquatJoint.rightHip],
    ];
    if (joints.any((p) => p == null || p.confidence < minimumConfidence)) {
      return null;
    }
    final [ls!, rs!, lh!, rh!] = joints;
    final torso = pointDistance(
      SquatPoint((ls.x + rs.x) / 2, (ls.y + rs.y) / 2),
      SquatPoint((lh.x + rh.x) / 2, (lh.y + rh.y) / 2),
    );
    return torso > 0.02 ? pointDistance(ls, rs) / torso : null;
  }
}

typedef ArmJoints = ({
  bool left,
  SquatPoint shoulder,
  SquatPoint elbow,
  SquatPoint wrist,
});

/// The shoulder and elbow of [arm], highlighted for an elbow fault.
Set<SquatJoint> armJoints(ArmJoints arm) => arm.left
    ? const {SquatJoint.leftShoulder, SquatJoint.leftElbow}
    : const {SquatJoint.rightShoulder, SquatJoint.rightElbow};
