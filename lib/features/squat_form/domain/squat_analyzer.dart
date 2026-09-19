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
}

class SquatPoint {
  const SquatPoint(this.x, this.y, {this.confidence = 1});

  final double x;
  final double y;
  final double confidence;
}

enum SquatPhase { findingBody, standing, descending, bottom, ascending }

class SquatAnalysis {
  const SquatAnalysis({
    required this.phase,
    required this.repetitions,
    required this.score,
    required this.cue,
    required this.bodyVisible,
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

enum FormExercise {
  squat('Squat'),
  pushup('Push-up'),
  plank('Plank');

  const FormExercise(this.label);
  final String label;
}

/// Telemetry for one completed rep — the data behind "was that rep
/// clean?" Used by the post-set review and the AI coach prompt.
class RepRecord {
  const RepRecord({
    required this.number,
    required this.minKneeAngle,
    required this.descentMs,
    required this.ascentMs,
    required this.faults,
  });

  final int number;
  final double minKneeAngle;
  final int descentMs;
  final int ascentMs;
  final List<String> faults;

  Map<String, Object> toJson() => {
    'rep': number,
    'minKneeAngleDeg': minKneeAngle.round(),
    'descentMs': descentMs,
    'ascentMs': ascentMs,
    'faults': faults,
  };
}

abstract interface class RepAnalyzer {
  SquatAnalysis analyze(Map<SquatJoint, SquatPoint> points, {int? timestampUs});
  int get repetitions;
  String get countLabel;
  List<RepRecord> get repRecords;
  void reset();
}

class SquatAnalyzer implements RepAnalyzer {
  SquatAnalyzer({
    this.minimumConfidence = 0.55,
    this.smoothingFactor = 0.35,
    this.transitionFrames = 2,
  });

  final double minimumConfidence;
  final double smoothingFactor;
  final int transitionFrames;

  SquatPhase _phase = SquatPhase.findingBody;
  SquatPhase? _candidate;
  int _candidateFrames = 0;
  int _repetitions = 0;
  bool _reachedDepth = false;
  double? _knee;
  double? _hip;
  double? _trunk;
  int? _lastTimestampUs;
  final _repRecords = <RepRecord>[];
  int? _repStartUs;
  int? _repAscentUs;
  double _repMinKnee = 180;
  double? _repAnkleBaseY;
  bool _repHeelsLifted = false;
  int _repFrames = 0;
  int _repValgusFrames = 0;
  int _repLeanFrames = 0;
  int _repAsymmetryFrames = 0;

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
    _knee = _hip = _trunk = null;
    _lastTimestampUs = null;
    _repRecords.clear();
    _repStartUs = _repAscentUs = null;
    _repAnkleBaseY = null;
    _repHeelsLifted = false;
    _repMinKnee = 180;
    _repFrames = _repValgusFrames = _repLeanFrames = _repAsymmetryFrames = 0;
  }

  @override
  SquatAnalysis analyze(
    Map<SquatJoint, SquatPoint> points, {
    int? timestampUs,
  }) {
    final side = _bestSide(points);
    if (side == null || !_wholeBodyVisible(points, side)) {
      _phase = SquatPhase.findingBody;
      _candidate = null;
      _candidateFrames = 0;
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
    final previousUs = _lastTimestampUs;
    _lastTimestampUs = timestampUs;
    final alpha = timestampUs == null || previousUs == null
        ? smoothingFactor
        : 1 - math.exp(-(timestampUs - previousUs) / 180000);
    _knee = _smooth(_knee, angleDegrees(hip, knee, ankle), alpha);
    _hip = _smooth(_hip, angleDegrees(shoulder, hip, knee), alpha);
    _trunk = _smooth(
      _trunk,
      angleDegrees(shoulder, hip, SquatPoint(hip.x, hip.y - 1)),
      alpha,
    );

    final next = _classify(_knee!, _phase);
    _transition(next);
    final kneeTrackingOk = _kneeTracking(points);
    _trackRep(points, side, timestampUs, ankle, kneeTrackingOk);
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
      _closeRep(timestampUs);
    }
    if (_phase == SquatPhase.standing) _clearRepTracking();
    final stableTrunk = _trunk! < 45;
    final deepEnough = _knee! <= 105;
    var score = 100;
    if (!kneeTrackingOk) score -= 25;
    if (!stableTrunk) score -= 20;
    if ((_phase == SquatPhase.bottom || _phase == SquatPhase.ascending) &&
        !deepEnough) {
      score -= 20;
    }

    final cue = !kneeTrackingOk
        ? 'Giữ gối theo hướng mũi chân'
        : !stableTrunk
        ? 'Giữ thân ổn định'
        : (_phase == SquatPhase.descending && _knee! > 105)
        ? 'Xuống thêm một chút'
        : _phase == SquatPhase.bottom
        ? 'Độ sâu tốt, đứng lên'
        : 'Giữ nhịp đều';

    return SquatAnalysis(
      phase: _phase,
      repetitions: _repetitions,
      score: score.clamp(0, 100),
      cue: cue,
      bodyVisible: true,
      kneeAngle: _knee,
      hipAngle: _hip,
      trunkAngle: _trunk,
    );
  }

  double _smooth(double? previous, double value, [double? alpha]) =>
      previous == null
      ? value
      : previous + (alpha ?? smoothingFactor) * (value - previous);

  SquatPhase _classify(double knee, SquatPhase current) {
    if (knee >= 158) return SquatPhase.standing;
    if (knee <= 102) return SquatPhase.bottom;
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
    final ys = [
      side.$1,
      side.$2,
      side.$3,
      side.$4,
    ].map((joint) => points[joint]!.y).toList();
    return ys.every((value) => value >= 0 && value <= 1) &&
        (ys.last - ys.first).abs() > 0.35;
  }

  /// Samples fault signals while a rep is in progress (started when the
  /// user leaves `standing`, closed by [_closeRep] on rep completion).
  void _trackRep(
    Map<SquatJoint, SquatPoint> points,
    (SquatJoint, SquatJoint, SquatJoint, SquatJoint, SquatJoint) side,
    int? timestampUs,
    SquatPoint ankle,
    bool kneeTrackingOk,
  ) {
    final inRep =
        _phase == SquatPhase.descending ||
        _phase == SquatPhase.bottom ||
        _phase == SquatPhase.ascending;
    // Start on any non-standing phase — frames can jump straight to
    // bottom when pose frames are sparse.
    if (inRep && _repStartUs == null) {
      _repStartUs = timestampUs;
      _repMinKnee = _knee!;
      _repAnkleBaseY = ankle.y;
      _repHeelsLifted = false;
      _repFrames = _repValgusFrames = _repLeanFrames = _repAsymmetryFrames = 0;
    }
    if (_repStartUs == null || !inRep) return;
    _repFrames++;
    _repMinKnee = math.min(_repMinKnee, _knee!);
    if (!kneeTrackingOk) _repValgusFrames++;
    if (_trunk! > 45) _repLeanFrames++;
    final otherKnee = _otherKneeAngle(points, side);
    if (otherKnee != null && (_knee! - otherKnee).abs() > 15) {
      _repAsymmetryFrames++;
    }
    if (_repAnkleBaseY! - ankle.y > 0.015) _repHeelsLifted = true;
    if (_phase == SquatPhase.ascending && _repAscentUs == null) {
      _repAscentUs = timestampUs;
    }
  }

  /// Finalizes the in-progress rep into a [RepRecord]. A rep that never
  /// reached bottom is discarded by [_clearRepTracking] instead.
  void _closeRep(int? timestampUs) {
    if (_repStartUs == null || _repFrames == 0) return;
    final ascentUs = _repAscentUs;
    final hasTiming = timestampUs != null && ascentUs != null;
    final descentMs = hasTiming ? (ascentUs - _repStartUs!) ~/ 1000 : 0;
    final ascentMs = hasTiming ? (timestampUs - ascentUs) ~/ 1000 : 0;
    _repRecords.add(
      RepRecord(
        number: _repetitions,
        minKneeAngle: _repMinKnee,
        descentMs: descentMs,
        ascentMs: ascentMs,
        faults: [
          if (_repMinKnee > 95) 'shallowDepth',
          if (_repValgusFrames / _repFrames > 0.3) 'kneeValgus',
          if (_repLeanFrames / _repFrames > 0.3) 'forwardLean',
          if (_repHeelsLifted) 'heelsUp',
          if (_repAsymmetryFrames / _repFrames > 0.3) 'asymmetry',
          if (hasTiming && descentMs < 800) 'fastEccentric',
        ],
      ),
    );
  }

  void _clearRepTracking() {
    _repStartUs = _repAscentUs = null;
    _repAnkleBaseY = null;
    _repHeelsLifted = false;
    _repMinKnee = 180;
    _repFrames = _repValgusFrames = _repLeanFrames = _repAsymmetryFrames = 0;
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

  bool _kneeTracking(Map<SquatJoint, SquatPoint> points) {
    bool side(SquatJoint knee, SquatJoint ankle, SquatJoint foot) {
      final k = points[knee];
      final a = points[ankle];
      final f = points[foot];
      if (k == null || a == null || f == null) return true;
      final footWidth = (f.x - a.x).abs().clamp(0.03, 0.3);
      return (k.x - a.x).abs() <= footWidth * 1.8;
    }

    return side(
          SquatJoint.leftKnee,
          SquatJoint.leftAnkle,
          SquatJoint.leftFoot,
        ) &&
        side(SquatJoint.rightKnee, SquatJoint.rightAnkle, SquatJoint.rightFoot);
  }
}

/// Prompt contract for the AI post-set form review — sends per-rep
/// telemetry, asks for coach-style feedback.
abstract final class AiFormReviewPrompt {
  static const system = '''
You are a lifting coach reviewing rep-by-rep telemetry from a phone
pose detector. Rules:
- summary: 2-3 sentences on overall form quality this set.
- tips: 1-3 concrete coaching cues addressing the detected faults.
- Reference rep numbers when calling out specific reps.
- Fault codes: shallowDepth, kneeValgus (knees caved in), forwardLean,
  heelsUp, asymmetry (one leg dominant), fastEccentric (dropped too fast).
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
  }) =>
      'Exercise: $exercise\nRep telemetry: ${jsonEncode([for (final rep in reps) rep.toJson()])}';
}
