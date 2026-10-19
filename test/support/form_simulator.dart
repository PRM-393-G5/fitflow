import 'dart:math' as math;

import 'package:prm/features/squat_form/domain/form_feedback.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

/// Synthetic pose generator for the form-check analyzers: a 3D skeleton
/// with real limb lengths, projected through a camera at any angle, with
/// ML Kit-like landmark jitter, outliers, dropped frames and inference
/// latency. Lets tests replay whole sets of good and faulty reps.
class V3 {
  const V3(this.x, this.y, this.z);

  /// Metres. x: the way the body faces (squat) or toward the head (prone);
  /// y: up; z: toward the body's left.
  final double x, y, z;

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double get length => math.sqrt(x * x + y * y + z * z);
}

typedef Pose3 = Map<SquatJoint, V3>;

double _rad(double degrees) => degrees * math.pi / 180;

/// Adult proportions (~1.72 m tall).
abstract final class Body {
  static const shank = .43;
  static const thigh = .43;
  static const torso = .50;
  static const hipHalf = .10;
  static const shoulderHalf = .19;
  static const upperArm = .30;
  static const forearm = .27;
  static const ankleHeight = .08;
  static const heelBack = .06;
  static const footFront = .17;
}

/// Phone camera looking at the subject. [azimuthDeg] 90 = camera on the
/// body's left side (side-on), 0 = straight in front. [pitchDeg] tilts it
/// down, as when the phone sits up high (a shelf, a projector).
class SimCamera {
  const SimCamera({
    this.azimuthDeg = 90,
    this.pitchDeg = 0,
    this.scale = .436,
    this.distanceM = 3,
    this.aspect = 480 / 720,
    this.floorY = .92,
    this.centerU = 0,
    this.aimHeightM = 1,
  });

  final double azimuthDeg;
  final double pitchDeg;

  /// Body height (metres) the tilted camera aims at: it pivots about it.
  final double aimHeightM;

  /// Frame units (upright image height = 1) per metre at the subject.
  final double scale;
  final double distanceM;

  /// Upright width / height; the page is portrait-locked (480x720 medium).
  final double aspect;

  /// Frame y of the floor at the subject's distance when the camera is
  /// level; with [pitchDeg] the floor moves (only the aim point stays put,
  /// at `floorY - aimHeightM * scale`).
  final double floorY;

  /// Horizontal body coordinate (metres) drawn at the frame center.
  final double centerU;

  double _u(V3 p) {
    final a = _rad(azimuthDeg);
    return p.x * math.sin(a) - p.z * math.cos(a);
  }

  /// Horizontal distance toward the camera, metres — what decides which
  /// side of the body is occluded.
  double depth(V3 p) {
    final a = _rad(azimuthDeg);
    return p.x * math.cos(a) + p.z * math.sin(a);
  }

  (double, double) project(V3 p) {
    final pitch = _rad(pitchDeg);
    // Tilted down about the aim point: height and nearness mix into the
    // image's vertical axis, and higher points come closer to the camera.
    final height = p.y - aimHeightM;
    final up = height * math.cos(pitch) - depth(p) * math.sin(pitch);
    final towardCamera = depth(p) * math.cos(pitch) + height * math.sin(pitch);
    final perspective = distanceM / (distanceM - towardCamera);
    return (
      aspect / 2 + (_u(p) - centerU) * scale * perspective,
      // Perspective scales about the aim point, where the lens points.
      floorY - aimHeightM * scale - up * scale * perspective,
    );
  }
}

/// Detector imperfections.
class SimNoise {
  const SimNoise({
    this.sigma = .004,
    this.farSigmaFactor = 2,
    this.nearConfidence = .97,
    this.farConfidence = .80,
    this.outlierRate = .02,
    this.outlierSigma = .03,
    this.dropoutRate = .01,
    this.fps = 15,
    this.frameJitterMs = 12,
    this.latencyMs = 45,
    this.latencyJitterMs = 10,
  });

  /// Gaussian landmark jitter, frame units (.004 ≈ 3 px on 720 px).
  final double sigma;

  /// Occluded far-side joints are guessed, so they jitter more.
  final double farSigmaFactor;
  final double nearConfidence;
  final double farConfidence;

  /// Chance per frame that one random joint jumps by [outlierSigma].
  final double outlierRate;
  final double outlierSigma;

  /// Chance per frame that ML Kit returns no pose at all.
  final double dropoutRate;
  final double fps;
  final double frameJitterMs;
  final double latencyMs;
  final double latencyJitterMs;

  static const none = SimNoise(
    sigma: 0,
    farSigmaFactor: 1,
    farConfidence: .97,
    outlierRate: 0,
    dropoutRate: 0,
    frameJitterMs: 0,
    latencyJitterMs: 0,
  );
}

/// A movement over time, plus how many reps (or hold seconds) it should
/// produce.
abstract interface class Movement {
  double get durationS;
  Pose3 poseAt(double t);
}

double _ease(double x) => (1 - math.cos(math.pi * x.clamp(0, 1))) / 2;

/// Rep timeline: rest standing [leadS], then each rep descends, pauses at
/// the bottom, ascends and rests. Returns progress 0 (top) .. 1 (bottom).
class RepTimeline {
  const RepTimeline({
    required this.reps,
    required this.descentS,
    required this.pauseS,
    required this.ascentS,
    required this.restS,
    this.leadS = 1.5,
    this.tailS = 1.5,
  });

  final int reps;
  final double descentS, pauseS, ascentS, restS, leadS, tailS;

  double get repS => descentS + pauseS + ascentS + restS;
  double get durationS => leadS + reps * repS + tailS;

  double progress(double t) {
    final local = t - leadS;
    if (local < 0 || local >= reps * repS) return 0;
    final r = local % repS;
    if (r < descentS) return _ease(r / descentS);
    if (r < descentS + pauseS) return 1;
    if (r < descentS + pauseS + ascentS) {
      return 1 - _ease((r - descentS - pauseS) / ascentS);
    }
    return 0;
  }
}

class SquatMovement implements Movement {
  SquatMovement({
    this.reps = 5,
    this.kneeMinDeg = 75,
    this.leanBottomDeg = 35,
    this.shinShare = .40,
    this.heelLiftM = 0,
    this.valgusM = 0,
    this.asymmetryDeg = 0,
    this.stanceHalfM = .17,
    this.toeOutDeg = 20,
    double descentS = 1.4,
    double pauseS = .3,
    double ascentS = 1.0,
    double restS = 1.0,
  }) : timeline = RepTimeline(
         reps: reps,
         descentS: descentS,
         pauseS: pauseS,
         ascentS: ascentS,
         restS: restS,
       );

  final int reps;

  /// Smallest hip-knee-ankle angle at the bottom.
  final double kneeMinDeg;

  /// Trunk angle from vertical at the bottom.
  final double leanBottomDeg;

  /// Share of knee flexion taken by the shin tilting forward.
  final double shinShare;
  final double heelLiftM;

  /// How far the knees cave toward the midline at the bottom.
  final double valgusM;

  /// The right knee bends this much less than the left at the bottom.
  final double asymmetryDeg;
  final double stanceHalfM;
  final double toeOutDeg;
  final RepTimeline timeline;

  static const _standingKnee = 178.0;

  @override
  double get durationS => timeline.durationS;

  @override
  Pose3 poseAt(double t) {
    final p = timeline.progress(t);
    final pose = <SquatJoint, V3>{};
    final hips = <V3>[];
    for (final side in const [1, -1]) {
      final left = side == 1;
      final knee =
          _standingKnee -
          p * (_standingKnee - kneeMinDeg - (left ? 0 : -asymmetryDeg));
      final flex = 180 - knee;
      final s = _rad(shinShare * flex);
      final th = _rad(flex - shinShare * flex);
      final ankle = V3(
        0,
        Body.ankleHeight + heelLiftM * p * .5,
        side * stanceHalfM,
      );
      final kneeX = Body.shank * math.sin(s);
      // Standing, the knee sits on the hip-ankle line; bending, it follows
      // the toes out, unless it caves in.
      final kneeZ =
          ankle.z +
          (side * Body.hipHalf - ankle.z) * .5 * (1 - p) +
          side * math.sin(_rad(toeOutDeg)) * kneeX -
          side * valgusM * p;
      final kneePoint = V3(kneeX, ankle.y + Body.shank * math.cos(s), kneeZ);
      final hip = V3(
        kneePoint.x - Body.thigh * math.sin(th),
        kneePoint.y + Body.thigh * math.cos(th),
        side * Body.hipHalf,
      );
      hips.add(hip);
      final toe = _rad(toeOutDeg);
      pose[left ? SquatJoint.leftAnkle : SquatJoint.rightAnkle] = ankle;
      pose[left ? SquatJoint.leftKnee : SquatJoint.rightKnee] = kneePoint;
      pose[left ? SquatJoint.leftHip : SquatJoint.rightHip] = hip;
      pose[left ? SquatJoint.leftHeel : SquatJoint.rightHeel] = V3(
        -Body.heelBack,
        Body.ankleHeight * .3 + heelLiftM * p,
        ankle.z,
      );
      pose[left ? SquatJoint.leftFoot : SquatJoint.rightFoot] = V3(
        Body.footFront * math.cos(toe),
        .02,
        ankle.z + side * Body.footFront * math.sin(toe),
      );
    }
    final midHip = (hips[0] + hips[1]) * .5;
    final lean = _rad(leanBottomDeg * p);
    // Arms reach forward as a counterbalance on the way down.
    final reach = _rad(20 + 70 * p);
    final arm = V3(math.sin(reach), -math.cos(reach), 0);
    for (final side in const [1, -1]) {
      final left = side == 1;
      final shoulder = V3(
        midHip.x + Body.torso * math.sin(lean),
        midHip.y + Body.torso * math.cos(lean),
        side * Body.shoulderHalf,
      );
      final elbow = shoulder + arm * Body.upperArm;
      pose[left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder] =
          shoulder;
      pose[left ? SquatJoint.leftElbow : SquatJoint.rightElbow] = elbow;
      pose[left ? SquatJoint.leftWrist : SquatJoint.rightWrist] =
          elbow + arm * Body.forearm;
    }
    return pose;
  }
}

/// Prone body line shared by push-ups and planks: shoulders at
/// [shoulder], toes on the floor, hips offset down by [sagM] (negative =
/// piking).
void _proneBody(Pose3 pose, V3 shoulderLeft, double sagM) {
  const length = Body.torso + Body.thigh + Body.shank;
  const ankleY = .10;
  final drop = shoulderLeft.y - ankleY;
  final run = math.sqrt(math.max(0, length * length - drop * drop));
  for (final side in const [1, -1]) {
    final left = side == 1;
    final shoulder = V3(
      shoulderLeft.x,
      shoulderLeft.y,
      side * Body.shoulderHalf,
    );
    final ankle = V3(shoulder.x - run, ankleY, side * Body.hipHalf);
    V3 along(double distance) {
      final k = distance / length;
      final point = shoulder + (ankle - shoulder) * k;
      return V3(point.x, point.y, side * Body.hipHalf);
    }

    // Sag peaks at the hip and fades toward shoulders and ankles.
    final hip = along(Body.torso) - V3(0, sagM, 0);
    final knee = along(Body.torso + Body.thigh) - V3(0, sagM * .5, 0);
    pose[left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder] = shoulder;
    pose[left ? SquatJoint.leftHip : SquatJoint.rightHip] = hip;
    pose[left ? SquatJoint.leftKnee : SquatJoint.rightKnee] = knee;
    pose[left ? SquatJoint.leftAnkle : SquatJoint.rightAnkle] = ankle;
    pose[left ? SquatJoint.leftHeel : SquatJoint.rightHeel] =
        ankle + const V3(-.04, .06, 0);
    pose[left ? SquatJoint.leftFoot : SquatJoint.rightFoot] =
        ankle + const V3(.10, -.08, 0);
  }
}

class PushupMovement implements Movement {
  PushupMovement({
    this.reps = 5,
    this.elbowMinDeg = 80,
    this.elbowTopDeg = 172,
    this.sagM = 0,
    this.flareDeg = 25,
    double descentS = 1.0,
    double pauseS = .2,
    double ascentS = .8,
    double restS = .6,
  }) : timeline = RepTimeline(
         reps: reps,
         descentS: descentS,
         pauseS: pauseS,
         ascentS: ascentS,
         restS: restS,
       );

  final int reps;
  final double elbowMinDeg;
  final double elbowTopDeg;
  final double sagM;

  /// Elbow flare away from the body, degrees (0 = tucked along the sides).
  final double flareDeg;
  final RepTimeline timeline;

  static const _wristY = .03;

  @override
  double get durationS => timeline.durationS;

  @override
  Pose3 poseAt(double t) {
    final p = timeline.progress(t);
    final elbowAngle = elbowTopDeg - p * (elbowTopDeg - elbowMinDeg);
    const a = Body.upperArm, b = Body.forearm;
    final d = math.sqrt(a * a + b * b - 2 * a * b * math.cos(_rad(elbowAngle)));
    // Shoulders drift slightly ahead of the hands on the way down.
    final sx = .03 * p;
    final shoulderLeft = V3(sx, _wristY + math.sqrt(d * d - sx * sx), 0);
    final pose = <SquatJoint, V3>{};
    _proneBody(pose, shoulderLeft, sagM);
    for (final side in const [1, -1]) {
      final left = side == 1;
      final shoulder =
          pose[left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder]!;
      final wrist = V3(0, _wristY, side * (Body.shoulderHalf + .03));
      final axis = (shoulder - wrist) * (1 / (shoulder - wrist).length);
      final along = (b * b - a * a + d * d) / (2 * d);
      final out = math.sqrt(math.max(0, b * b - along * along));
      // Elbows bend back toward the feet, flared out by [flareDeg].
      final f = _rad(flareDeg);
      final bend = V3(
        -axis.y * math.cos(f),
        axis.x * math.cos(f),
        side * math.sin(f),
      );
      pose[left ? SquatJoint.leftWrist : SquatJoint.rightWrist] = wrist;
      pose[left ? SquatJoint.leftElbow : SquatJoint.rightElbow] =
          wrist + axis * along + bend * out;
    }
    return pose;
  }
}

class PlankMovement implements Movement {
  PlankMovement({this.holdS = 20, this.sagM = 0, this.swayM = .01});

  final double holdS;
  final double sagM;

  /// Slow natural sway of the hips while holding.
  final double swayM;

  @override
  double get durationS => holdS;

  @override
  Pose3 poseAt(double t) {
    const elbowY = .05;
    final pose = <SquatJoint, V3>{};
    _proneBody(
      pose,
      const V3(0, elbowY + Body.upperArm, 0),
      sagM + swayM * math.sin(t * 1.3),
    );
    for (final side in const [1, -1]) {
      final left = side == 1;
      final z = side * Body.shoulderHalf;
      pose[left ? SquatJoint.leftElbow : SquatJoint.rightElbow] = V3(
        0,
        elbowY,
        z,
      );
      pose[left ? SquatJoint.leftWrist : SquatJoint.rightWrist] = V3(
        Body.forearm,
        .04,
        z * .6,
      );
    }
    return pose;
  }
}

/// Standing overhead press with both arms in the frontal plane: from the
/// rack (upper arms out to the sides, elbows bent 90°, hands up) to arms
/// straight overhead.
class ShoulderPressMovement implements Movement {
  ShoulderPressMovement({
    this.reps = 5,
    this.elbowTopDeg = 172,
    this.rightShortfall = 0,
    this.topP = 1,
    this.lowestP = 0,
    double pressS = .9,
    double pauseS = .25,
    double lowerS = 1.1,
    double restS = .6,
  }) : timeline = RepTimeline(
         reps: reps,
         descentS: pressS,
         pauseS: pauseS,
         ascentS: lowerS,
         restS: restS,
       );

  final int reps;

  /// Elbow angle at the top: ~172 locked out, lower for a half press.
  final double elbowTopDeg;

  /// How far short of the left arm the right one stops (0..1 of its
  /// range): a weaker arm that never gets as high, not one that catches up.
  final double rightShortfall;

  /// How far up each press goes (1 = locked out overhead).
  final double topP;

  /// Lowest point between reps (0 = back to the shoulders).
  final double lowestP;

  /// Pressing up / holding / lowering, on the shared rep timeline.
  final RepTimeline timeline;

  static const _shoulderY = 1.44;

  @override
  double get durationS => timeline.durationS;

  @override
  Pose3 poseAt(double t) {
    final raw = timeline.progress(t);
    // The set starts and ends at the shoulders; only the rests between
    // presses stop at [lowestP].
    final inSet =
        t >= timeline.leadS && t < timeline.durationS - timeline.tailS;
    final p = (inSet ? lowestP + (1 - lowestP) * raw : raw) * topP;
    final pose = <SquatJoint, V3>{};
    for (final side in const [1, -1]) {
      final left = side == 1;
      final armP = left ? p : p * (1 - rightShortfall);
      // Upper arm from horizontal-outward (rack) to nearly vertical.
      final beta = _rad(80 * armP);
      final elbowAngle = 90 + (elbowTopDeg - 90) * armP;
      // Forearm direction, same convention: vertical in the rack, in line
      // with the upper arm when locked out.
      final gamma = beta + _rad(180 - elbowAngle);
      final shoulder = V3(0, _shoulderY, side * Body.shoulderHalf);
      final elbow =
          shoulder +
          V3(.04, math.sin(beta), side * math.cos(beta)) * Body.upperArm;
      final wrist =
          elbow +
          V3(.02, math.sin(gamma), side * math.cos(gamma)) * Body.forearm;
      pose[left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder] =
          shoulder;
      pose[left ? SquatJoint.leftElbow : SquatJoint.rightElbow] = elbow;
      pose[left ? SquatJoint.leftWrist : SquatJoint.rightWrist] = wrist;
      pose[left ? SquatJoint.leftHip : SquatJoint.rightHip] = V3(
        0,
        _shoulderY - Body.torso,
        side * Body.hipHalf,
      );
      pose[left ? SquatJoint.leftKnee : SquatJoint.rightKnee] = V3(
        0,
        Body.ankleHeight + Body.shank,
        side * Body.hipHalf,
      );
      pose[left ? SquatJoint.leftAnkle : SquatJoint.rightAnkle] = V3(
        0,
        Body.ankleHeight,
        side * Body.hipHalf,
      );
    }
    return pose;
  }
}

/// Not a press: straight arms raised from hanging at the sides to
/// overhead and back, elbows never bending at the shoulders.
class StraightArmRaiseMovement implements Movement {
  StraightArmRaiseMovement({this.reps = 5})
    : timeline = RepTimeline(
        reps: reps,
        descentS: 1,
        pauseS: .3,
        ascentS: 1,
        restS: .6,
      );

  final int reps;
  final RepTimeline timeline;

  @override
  double get durationS => timeline.durationS;

  @override
  Pose3 poseAt(double t) {
    final press = ShoulderPressMovement().poseAt(0);
    final pose = Map.of(press);
    // From pointing down (-85°) through the side to overhead (85°).
    final angle = _rad(-85 + 170 * timeline.progress(t));
    for (final side in const [1, -1]) {
      final left = side == 1;
      final shoulder =
          pose[left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder]!;
      final direction = V3(.02, math.sin(angle), side * math.cos(angle));
      final elbow = shoulder + direction * Body.upperArm;
      pose[left ? SquatJoint.leftElbow : SquatJoint.rightElbow] = elbow;
      pose[left ? SquatJoint.leftWrist : SquatJoint.rightWrist] =
          elbow + direction * Body.forearm;
    }
    return pose;
  }
}

/// One analyzer frame: what the page would hand to `analyze`.
class SimFrame {
  const SimFrame(this.timestampUs, this.points);
  final int timestampUs;
  final Map<SquatJoint, SquatPoint> points;
}

/// Renders [movement] into detector frames.
List<SimFrame> simulate(
  Movement movement, {
  SimCamera camera = const SimCamera(),
  SimNoise noise = const SimNoise(),
  int seed = 1,
}) {
  final rng = math.Random(seed);
  double gauss() {
    final u1 = math.max(1e-12, rng.nextDouble());
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final frames = <SimFrame>[];
  var t = 0.0;
  final occlusionWeight = math.sin(_rad(camera.azimuthDeg)).abs();
  while (t < movement.durationS) {
    final latency = (noise.latencyMs + gauss() * noise.latencyJitterMs) / 1000;
    final us = ((t + math.max(.01, latency)) * 1e6).round();
    if (rng.nextDouble() < noise.dropoutRate) {
      frames.add(SimFrame(us, const {}));
    } else {
      final pose = movement.poseAt(t);
      final center =
          pose.values.fold(0.0, (sum, p) => sum + camera.depth(p)) /
          pose.length;
      final outlier = rng.nextDouble() < noise.outlierRate
          ? pose.keys.elementAt(rng.nextInt(pose.length))
          : null;
      final points = <SquatJoint, SquatPoint>{};
      for (final entry in pose.entries) {
        final (x, y) = camera.project(entry.value);
        // Joints on the far side of the body are partly occluded.
        final behind =
            ((center - camera.depth(entry.value)) / .12).clamp(0.0, 1.0) *
            occlusionWeight;
        final heel =
            entry.key == SquatJoint.leftHeel ||
            entry.key == SquatJoint.rightHeel;
        final confidence =
            (noise.nearConfidence -
                    (noise.nearConfidence - noise.farConfidence) * behind -
                    (heel ? .08 : 0) +
                    gauss() * .02)
                .clamp(0.0, 1.0);
        var sigma = noise.sigma * (1 + (noise.farSigmaFactor - 1) * behind);
        if (entry.key == outlier) sigma += noise.outlierSigma;
        points[entry.key] = SquatPoint(
          x + gauss() * sigma,
          y + gauss() * sigma,
          confidence: confidence,
        );
      }
      frames.add(SimFrame(us, points));
    }
    t += 1 / noise.fps + gauss() * noise.frameJitterMs / 1000;
  }
  return frames;
}

/// Everything the page would show while replaying [frames].
class SimResult {
  SimResult(this.analyzer, this.outputs);
  final RepAnalyzer analyzer;
  final List<SquatAnalysis> outputs;

  int get count => analyzer.repetitions;
  List<RepRecord> get records => analyzer.repRecords;

  Iterable<SquatAnalysis> get visible =>
      outputs.where((o) => o.bodyVisible && o.phase != SquatPhase.findingBody);

  /// Lowest live FORM score while tracking.
  int get minScore =>
      visible.isEmpty ? 0 : visible.map((o) => o.score).reduce(math.min);

  /// Share of tracked frames that showed a perfect 100.
  double get perfectShare => visible.isEmpty
      ? 0
      : visible.where((o) => o.score == 100).length / visible.length;

  Set<String> get cues => {for (final o in outputs) o.cue};

  /// Cues shown as form warnings (amber on screen, spoken aloud).
  Set<String> get warnings => {
    for (final o in outputs)
      if (o.tone == CueTone.warn) o.cue,
  };
  Set<String> get faults => {for (final r in records) ...r.faults};
}

SimResult replay(RepAnalyzer analyzer, List<SimFrame> frames) =>
    SimResult(analyzer, [
      for (final frame in frames)
        analyzer.analyze(frame.points, timestampUs: frame.timestampUs),
    ]);

/// What the page would say aloud over [frames], through the same live
/// feedback loop it uses.
List<String> spoken(
  RepAnalyzer analyzer,
  List<SimFrame> frames, {
  bool timed = false,
}) {
  final feedback = LiveFeedback(timed: timed);
  return [
    for (final frame in frames)
      ?feedback
          .update(
            analyzer.analyze(frame.points, timestampUs: frame.timestampUs),
            frame.timestampUs,
          )
          .say,
  ];
}

/// The cues the page would actually put on screen over [frames], in order,
/// after glitch filtering and stabilizing.
List<(String, CueTone)> shownCues(
  RepAnalyzer analyzer,
  List<SimFrame> frames, {
  bool timed = false,
}) {
  final feedback = LiveFeedback(timed: timed);
  final shown = <(String, CueTone)>[];
  for (final frame in frames) {
    feedback.update(
      analyzer.analyze(frame.points, timestampUs: frame.timestampUs),
      frame.timestampUs,
    );
    final cue = (feedback.cue.cue!, feedback.cue.tone);
    if (shown.isEmpty || shown.last != cue) shown.add(cue);
  }
  return shown;
}
