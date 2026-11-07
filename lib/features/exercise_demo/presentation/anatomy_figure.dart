import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/muscle_body_map.dart';
import '../../../domain/models/exercise_motion.dart';
import '../../../domain/motion_rig.dart';
import '../../../domain/muscle_volume.dart';
import '../../squat_form/domain/squat_analyzer.dart' show SquatJoint;
import 'profile_figure.dart';

/// The muscle map's body art (front or back) without its arms (drawn in
/// its style by [ProfileBody.frontArms]) and with the head on its own,
/// legs cut into parts laid along the bones of [MotionRig].
///
/// Art units: the 724 × 1448 box of the front view; the back view is the
/// same figure [dx] further right. Parts are cut on the screen-left side
/// and mirrored for the other.
class AnatomyArt {
  AnatomyArt._(this.dx, {required bool front}) : parts = _cut(dx, front);

  static final front = AnatomyArt._(0, front: true);
  static final back = AnatomyArt._(718.3, front: false);

  /// Art units per rig unit (the torso, hips to shoulders, matches).
  static const scale = 1172.0;

  final double dx;
  final Map<AnatomyPart, AnatomyPiece> parts;

  double get centerX => 364.45 + dx;

  // Joints of the screen-left leg in the front art.
  static const _hip = Offset(296, 670);
  static const _knee = Offset(292, 980);
  static const _ankle = Offset(290, 1248);
  Offset get hip => _hip.translate(dx, 0);
  Offset get knee => _knee.translate(dx, 0);
  Offset get ankle => _ankle.translate(dx, 0);
  Offset get hips => Offset(centerX, 670);
  Offset get shoulders => Offset(centerX, 330);

  /// Where the head is cut off and hung: the base of the neck.
  Offset get neck => Offset(centerX, _neckY);
  static const _neckY = 292.0;

  Offset mirror(Offset point) => Offset(2 * centerX - point.dx, point.dy);

  // The whole arm, cut from the torso along the armpit (the arm and torso
  // art join down to y ≈ 448) and clear of the waist below it.
  static const _arm = [
    Offset(150, 270),
    Offset(250, 284),
    Offset(263, 318),
    Offset(259, 360),
    Offset(253, 420),
    Offset(249, 449),
    Offset(240, 480),
    Offset(236, 524),
    Offset(228, 600),
    Offset(212, 660),
    Offset(195, 720),
    Offset(175, 860),
    Offset(10, 860),
    Offset(10, 640),
    Offset(100, 480),
    Offset(140, 330),
  ];
  static const _thigh = [
    Offset(228, 640),
    Offset(364, 765),
    Offset(364, 985),
    Offset(228, 985),
  ];
  static const _shin = [
    Offset(228, 985),
    Offset(364, 985),
    Offset(364, 1250),
    Offset(228, 1250),
  ];
  static const _foot = [
    Offset(200, 1250),
    Offset(364, 1250),
    Offset(364, 1380),
    Offset(200, 1380),
  ];

  static Map<AnatomyPart, AnatomyPiece> _cut(double dx, bool front) {
    final art = muscleArt(front: front);
    final center = 364.45 + dx;
    AnatomyPiece piece(Path region) => AnatomyPiece(
      outline: Path.combine(PathOperation.intersect, art.outline, region),
      muscles: [
        for (final (muscle, path) in art.parts)
          if (Path.combine(PathOperation.intersect, path, region) case final cut
              when !cut.getBounds().isEmpty)
            (muscle, cut),
      ],
    );
    Path polygon(List<Offset> points, bool mirrored) => Path()
      ..addPolygon([
        for (final point in points)
          mirrored
              ? Offset(2 * center - point.dx - dx, point.dy)
              : point.translate(dx, 0),
      ], true);
    final legs = <AnatomyPart, Path>{};
    var torso = Path()
      ..addRect(Rect.fromLTRB(dx - 100, _neckY, dx + 900, 1600));
    final head = Path()
      ..addRect(Rect.fromLTRB(dx - 100, -100, dx + 900, _neckY));
    for (final mirrored in [false, true]) {
      for (final (part, shape) in [
        (AnatomyPart.thigh, _thigh),
        (AnatomyPart.shin, _shin),
        (AnatomyPart.foot, _foot),
      ]) {
        legs[part.side(mirrored: mirrored)] = polygon(shape, mirrored);
      }
      torso = Path.combine(
        PathOperation.difference,
        torso,
        polygon(_arm, mirrored),
      );
    }
    for (final leg in legs.values) {
      torso = Path.combine(PathOperation.difference, torso, leg);
    }
    return {
      AnatomyPart.torso: piece(torso),
      AnatomyPart.head: piece(head),
      for (final MapEntry(key: part, value: region) in legs.entries)
        part: piece(region),
    };
  }
}

enum AnatomyPart {
  torso,
  head,
  thigh,
  shin,
  foot,
  thighMirrored,
  shinMirrored,
  footMirrored;

  /// The screen-left art of a leg part, or its [mirrored] copy.
  AnatomyPart side({required bool mirrored}) =>
      mirrored ? AnatomyPart.values[index + 3] : this;
}

class AnatomyPiece {
  const AnatomyPiece({required this.outline, required this.muscles});

  final Path outline;
  final List<(Muscle?, Path)> muscles;
}

/// The transform laying the art from [a0] to [a1] along [p0] → [p1]:
/// turned and stretched along the bone (a bone pointing at the viewer
/// shows short).
Matrix4 _alongBone(Offset a0, Offset a1, Offset p0, Offset p1) {
  final art = a1 - a0;
  final bone = p1 - p0;
  // A bone seen end-on keeps a sliver, pointing down.
  final along = bone.distance < 1e-6 ? Offset(0, art.distance * 1e-3) : bone;
  return Matrix4.identity()
    ..translateByDouble(p0.dx, p0.dy, 0, 1)
    ..rotateZ(along.direction)
    ..scaleByDouble(along.distance / art.distance, 1, 1, 1)
    ..rotateZ(-art.direction)
    ..translateByDouble(-a0.dx, -a0.dy, 0, 1);
}

/// One drawn art part and where it goes.
typedef PlacedPart = ({AnatomyPart art, Matrix4 matrix});

/// The torso, head and legs seen from the front or back ([view]) in art
/// units: legs nearer than the hips go [inFront] of the torso, the others
/// [behind] it; [joints] close the legs' seams over the torso.
class AnatomyFrame {
  AnatomyFrame(this.art, RigView view) {
    final rig = view.pose;
    final back = art == AnatomyArt.back;
    Offset at(SquatJoint joint) {
      final point = rig.joints[joint]!;
      return Offset(point.x, point.y) * AnatomyArt.scale;
    }

    Offset mid(SquatJoint a, SquatJoint b) => Offset.lerp(at(a), at(b), .5)!;
    final hips = mid(SquatJoint.leftHip, SquatJoint.rightHip);
    final shoulders = mid(SquatJoint.leftShoulder, SquatJoint.rightShoulder);
    torso = (
      art: AnatomyPart.torso,
      matrix: _alongBone(art.hips, art.shoulders, hips, shoulders),
    );
    // The head hangs from the neck at its own size, turned with the torso.
    final up = shoulders - hips;
    final direction = up.distance < 1e-6 ? -math.pi / 2 : up.direction;
    final neck =
        shoulders +
        Offset.fromDirection(direction) *
            (art.shoulders.dy - art.neck.dy) *
            (up.distance / (art.shoulders - art.hips).distance).clamp(.3, 1);
    head = (
      art: AnatomyPart.head,
      matrix: Matrix4.identity()
        ..translateByDouble(neck.dx, neck.dy, 0, 1)
        ..rotateZ(direction + math.pi / 2)
        ..translateByDouble(-art.neck.dx, -art.neck.dy, 0, 1),
    );
    final hipDepth =
        (view.depth[SquatJoint.leftHip]! + view.depth[SquatJoint.rightHip]!) /
        2;
    for (final left in [true, false]) {
      // From the front the figure's left leg is on screen right (the art's
      // mirrored copy); from behind, on screen left.
      final mirrored = back ? !left : left;
      Offset place(Offset point) => mirrored ? art.mirror(point) : point;
      SquatJoint pick(SquatJoint l, SquatJoint r) => left ? l : r;
      final kneeJoint = pick(SquatJoint.leftKnee, SquatJoint.rightKnee);
      final hip = at(pick(SquatJoint.leftHip, SquatJoint.rightHip));
      final knee = at(kneeJoint);
      final ankle = at(pick(SquatJoint.leftAnkle, SquatJoint.rightAnkle));
      final shin = ankle - knee;
      final leg = [
        (
          art: AnatomyPart.thigh.side(mirrored: mirrored),
          matrix: _alongBone(place(art.hip), place(art.knee), hip, knee),
        ),
        (
          art: AnatomyPart.shin.side(mirrored: mirrored),
          matrix: _alongBone(place(art.knee), place(art.ankle), knee, ankle),
        ),
        (
          art: AnatomyPart.foot.side(mirrored: mirrored),
          // The foot hangs on from the shin.
          matrix: _alongBone(
            place(art.ankle),
            place(art.ankle + const Offset(0, 100)),
            ankle,
            ankle +
                (shin.distance < 1e-6
                        ? const Offset(0, 1)
                        : shin / shin.distance) *
                    100,
          ),
        ),
      ];
      final nearer = view.depth[kneeJoint]! >= hipDepth - .02;
      (nearer ? inFront : behind).addAll(leg);
      if (nearer) {
        joints.addAll([
          (at: hip, radius: 52.0),
          (at: knee, radius: 36.0),
          (at: ankle, radius: 22.0),
        ]);
      }
    }
  }

  final AnatomyArt art;
  late final PlacedPart torso;
  late final PlacedPart head;
  final behind = <PlacedPart>[];
  final inFront = <PlacedPart>[];
  final joints = <({Offset at, double radius})>[];
}

/// A [BodyPiece] as the painter draws it; muscle-map art pieces carry a
/// [matrix] and untracked (null) muscles.
typedef _ScenePiece = ({
  List<({Path fill, List<(Muscle?, Path)> muscles, Path? seams})> layers,
  Path outline,
  Path? edge,
  Path? unstroked,
  List<(Path, Path)> contours,
  Path? details,
  bool far,
  bool gear,
  Matrix4? matrix,
});

_ScenePiece _fromBody(BodyPiece piece) => (
  layers: [
    for (final layer in piece.layers)
      (fill: layer.fill, muscles: layer.muscles, seams: layer.seams),
  ],
  outline: piece.outline,
  edge: piece.edge,
  unstroked: piece.unstroked,
  contours: piece.contours,
  details: piece.details,
  far: piece.far,
  gear: piece.gear,
  matrix: null,
);

/// What a frame draws, in rig units: pieces back to front (a piece with a
/// matrix is art drawn through it), and joint fills drawn after piece
/// [capsAfter] to close the seams of the front art's legs.
class _Scene {
  _Scene.flat(ExerciseMotion motion, RigView view, {required bool back}) {
    final frame = AnatomyFrame(back ? AnatomyArt.back : AnatomyArt.front, view);
    final toRig = Matrix4.diagonal3Values(
      1 / AnatomyArt.scale,
      1 / AnatomyArt.scale,
      1,
    );
    void art(PlacedPart part) {
      final piece = frame.art.parts[part.art]!;
      pieces.add((
        layers: [(fill: piece.outline, muscles: piece.muscles, seams: null)],
        outline: piece.outline,
        edge: null,
        unstroked: null,
        contours: const [],
        details: null,
        far: false,
        gear: false,
        matrix: toRig.multiplied(part.matrix),
      ));
    }

    final arms = ProfileBody.frontArms(motion, view);
    // Arms reaching behind the body (a dip, behind the head) go first.
    for (final arm in arms.where((arm) => arm.depth < -.03)) {
      pieces.addAll(arm.pieces.map(_fromBody));
    }
    frame.behind.forEach(art);
    art(frame.torso);
    art(frame.head);
    capsAfter = pieces.length - 1;
    caps.addAll([
      for (final joint in frame.joints)
        (
          at: joint.at / AnatomyArt.scale,
          radius: joint.radius / AnatomyArt.scale,
        ),
    ]);
    frame.inFront.forEach(art);
    for (final arm in arms.where((arm) => arm.depth >= -.03)) {
      pieces.addAll(arm.pieces.map(_fromBody));
    }
  }

  _Scene.side(ExerciseMotion motion, RigView view, {required double floor}) {
    pieces.addAll(
      ProfileBody.pieces(motion, view, floor: floor).map(_fromBody),
    );
  }

  final pieces = <_ScenePiece>[];
  final caps = <({Offset at, double radius})>[];

  /// The leg joints close over the torso, after this piece.
  int capsAfter = -1;

  Rect bounds() {
    Rect? box;
    void include(Path path) {
      final bounds = path.getBounds();
      if (bounds.isEmpty) return;
      box = box == null ? bounds : box!.expandToInclude(bounds);
    }

    for (final piece in pieces) {
      final matrix = piece.matrix;
      if (matrix == null) {
        include(piece.outline);
        continue;
      }
      include(piece.outline.transform(matrix.storage));
      // The art's head (an untracked part) lies outside its outline.
      for (final layer in piece.layers) {
        for (final (muscle, path) in layer.muscles) {
          if (muscle == null) include(path.transform(matrix.storage));
        }
      }
    }
    return box!;
  }
}

/// Paints [motion] as the muscle map's body, its [worked] muscles lit:
/// the muscle map's own art from the front, its style drawn side-on.
class AnatomyPainter extends CustomPainter {
  AnatomyPainter({
    required this.motion,
    required this.progress,
    required this.worked,
    required this.body,
    required this.muscle,
    required this.workedColor,
    required this.outline,
    required this.floor,
    MotionAngle? angle,
    this.gear = const Color(0xFF64748B),
  }) : angle = angle ?? MotionAngle.of(motion.view),
       super(repaint: progress);

  final ExerciseMotion motion;

  /// Where the figure is seen from.
  final MotionAngle angle;
  final Animation<double> progress;
  final Set<Muscle> worked;
  final Color body;
  final Color muscle;
  final Color workedColor;
  final Color outline;
  final Color floor;

  /// Weights and their plates.
  final Color gear;

  /// The framing of each motion from each angle: a painter is made on
  /// every rebuild, the framing samples a whole loop.
  static final _framing =
      Expando<Map<MotionAngle, (math.Rectangle<double>, Rect)>>();

  late final (math.Rectangle<double>, Rect) _frame =
      (_framing[motion] ??= {})[angle] ??= () {
        final rig = MotionRig.bounds(motion, angle);
        return (rig, _loopBox(rig));
      }();
  math.Rectangle<double> get _rigBounds => _frame.$1;
  Rect get _box => _frame.$2;

  _Scene _sceneAt(double ms, double floor) {
    final view = MotionRig.seenAt(motion, ms, angle);
    return angle == MotionAngle.side
        ? _Scene.side(motion, view, floor: floor)
        : _Scene.flat(motion, view, back: angle == MotionAngle.back);
  }

  /// Everything drawn over a loop (the bench too), so the figure is
  /// framed once.
  Rect _loopBox(math.Rectangle<double> rig) {
    var box = _sceneAt(0, rig.bottom).bounds();
    for (var i = 1; i < 24; i++) {
      box = box.expandToInclude(
        _sceneAt(motion.loopMs * i / 24, rig.bottom).bounds(),
      );
    }
    return box.expandToInclude(
      Rect.fromLTWH(rig.left, rig.top, rig.width, rig.height),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = _box;
    // Side-on, the soles are the rig's; the front art's feet reach lower.
    final floorY = angle == MotionAngle.side
        ? _rigBounds.bottom
        : math.max(box.bottom, _rigBounds.bottom);
    final pad = size.shortestSide * .07;
    final scale = math.min(
      (size.width - pad * 2) / box.width,
      (size.height - pad * 2) / (floorY - box.top),
    );
    final ms = progress.value * motion.loopMs;
    final scene = _sceneAt(ms, _rigBounds.bottom);

    canvas
      ..save()
      ..translate(
        (size.width - box.width * scale) / 2 - box.left * scale,
        size.height - pad - floorY * scale,
      )
      ..scale(scale);
    final px = 1 / scale;
    canvas.drawLine(
      Offset(box.left - size.width * px, floorY),
      Offset(box.right + size.width * px, floorY),
      Paint()
        ..color = floor
        ..strokeWidth = 2 * px,
    );
    // The bench is behind the body, except seen from behind.
    final bench = motion.equipment == MotionEquipment.bench
        ? _bench(ms, floorY)
        : null;
    if (bench != null && angle != MotionAngle.back) {
      canvas.drawRRect(bench, Paint()..color = floor);
    }

    final pulse = (math.sin(ms / 1000 * 2 * math.pi) + 1) / 2;
    final lit = Color.lerp(
      Color.lerp(workedColor, body, .3),
      workedColor,
      pulse,
    )!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * px
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = outline;
    final gearFill = Paint()..color = gear;
    final gearStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * px
      ..color = Color.lerp(gear, const Color(0xFF000000), .3)!;
    final shade = Paint()..color = const Color(0x12000000);
    final bodyPaint = Paint()..color = body;
    // Splits muscle heads with the body's colour, like the muscle map.
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Segment.gap
      ..strokeCap = StrokeCap.round
      ..color = body;

    for (final (index, piece) in scene.pieces.indexed) {
      canvas.save();
      if (piece.matrix case final matrix?) canvas.transform(matrix.storage);
      if (piece.gear) {
        canvas
          ..drawPath(piece.outline, gearFill)
          ..drawPath(piece.outline, gearStroke);
        if (piece.details case final details?) {
          canvas.drawPath(details, gearStroke);
        }
      } else {
        for (final layer in piece.layers) {
          canvas.drawPath(layer.fill, bodyPaint);
          for (final (m, path) in layer.muscles) {
            canvas.drawPath(
              path,
              Paint()
                ..color = m == null
                    ? body
                    : worked.contains(m)
                    ? lit
                    : muscle,
            );
          }
          if (layer.seams case final seams?) canvas.drawPath(seams, seam);
        }
        for (final (line, clip) in piece.contours) {
          canvas
            ..save()
            ..clipPath(clip)
            ..drawPath(line, stroke)
            ..restore();
        }
        final edge = piece.edge ?? piece.outline;
        if (piece.unstroked case final region?) {
          final everywhere = Path()
            ..addRect(piece.outline.getBounds().inflate(1));
          canvas
            ..save()
            ..clipPath(
              Path.combine(PathOperation.difference, everywhere, region),
            )
            ..drawPath(edge, stroke)
            ..restore();
        } else {
          canvas.drawPath(edge, stroke);
        }
        if (piece.details case final details?) {
          canvas.drawPath(details, stroke);
        }
      }
      if (piece.far) canvas.drawPath(piece.outline, shade);
      canvas.restore();
      if (index == scene.capsAfter) {
        for (final cap in scene.caps) {
          canvas.drawCircle(cap.at, cap.radius, bodyPaint);
        }
      }
    }
    if (bench != null && angle == MotionAngle.back) {
      canvas.drawRRect(bench, Paint()..color = floor.withValues(alpha: .92));
    }
    canvas.restore();
  }

  /// The bench under the hands at [ms], down to [floorY].
  RRect _bench(double ms, double floorY) {
    final rig = MotionRig.seenAt(motion, ms, angle).pose;
    final left = rig.joints[SquatJoint.leftWrist]!;
    final right = rig.joints[SquatJoint.rightWrist]!;
    final hands = Offset((left.x + right.x) / 2, (left.y + right.y) / 2);
    final side = angle == MotionAngle.side;
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(
        hands.dx - (side ? MotionRig.benchBehind : MotionRig.benchHalfWidth),
        hands.dy + .012,
        hands.dx + (side ? MotionRig.benchAhead : MotionRig.benchHalfWidth),
        floorY,
      ),
      const Radius.circular(.014),
    );
  }

  @override
  bool shouldRepaint(AnatomyPainter old) =>
      old.motion != motion || old.progress != progress || old.angle != angle;
}
