import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../domain/models/exercise_motion.dart';
import '../../../domain/motion_rig.dart';
import '../../../domain/muscle_volume.dart';
import '../../squat_form/domain/squat_analyzer.dart' show SquatJoint;

/// A shape of a [BodyPiece], filled in order (later layers cover the
/// muscles of earlier ones), with its muscles and the thin [seams] that
/// split muscle heads.
typedef BodyLayer = ({Path fill, List<(Muscle, Path)> muscles, Path seams});

/// One drawn part, in rig units: its [layers] and a single [outline]
/// round them all, so a limb reads as one piece rather than segments
/// joined at the joints. The outline is stroked (or [edge] instead, when
/// set) except inside [unstroked], where the part merges into the body.
/// [contours] are where a segment folds over an earlier one: each line is
/// stroked only inside its clip, which leaves out the joint itself.
/// [details] (fingers) are drawn like the edge. [far] parts are the side
/// behind the body; [gear] is equipment, not body.
typedef BodyPiece = ({
  List<BodyLayer> layers,
  Path outline,
  Path? edge,
  Path? unstroked,
  List<(Path line, Path clip)> contours,
  Path details,
  bool far,
  bool gear,
});

BodyPiece _bodyPiece(
  Path fill, {
  Path? edge,
  Path? unstroked,
  List<(Muscle, Path)> muscles = const [],
  Path? seams,
  Path? details,
  bool far = false,
  bool gear = false,
}) => (
  layers: [(fill: fill, muscles: muscles, seams: seams ?? Path())],
  outline: fill,
  edge: edge,
  unstroked: unstroked,
  contours: const [],
  details: details ?? Path(),
  far: far,
  gear: gear,
);

/// A segment of a limb and the joint it hangs from (its parent's end).
typedef ChainLink = ({BodyPiece part, Offset joint, double reach});

/// [links] drawn as one limb: each covers the ones before it, inside one
/// outline. Where a link folds over the earlier ones further than [reach]
/// from its joint (a tight curl, a deep squat), its edge shows there.
BodyPiece chain(BodyPiece first, List<ChainLink> links, {required bool far}) {
  var outline = first.outline;
  var unstroked = first.unstroked;
  final contours = <(Path, Path)>[];
  final details = Path()..addPath(first.details, Offset.zero);
  for (final link in links) {
    final joint = Path()
      ..addOval(Rect.fromCircle(center: link.joint, radius: link.reach));
    contours.add((
      link.part.outline,
      Path.combine(PathOperation.difference, outline, joint),
    ));
    outline = Path.combine(PathOperation.union, outline, link.part.outline);
    if (link.part.unstroked case final region?) {
      unstroked = unstroked == null
          ? region
          : Path.combine(PathOperation.union, unstroked, region);
    }
    details.addPath(link.part.details, Offset.zero);
  }
  return (
    layers: [...first.layers, for (final link in links) ...link.part.layers],
    outline: outline,
    edge: null,
    unstroked: unstroked,
    contours: contours,
    details: details,
    far: far,
    gear: false,
  );
}

/// A closed curve through [points] (Catmull-Rom, as cubic Béziers).
Path smoothClosed(List<Offset> points) {
  final n = points.length;
  final path = Path()..moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = points[(i - 1 + n) % n];
    final p1 = points[i];
    final p2 = points[(i + 1) % n];
    final p3 = points[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// An open curve through [points].
Path smoothOpen(List<Offset> points) {
  final n = points.length;
  final path = Path()..moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < n - 1; i++) {
    final p0 = points[math.max(i - 1, 0)];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[math.min(i + 2, n - 1)];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// How thick a segment is at `u` (rig units along its bone): in front of
/// and behind the bone line.
typedef Station = (double u, double front, double back);

/// A muscle on a segment: from [u0] to [u1] along it, between [v0] and
/// [v1] across (-1 the back edge, 1 the front edge), [seams] splitting
/// its heads at those `v`s.
typedef MuscleRegion = ({
  Muscle muscle,
  double u0,
  double u1,
  double v0,
  double v1,
  List<double> seams,
});

/// A segment's silhouette ([stations], root to tip) and its muscles.
class Segment {
  const Segment(this.stations, this.muscles, {this.openRoot = false});

  final List<Station> stations;
  final List<MuscleRegion> muscles;

  /// Leaves the root end unstroked, so the part merges into the body it
  /// grows from.
  final bool openRoot;

  (double front, double back) widthAt(double u) {
    final s = stations;
    if (u <= s.first.$1) return (s.first.$2, s.first.$3);
    for (var i = 1; i < s.length; i++) {
      if (u <= s[i].$1) {
        final t = (u - s[i - 1].$1) / (s[i].$1 - s[i - 1].$1);
        return (
          s[i - 1].$2 + (s[i].$2 - s[i - 1].$2) * t,
          s[i - 1].$3 + (s[i].$3 - s[i - 1].$3) * t,
        );
      }
    }
    return (s.last.$2, s.last.$3);
  }

  /// Front edge root to tip, round tip, back edge to the root, then the
  /// round root cap (its last [_capPoints] points).
  /// [stretch] shortens the segment along its bone (seen end-on); its
  /// round ends keep their size, as a limb's cross-section would.
  List<Offset> _outline(double stretch) {
    final first = stations.first;
    final last = stations.last;
    final tip = (last.$2 + last.$3) / 2;
    final root = (first.$2 + first.$3) / 2;
    final end = last.$1 * stretch;
    final start = first.$1 * stretch;
    return [
      for (final (u, front, _) in stations) Offset(u * stretch, front),
      Offset(end + tip * .62, last.$2 * .72 - last.$3 * .1),
      Offset(end + tip * .95, (last.$2 - last.$3) / 2),
      Offset(end + tip * .62, -last.$3 * .72 + last.$2 * .1),
      for (final (u, _, back) in stations.reversed) Offset(u * stretch, -back),
      Offset(start - root * .62, -first.$3 * .72 + first.$2 * .1),
      Offset(start - root * .95, (first.$2 - first.$3) / 2),
      Offset(start - root * .62, first.$2 * .72 - first.$3 * .1),
    ];
  }

  static const _capPoints = 3;

  /// The light gap between neighbouring muscles and around them.
  static const gap = .0045;

  /// The piece on [frame]; [skin] places points instead where some ride
  /// another bone too (the hips with the thigh).
  BodyPiece place(
    BoneFrame frame, {
    required bool far,
    Offset Function(Offset local)? skin,
  }) {
    final stretch = frame.stretch;
    final at = skin ?? frame.at;
    final outline = _outline(stretch);
    final fill = smoothClosed([for (final point in outline) at(point)]);
    Path? unstroked;
    if (openRoot) {
      // Everything past the root station, a little enlarged so the
      // stroke's width is covered too.
      final first = stations.first;
      final rootU = first.$1 * stretch;
      final center = Offset(rootU, (first.$2 - first.$3) / 2);
      unstroked = Path()
        ..addPolygon([
          at(Offset(rootU + .003, first.$2 + .01)),
          for (final point
              in outline.sublist(outline.length - _capPoints).reversed)
            at(center + (point - center) * 1.4),
          at(Offset(rootU + .003, -first.$3 - .01)),
        ], true);
    }
    final muscles = <(Muscle, Path)>[];
    final seams = Path();
    for (final region in this.muscles) {
      const samples = 7;
      final top = <Offset>[];
      final bottom = <Offset>[];
      for (var i = 0; i <= samples; i++) {
        final t = i / samples;
        final u = region.u0 + (region.u1 - region.u0) * t;
        final (front, back) = widthAt(u);
        double y(double v) => -back + (front + back) * (v + 1) / 2;
        // A lens: full width in the middle, narrower at the ends.
        final swell = .3 + .7 * math.pow(math.sin(math.pi * t), .6);
        final mid = (region.v0 + region.v1) / 2;
        final half = (region.v1 - region.v0) / 2 * swell;
        top.add(
          Offset(u * stretch, math.min(y(mid + half), front - gap) - gap / 2),
        );
        bottom.add(
          Offset(u * stretch, math.max(y(mid - half), -back + gap) + gap / 2),
        );
      }
      muscles.add((
        region.muscle,
        smoothClosed([
          for (final point in [...top, ...bottom.reversed]) at(point),
        ]),
      ));
      for (final v in region.seams) {
        seams.addPath(
          smoothOpen([
            for (var i = 1; i < 6; i++)
              () {
                final u =
                    region.u0 + (region.u1 - region.u0) * (.1 + .8 * i / 6);
                final (front, back) = widthAt(u);
                return at(
                  Offset(u * stretch, -back + (front + back) * (v + 1) / 2),
                );
              }(),
          ]),
          Offset.zero,
        );
      }
    }
    return _bodyPiece(
      fill,
      unstroked: unstroked,
      muscles: muscles,
      seams: seams,
      far: far,
    );
  }
}

MuscleRegion _m(
  Muscle muscle,
  double u0,
  double u1,
  double v0,
  double v1, [
  List<double> seams = const [],
]) => (muscle: muscle, u0: u0, u1: u1, v0: v0, v1: v1, seams: seams);

/// A bone's frame: x along it from [origin], y across, + towards the
/// body's front (or, for a foot, up towards the ankle). [flip] mirrors y,
/// for the right arm seen from the front. Given the bone's true
/// [length], [stretch] is how much of it shows: a bone pointing at the
/// viewer is drawn short.
class BoneFrame {
  factory BoneFrame(
    Offset origin,
    Offset along, {
    bool torso = false,
    bool flip = false,
    double? length,
  }) {
    final distance = along.distance;
    // A bone pointing straight at the viewer has no direction on screen.
    final x = distance < 1e-6 ? const Offset(0, 1) : along / distance;
    final y =
        (torso ? Offset(-x.dy, x.dx) : Offset(x.dy, -x.dx)) *
        (flip ? -1.0 : 1.0);
    return BoneFrame._(
      origin,
      x,
      y,
      length == null ? 1 : math.min(distance / length, 1.0),
    );
  }

  BoneFrame._(this.origin, this.x, this.y, this.stretch);

  final Offset origin;
  final Offset x;
  final Offset y;
  final double stretch;

  Offset at(Offset local) => origin + x * local.dx + y * local.dy;
}

/// The muscle map's style drawn side-on, laid on the rig's bones (see
/// [MotionRig] for their lengths).
abstract final class ProfileBody {
  // Torso: x up from the hips' midpoint (shoulders at 0.29), y forward.
  static final torso = Segment(
    const [
      (-.088, .016, .03),
      (-.07, .036, .078),
      (-.02, .05, .088),
      (.04, .057, .072),
      (.1, .058, .05),
      (.16, .057, .054),
      (.21, .068, .064),
      (.255, .08, .068),
      (.29, .06, .064),
      (.315, .036, .046),
    ],
    [
      _m(Muscle.lowerBack, .1, .18, -1, -.4),
      _m(Muscle.obliques, .02, .2, -.32, .42, [-.05, .2]),
      _m(Muscle.abs, -.01, .2, .5, 1),
      _m(Muscle.upperBack, .15, .285, -1, -.1, [-.55]),
      _m(Muscle.chest, .195, .3, .1, 1, [.55]),
      _m(Muscle.trapezius, .27, .33, -1, -.2),
    ],
  );

  // Thigh: x down from the hip to the knee (0.245), y forward.
  static final thigh = Segment(
    const [
      (.0, .05, .05),
      (.04, .058, .058),
      (.1, .056, .054),
      (.17, .048, .045),
      (.225, .038, .034),
      (.25, .032, .03),
    ],
    [
      _m(Muscle.quadriceps, .01, .238, .02, 1, [.5]),
      _m(Muscle.hamstrings, .03, .225, -1, -.04, [-.5]),
    ],
    openRoot: true,
  );

  // Shin: x down from the knee to the ankle (0.24), y forward.
  static final shin = Segment(
    const [
      (-.02, .03, .032),
      (.03, .029, .044),
      (.08, .026, .048),
      (.14, .022, .036),
      (.2, .018, .022),
      (.24, .017, .018),
    ],
    [
      _m(Muscle.calves, .0, .175, -1, -.08, [-.5]),
      _m(Muscle.calves, .03, .19, .16, 1),
    ],
  );

  // Upper arm: x down from the shoulder to the elbow (0.17), y forward.
  static final upperArm = Segment(
    const [
      (-.035, .028, .032),
      (.0, .042, .044),
      (.05, .04, .04),
      (.1, .034, .036),
      (.15, .028, .029),
      (.175, .022, .022),
    ],
    [
      _m(Muscle.deltoids, -.035, .08, -1, 1, [-.38, .38]),
      _m(Muscle.biceps, .07, .165, .04, 1),
      _m(Muscle.triceps, .055, .168, -1, -.04, [-.55]),
    ],
    openRoot: true,
  );

  // Forearm: x from the elbow to the wrist (0.155), y forward.
  static final forearm = Segment(
    const [
      (-.025, .022, .024),
      (.025, .032, .028),
      (.075, .027, .024),
      (.13, .018, .017),
      (.158, .015, .015),
    ],
    [
      _m(Muscle.forearms, -.005, .125, -1, 1, [.1]),
    ],
  );

  // Hand: x from the wrist along the hand, y towards its front.
  static const hand = Segment([
    (.0, .016, .015),
    (.04, .02, .017),
    (.075, .016, .014),
  ], []);

  // A fist round a handle, x from the wrist; side-on the thumb is in
  // front (y > 0), from the front the knuckles face the viewer.
  static const fistPoints = [
    Offset(-.006, .019),
    Offset(.018, .026),
    Offset(.042, .025),
    Offset(.056, .013),
    Offset(.058, -.004),
    Offset(.05, -.019),
    Offset(.028, -.024),
    Offset(.006, -.021),
    Offset(-.008, -.008),
  ];
  static const _sideFingers = [
    [Offset(.036, -.023), Offset(.046, -.012), Offset(.05, .0)],
    [Offset(.046, -.02), Offset(.053, -.008), Offset(.055, .004)],
    // The thumb across the fingers.
    [Offset(.008, .021), Offset(.026, .016), Offset(.044, .009)],
  ];
  static const _frontFingers = [
    [Offset(.04, -.012), Offset(.057, -.011)],
    [Offset(.041, .0), Offset(.058, .001)],
    [Offset(.04, .012), Offset(.055, .013)],
    // The thumb, along the side.
    [Offset(.006, .02), Offset(.024, .014), Offset(.034, .004)],
  ];

  static BodyPiece _fist(
    BoneFrame frame, {
    required bool front,
    bool far = false,
  }) {
    final details = Path();
    for (final line in front ? _frontFingers : _sideFingers) {
      details.addPath(
        smoothOpen([for (final point in line) frame.at(point)]),
        Offset.zero,
      );
    }
    return _bodyPiece(
      smoothClosed([for (final point in fistPoints) frame.at(point)]),
      details: details,
      far: far,
    );
  }

  /// Where a fist closes round a handle: a little past the wrist.
  static Offset gripAt(Offset elbow, Offset wrist) =>
      wrist + (wrist - elbow) / (wrist - elbow).distance * .03;

  static BodyPiece _gear(Path fill, {Path? details, bool far = false}) =>
      _bodyPiece(fill, details: details, far: far, gear: true);

  /// A rounded bar [length] long [along] its axis, [width] thick.
  static Path _box(Offset center, Offset along, double length, double width) {
    final unit = along / along.distance;
    final across = Offset(-unit.dy, unit.dx);
    final bar = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: length, height: width),
          Radius.circular(width * .3),
        ),
      );
    return bar.transform(
      Float64List.fromList([
        unit.dx, unit.dy, 0, 0, //
        across.dx, across.dy, 0, 0,
        0, 0, 1, 0,
        center.dx, center.dy, 0, 1,
      ]),
    );
  }

  /// A dumbbell end-on (its plate), as a curl shows it side-on.
  static BodyPiece _plate(Offset center, double radius, {bool far = false}) =>
      _gear(
        Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
        details: Path()
          ..addOval(Rect.fromCircle(center: center, radius: radius * .35)),
        far: far,
      );

  /// A dumbbell lying across a fist ([along] the forearm): its handle
  /// through the grip, a plate either side.
  static List<BodyPiece> _dumbbellAcross(Offset center, Offset along) {
    final unit = along / along.distance;
    final across = Offset(-unit.dy, unit.dx);
    return [
      _gear(_box(center, across, .11, .011)),
      for (final end in [center - across * .05, center + across * .05])
        _gear(_box(end, unit, .06, .02)),
    ];
  }

  /// One dumbbell held upright by both hands round its handle, just
  /// under the top plate, the rest hanging below them.
  static List<BodyPiece> _dumbbellHanging(Offset grip) {
    final top = grip - const Offset(0, .034);
    final bottom = grip + const Offset(0, MotionRig.singleDumbbellDrop - .04);
    return [
      _gear(
        _box(
          Offset.lerp(top, bottom, .5)!,
          const Offset(0, 1),
          (bottom - top).distance,
          .012,
        ),
      ),
      _gear(_box(top, const Offset(1, 0), .08, .022)),
      _gear(_box(bottom, const Offset(1, 0), .08, .022)),
    ];
  }

  /// A barbell seen from the front: a bar through both fists.
  static List<BodyPiece> _barbellAcross(Offset left, Offset right) {
    final along = (left - right) / (left - right).distance;
    final from = right - along * .16;
    final to = left + along * .16;
    return [
      _gear(
        _box(Offset.lerp(from, to, .5)!, along, (to - from).distance, .012),
      ),
      for (final end in [right - along * .12, left + along * .12])
        _gear(_box(end, Offset(-along.dy, along.dx), .11, .024)),
    ];
  }

  // Foot: x from the ankle towards the toes, y up (the sole is at -0.035).
  static const footPoints = [
    Offset(-.024, .022),
    Offset(-.044, -.004),
    Offset(-.036, -.034),
    Offset(.04, -.036),
    Offset(.1, -.034),
    Offset(.116, -.022),
    Offset(.098, -.011),
    Offset(.05, .002),
    Offset(.016, .024),
  ];

  // The buttock, in the torso's frame: drawn over the near thigh, as the
  // glute overlaps the top of the thigh side-on. Its outer contour (the
  // first [_buttockEdge] points) is stroked; the side towards the thigh
  // blends in.
  static const buttockPoints = [
    Offset(.1, -.05),
    Offset(.04, -.072),
    Offset(-.02, -.088),
    Offset(-.07, -.078),
    Offset(-.1, -.05),
    Offset(-.113, -.02),
    Offset(-.1, .002),
    Offset(-.06, .006),
    Offset(-.01, -.01),
    Offset(.05, -.028),
  ];
  static const _buttockEdge = 7;

  static const glutePoints = [
    Offset(.074, -.047),
    Offset(.035, -.064),
    Offset(-.02, -.0785),
    Offset(-.064, -.07),
    Offset(-.091, -.046),
    Offset(-.101, -.02),
    Offset(-.088, -.006),
    Offset(-.05, -.004),
    Offset(-.008, -.02),
    Offset(.04, -.034),
  ];

  /// A point of the buttock: its upper part rides the torso, its lower
  /// part the thigh (as it hangs at rest: along the torso, reversed), so
  /// flexing the hip rounds it along the back of the thigh instead of
  /// leaving it hanging below.
  static Offset _skinned(Offset point, BoneFrame torso, BoneFrame thigh) {
    final onTorso = torso.at(point);
    final onThigh = thigh.at(Offset(-point.dx, point.dy));
    final weight = ((.02 - point.dx) / .1).clamp(0.0, 1.0);
    return Offset.lerp(onTorso, onThigh, weight)!;
  }

  static BodyPiece _buttock(Offset Function(Offset) skin) {
    List<Offset> place(List<Offset> points) => [
      for (final point in points) skin(point),
    ];
    final points = place(buttockPoints);
    return _bodyPiece(
      smoothClosed(points),
      edge: smoothOpen(points.sublist(0, _buttockEdge)),
      muscles: [(Muscle.glutes, smoothClosed(place(glutePoints)))],
    );
  }

  // Head and neck, in the torso's frame.
  static const headPoints = [
    Offset(.28, .03),
    Offset(.318, .026),
    Offset(.336, .044),
    Offset(.352, .058),
    Offset(.373, .066),
    Offset(.395, .064),
    Offset(.42, .059),
    Offset(.442, .04),
    Offset(.454, .004),
    Offset(.442, -.035),
    Offset(.412, -.056),
    Offset(.374, -.058),
    Offset(.344, -.042),
    Offset(.322, -.032),
    Offset(.28, -.034),
  ];

  /// How far the side behind is shifted back, so it shows as depth.
  static const farShift = Offset(-.016, 0);

  static BodyPiece _plain(List<Offset> points, BoneFrame frame, bool far) =>
      _bodyPiece(
        smoothClosed([for (final point in points) frame.at(point)]),
        far: far,
      );

  static Offset _joint(RigPose rig, SquatJoint joint) {
    final point = rig.joints[joint]!;
    return Offset(point.x, point.y);
  }

  /// Both arms seen from the front or back ([back]); the torso and legs
  /// are the muscle map's own art. Each arm comes with whatever it holds
  /// and how near it is ([depth], against the shoulders'), so it can go
  /// in front of or behind the body.
  static List<({List<BodyPiece> pieces, double depth})> frontArms(
    ExerciseMotion motion,
    RigView view,
  ) {
    final rig = view.pose;
    Offset at(SquatJoint joint) => _joint(rig, joint);
    final equipment = motion.equipment;
    final gripping =
        equipment != MotionEquipment.none && equipment != MotionEquipment.bench;
    final shoulders =
        (view.depth[SquatJoint.leftShoulder]! +
            view.depth[SquatJoint.rightShoulder]!) /
        2;
    final arms = <({List<BodyPiece> pieces, double depth})>[];
    final grips = <Offset>[];
    for (final left in [true, false]) {
      // Mirror the figure's right arm: the biceps faces out from the
      // front, the triceps from behind.
      final flip = !left;
      SquatJoint pick(SquatJoint l, SquatJoint r) => left ? l : r;
      final shoulder = at(
        pick(SquatJoint.leftShoulder, SquatJoint.rightShoulder),
      );
      final elbowJoint = pick(SquatJoint.leftElbow, SquatJoint.rightElbow);
      final wristJoint = pick(SquatJoint.leftWrist, SquatJoint.rightWrist);
      final elbow = at(elbowJoint);
      final wrist = at(wristJoint);
      final handFrame = BoneFrame(
        wrist,
        wrist - elbow,
        flip: flip,
        length: MotionRig.forearmLength,
      );
      final grip = gripAt(elbow, wrist);
      grips.add(grip);
      arms.add((
        pieces: [
          if (equipment == MotionEquipment.dumbbells)
            ..._dumbbellAcross(grip, wrist - elbow),
          chain(
            forearm.place(
              BoneFrame(
                elbow,
                wrist - elbow,
                flip: flip,
                length: MotionRig.forearmLength,
              ),
              far: false,
            ),
            [
              (
                part: upperArm.place(
                  BoneFrame(
                    shoulder,
                    elbow - shoulder,
                    flip: flip,
                    length: MotionRig.upperArmLength,
                  ),
                  far: false,
                ),
                joint: elbow,
                reach: elbowReach,
              ),
              (
                part: gripping
                    ? _fist(handFrame, front: true)
                    : hand.place(handFrame, far: false),
                joint: wrist,
                reach: wristReach,
              ),
            ],
            far: false,
          ),
        ],
        depth:
            (view.depth[elbowJoint]! + view.depth[wristJoint]!) / 2 - shoulders,
      ));
    }
    // A weight held in both hands goes with the nearer arm, under it.
    final both = switch (equipment) {
      MotionEquipment.barbell => _barbellAcross(grips[0], grips[1]),
      MotionEquipment.dumbbell => _dumbbellHanging(
        Offset.lerp(grips[0], grips[1], .5)!,
      ),
      _ => const <BodyPiece>[],
    };
    if (both.isNotEmpty) {
      final nearer = arms[0].depth >= arms[1].depth ? 0 : 1;
      arms[nearer] = (
        pieces: [...both, ...arms[nearer].pieces],
        depth: arms[nearer].depth,
      );
    }
    return arms;
  }

  /// How far from a joint a folded segment's edge stays hidden.
  static const elbowReach = .05;
  static const wristReach = .034;
  static const kneeReach = .058;
  static const ankleReach = .04;

  /// The body side-on ([view] from [MotionAngle.side]), back to front, in
  /// rig units; [floor] is where hands lie flat.
  static List<BodyPiece> pieces(
    ExerciseMotion motion,
    RigView view, {
    required double floor,
  }) {
    final rig = view.pose;
    Offset at(SquatJoint joint, [Offset shift = Offset.zero]) =>
        _joint(rig, joint) + shift;

    final hips = Offset.lerp(
      at(SquatJoint.leftHip),
      at(SquatJoint.rightHip),
      .5,
    )!;
    final shoulders = Offset.lerp(
      at(SquatJoint.leftShoulder),
      at(SquatJoint.rightShoulder),
      .5,
    )!;
    final torsoFrame = BoneFrame(
      hips,
      shoulders - hips,
      torso: true,
      length: MotionRig.torsoLength,
    );
    // The head keeps its size however the torso leans.
    final headFrame = BoneFrame(
      shoulders - torsoFrame.x * MotionRig.torsoLength,
      shoulders - hips,
      torso: true,
    );
    final equipment = motion.equipment;
    final gripping =
        equipment != MotionEquipment.none && equipment != MotionEquipment.bench;

    ({List<BodyPiece> leg, List<BodyPiece> arm}) side({required bool left}) {
      // The far limbs share the hip and shoulder, and show behind
      // from the knee and elbow down.
      Offset joint(SquatJoint l, SquatJoint r, {bool root = false}) =>
          at(left ? l : r, left && !root ? farShift : Offset.zero);
      final shoulder = joint(
        SquatJoint.leftShoulder,
        SquatJoint.rightShoulder,
        root: true,
      );
      final elbow = joint(SquatJoint.leftElbow, SquatJoint.rightElbow);
      final wrist = joint(SquatJoint.leftWrist, SquatJoint.rightWrist);
      final hip = joint(SquatJoint.leftHip, SquatJoint.rightHip, root: true);
      final knee = joint(SquatJoint.leftKnee, SquatJoint.rightKnee);
      final ankle = joint(SquatJoint.leftAnkle, SquatJoint.rightAnkle);
      final heel = joint(SquatJoint.leftHeel, SquatJoint.rightHeel);
      final toe = joint(SquatJoint.leftFoot, SquatJoint.rightFoot);
      // Hands on the floor or the bench lie flat, fingers forward.
      final pressing =
          motion.anchor == MotionAnchor.hands || wrist.dy > floor - .1;
      final handFrame = pressing
          ? BoneFrame(wrist, const Offset(1, 0))
          : BoneFrame(wrist, wrist - elbow, length: MotionRig.forearmLength);
      final grip = gripAt(elbow, wrist);
      return (
        leg: [
          chain(
            _plain(
              footPoints,
              BoneFrame(ankle, toe - heel, length: MotionRig.footLength),
              left,
            ),
            [
              (
                part: shin.place(
                  BoneFrame(knee, ankle - knee, length: MotionRig.shinLength),
                  far: left,
                ),
                joint: ankle,
                reach: ankleReach,
              ),
              (
                part: thigh.place(
                  BoneFrame(hip, knee - hip, length: MotionRig.thighLength),
                  far: left,
                ),
                joint: knee,
                reach: kneeReach,
              ),
            ],
            far: left,
          ),
        ],
        arm: [
          // A dumbbell held in both hands hangs between them, behind the
          // near arm; plates seen end-on are in front of the fist.
          if (equipment == MotionEquipment.dumbbell && !left)
            ..._dumbbellHanging(grip),
          chain(
            forearm.place(
              BoneFrame(elbow, wrist - elbow, length: MotionRig.forearmLength),
              far: left,
            ),
            [
              (
                part: upperArm.place(
                  BoneFrame(
                    shoulder,
                    elbow - shoulder,
                    length: MotionRig.upperArmLength,
                  ),
                  far: left,
                ),
                joint: elbow,
                reach: elbowReach,
              ),
              (
                part: gripping && !pressing
                    ? _fist(handFrame, front: false, far: left)
                    : hand.place(handFrame, far: left),
                joint: wrist,
                reach: wristReach,
              ),
            ],
            far: left,
          ),
          if (equipment == MotionEquipment.dumbbells)
            _plate(grip, .036, far: left),
          if (equipment == MotionEquipment.barbell && !left) _plate(grip, .07),
        ],
      );
    }

    final far = side(left: true);
    final near = side(left: false);
    final nearThigh = BoneFrame(
      at(SquatJoint.rightHip),
      at(SquatJoint.rightKnee) - at(SquatJoint.rightHip),
      length: MotionRig.thighLength,
    );
    Offset skin(Offset point) => _skinned(point, torsoFrame, nearThigh);
    return [
      ...far.leg,
      ...far.arm,
      _plain(headPoints, headFrame, false),
      torso.place(torsoFrame, far: false, skin: skin),
      ...near.leg,
      _buttock(skin),
      ...near.arm,
    ];
  }
}
