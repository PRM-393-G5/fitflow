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

abstract interface class RepAnalyzer {
  SquatAnalysis analyze(Map<SquatJoint, SquatPoint> points, {int? timestampUs});
  int get repetitions;
  String get countLabel;
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

  @override
  int get repetitions => _repetitions;
  SquatPhase get phase => _phase;
  @override
  String get countLabel => 'SỐ REP';

  @override
  void reset() {
    _phase = SquatPhase.findingBody;
    _candidate = null;
    _candidateFrames = 0;
    _repetitions = 0;
    _reachedDepth = false;
    _knee = _hip = _trunk = null;
    _lastTimestampUs = null;
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
    if (_phase == SquatPhase.bottom) _reachedDepth = true;
    if (_phase == SquatPhase.standing && _reachedDepth) {
      _repetitions++;
      _reachedDepth = false;
    }

    final kneeTrackingOk = _kneeTracking(points);
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
