import 'dart:math' as math;

import '../features/squat_form/domain/squat_analyzer.dart' show SquatJoint;
import 'models/exercise_motion.dart';

typedef RigPoint = math.Point<double>;

/// Where a demo is seen from: [side] shows the figure's right side (it
/// faces right), [front] faces the viewer, [back] is seen from behind.
enum MotionAngle {
  side,
  front,
  back;

  /// The angle a motion posed in [view] is shown from at first.
  static MotionAngle of(MotionView view) =>
      view == MotionView.front ? front : side;
}

/// A [pose] seen from some [MotionAngle], with how near each joint is to
/// the viewer ([depth]: larger is nearer).
class RigView {
  const RigView({required this.pose, required this.depth});

  final RigPose pose;
  final Map<SquatJoint, double> depth;
}

/// Where every drawn point of a demo figure is, y pointing down.
class RigPose {
  const RigPose({required this.joints, required this.neck, required this.head});

  final Map<SquatJoint, RigPoint> joints;

  /// Top of the neck, and the centre of the head (radius
  /// [MotionRig.headRadius]).
  final RigPoint neck;
  final RigPoint head;

  RigPose shifted(RigPoint by) => RigPose(
    joints: joints.map((joint, point) => MapEntry(joint, point + by)),
    neck: neck + by,
    head: head + by,
  );
}

/// Turns a [MotionPose]'s joint angles into a stick figure about one unit
/// tall (forward kinematics from the hips). The admin web's
/// `motionRig.ts` is a port of this: keep the two in step.
///
/// Angles are degrees, counter-clockwise on screen for the figure's
/// facing side. Side view (facing right):
/// - torso: lean from upright; +90 lies face down, head forward.
/// - shoulder: upper arm from hanging along the torso; +90 points it
///   forward, +180 overhead, negative reaches back (a dip).
/// - elbow: forearm bend from straight, curling forward.
/// - hip: thigh from in line with the torso; +90 lifts it forward.
/// - knee: shin bend from straight, backwards.
/// - ankle: foot from square to the shin; + lifts the toes.
///
/// Front view mirrors the right side: shoulder and hip spread the limbs
/// out to the sides, elbow and knee bend them back in (elbows up in a
/// press), torso tilts sideways.
abstract final class MotionRig {
  static const torsoLength = 0.29;
  static const neckLength = 0.035;
  static const headRadius = 0.062;
  static const upperArmLength = 0.17;
  static const forearmLength = 0.155;
  static const thighLength = 0.245;
  static const shinLength = 0.24;
  static const footLength = 0.13;

  /// How far the sole is below the ankle.
  static const soleDepth = 0.035;
  static const halfShoulderWidth = 0.1;
  static const halfHipWidth = 0.065;

  /// A bench reaches this far behind the hands (side view), or this far
  /// out either side of them (front view).
  static const benchBehind = 0.3;
  static const benchAhead = 0.02;
  static const benchHalfWidth = 0.25;

  /// How far weights reach past the wrists, at most.
  static const dumbbellReach = 0.075;

  /// How far a dumbbell held upright in both hands hangs below them.
  static const singleDumbbellDrop = 0.13;
  static const barbellReach = 0.17;

  static RigPoint _direction(double degrees) {
    final radians = degrees * math.pi / 180;
    return RigPoint(math.cos(radians), -math.sin(radians));
  }

  static RigPoint _step(RigPoint from, double degrees, double length) =>
      from + _direction(degrees) * length;

  /// The figure with its hips' midpoint at the origin.
  static RigPose solve(MotionPose pose, MotionView view) {
    final front = view == MotionView.front;
    final torsoDirection = 90 - pose.torso;
    const hips = RigPoint(0, 0);
    final shoulders = _step(hips, torsoDirection, torsoLength);
    final joints = <SquatJoint, RigPoint>{};
    void limbs({
      required bool left,
      required double shoulder,
      required double elbow,
      required double hip,
      required double knee,
      required double ankle,
    }) {
      // Front view: the left side is on screen right; the right side
      // mirrors every angle.
      final mirror = front && !left ? -1.0 : 1.0;
      final across = front ? mirror : 0.0;
      final shoulderAt = _step(
        shoulders,
        torsoDirection - 90,
        across * halfShoulderWidth,
      );
      final hipAt = _step(hips, torsoDirection - 90, across * halfHipWidth);
      final upperArm = torsoDirection + 180 + mirror * shoulder;
      final forearm = upperArm + mirror * elbow;
      final thigh = torsoDirection + 180 + mirror * hip;
      final shin = thigh - mirror * knee;
      final foot = shin + mirror * (90 + ankle);
      final elbowAt = _step(shoulderAt, upperArm, upperArmLength);
      final kneeAt = _step(hipAt, thigh, thighLength);
      final ankleAt = _step(kneeAt, shin, shinLength);
      final sole = foot - mirror * 90;
      joints.addAll({
        left ? SquatJoint.leftShoulder : SquatJoint.rightShoulder: shoulderAt,
        left ? SquatJoint.leftElbow : SquatJoint.rightElbow: elbowAt,
        left ? SquatJoint.leftWrist : SquatJoint.rightWrist: _step(
          elbowAt,
          forearm,
          forearmLength,
        ),
        left ? SquatJoint.leftHip : SquatJoint.rightHip: hipAt,
        left ? SquatJoint.leftKnee : SquatJoint.rightKnee: kneeAt,
        left ? SquatJoint.leftAnkle : SquatJoint.rightAnkle: ankleAt,
        left ? SquatJoint.leftFoot : SquatJoint.rightFoot: _step(
          _step(ankleAt, foot, footLength * .78),
          sole,
          soleDepth,
        ),
        left ? SquatJoint.leftHeel : SquatJoint.rightHeel: _step(
          _step(ankleAt, foot, -footLength * .22),
          sole,
          soleDepth,
        ),
      });
    }

    limbs(
      left: true,
      shoulder: pose.shoulderL,
      elbow: pose.elbowL,
      hip: pose.hipL,
      knee: pose.kneeL,
      ankle: pose.ankleL,
    );
    limbs(
      left: false,
      shoulder: pose.shoulderR,
      elbow: pose.elbowR,
      hip: pose.hipR,
      knee: pose.kneeR,
      ankle: pose.ankleR,
    );
    return RigPose(
      joints: joints,
      neck: _step(shoulders, torsoDirection, neckLength),
      head: _step(shoulders, torsoDirection, neckLength + headRadius),
    );
  }

  static RigPoint _midpoint(RigPoint a, RigPoint b) => (a + b) * .5;

  /// The figure moved so its [anchor] sits at the origin: posed through a
  /// loop, the anchored part stays in place while the body moves.
  static RigPose anchored(
    MotionPose pose,
    MotionView view,
    MotionAnchor anchor,
  ) {
    final figure = solve(pose, view);
    final joints = figure.joints;
    final at = switch (anchor) {
      MotionAnchor.feet => _midpoint(
        joints[SquatJoint.leftFoot]!,
        joints[SquatJoint.rightFoot]!,
      ),
      MotionAnchor.hands => _midpoint(
        joints[SquatJoint.leftWrist]!,
        joints[SquatJoint.rightWrist]!,
      ),
      MotionAnchor.hips => const RigPoint(0, 0),
    };
    return figure.shifted(RigPoint(-at.x, -at.y));
  }

  /// The figure of [motion] at [ms] into its loop.
  static RigPose at(ExerciseMotion motion, double ms) =>
      anchored(motion.frameAt(ms).pose, motion.view, motion.anchor);

  static bool _isArm(SquatJoint joint) => switch (joint) {
    SquatJoint.leftShoulder ||
    SquatJoint.rightShoulder ||
    SquatJoint.leftElbow ||
    SquatJoint.rightElbow ||
    SquatJoint.leftWrist ||
    SquatJoint.rightWrist => true,
    _ => false,
  };

  /// [pose] in 3D, seen from [angle]. A motion's angles turn the limbs
  /// in the plane it was posed in ([view]): forwards and back for side,
  /// out to the sides for front. Seen from elsewhere the limbs that point
  /// at the viewer shorten, as they would.
  static RigView seen(
    MotionPose pose,
    MotionView view,
    MotionAnchor anchor,
    MotionAngle angle,
  ) {
    final flat = anchored(pose, view, anchor);
    // (forward, down, towards the figure's left)
    (double, double, double) lift(RigPoint point, SquatJoint? joint) {
      if (view == MotionView.front) return (0, point.y, point.x);
      final side = joint == null
          ? 0.0
          : (joint.name.startsWith('left') ? 1.0 : -1.0) *
                (_isArm(joint) ? halfShoulderWidth : halfHipWidth);
      return (point.x, point.y, side);
    }

    RigPoint project((double, double, double) p) => switch (angle) {
      MotionAngle.side => RigPoint(p.$1, p.$2),
      MotionAngle.front => RigPoint(p.$3, p.$2),
      MotionAngle.back => RigPoint(-p.$3, p.$2),
    };
    double nearness((double, double, double) p) => switch (angle) {
      MotionAngle.side => -p.$3,
      MotionAngle.front => p.$1,
      MotionAngle.back => -p.$1,
    };
    final joints = <SquatJoint, RigPoint>{};
    final depth = <SquatJoint, double>{};
    for (final MapEntry(key: joint, value: point) in flat.joints.entries) {
      var p = lift(point, joint);
      // Posed from the front, the feet were drawn pointing out to the
      // sides; in 3D they point forward, flat under the ankle.
      if (view == MotionView.front) {
        final along = switch (joint) {
          SquatJoint.leftFoot || SquatJoint.rightFoot => footLength * .78,
          SquatJoint.leftHeel || SquatJoint.rightHeel => -footLength * .22,
          _ => null,
        };
        if (along != null) {
          final ankle =
              flat.joints[joint.name.startsWith('left')
                  ? SquatJoint.leftAnkle
                  : SquatJoint.rightAnkle]!;
          p = (along, ankle.y + soleDepth, lift(ankle, joint).$3);
        }
      }
      joints[joint] = project(p);
      depth[joint] = nearness(p);
    }
    return RigView(
      pose: RigPose(
        joints: joints,
        neck: project(lift(flat.neck, null)),
        head: project(lift(flat.head, null)),
      ),
      depth: depth,
    );
  }

  /// The angles [motion] reads well from: the one it was posed in, and
  /// the others unless the body tips far over (a push-up seen head-on is
  /// all foreshortening).
  static List<MotionAngle> angles(ExerciseMotion motion) {
    final own = MotionAngle.of(motion.view);
    final upright = motion.keyframes.every(
      (frame) => frame.pose.torso.abs() <= 50,
    );
    return [
      for (final angle in MotionAngle.values)
        if (angle == own || upright) angle,
    ];
  }

  /// The figure of [motion] at [ms], seen from [angle].
  static RigView seenAt(ExerciseMotion motion, double ms, MotionAngle angle) =>
      seen(motion.frameAt(ms).pose, motion.view, motion.anchor, angle);

  /// Everything the figure covers over a whole loop (head and equipment
  /// included), so a demo can be framed once without the figure drifting
  /// or rescaling. Its bottom edge is the floor.
  static math.Rectangle<double> bounds(
    ExerciseMotion motion, [
    MotionAngle? angle,
  ]) {
    const samples = 48;
    final seenFrom = angle ?? MotionAngle.of(motion.view);
    final poses = [
      for (final frame in motion.keyframes)
        seen(frame.pose, motion.view, motion.anchor, seenFrom).pose,
      for (var i = 0; i < samples; i++)
        seenAt(motion, motion.loopMs * i / samples, seenFrom).pose,
    ];
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    void include(RigPoint point, [double radius = 0]) {
      left = math.min(left, point.x - radius);
      right = math.max(right, point.x + radius);
      top = math.min(top, point.y - radius);
      bottom = math.max(bottom, point.y + radius);
    }

    final side = seenFrom == MotionAngle.side;
    for (final pose in poses) {
      pose.joints.values.forEach(include);
      include(pose.head, headRadius);
      final wrists = [
        pose.joints[SquatJoint.leftWrist]!,
        pose.joints[SquatJoint.rightWrist]!,
      ];
      switch (motion.equipment) {
        case MotionEquipment.none:
          break;
        case MotionEquipment.dumbbells:
          for (final wrist in wrists) {
            include(wrist, dumbbellReach);
          }
        case MotionEquipment.dumbbell:
          // It hangs below the hands.
          final hands = _midpoint(wrists[0], wrists[1]);
          include(
            RigPoint(hands.x, hands.y + singleDumbbellDrop),
            dumbbellReach,
          );
        case MotionEquipment.barbell:
          for (final wrist in wrists) {
            include(wrist, side ? dumbbellReach : barbellReach);
          }
        case MotionEquipment.bench:
          final hands = _midpoint(wrists[0], wrists[1]);
          include(
            RigPoint(hands.x - (side ? benchBehind : benchHalfWidth), hands.y),
          );
          include(
            RigPoint(hands.x + (side ? benchAhead : benchHalfWidth), hands.y),
          );
      }
    }
    return math.Rectangle(left, top, right - left, bottom - top);
  }
}
