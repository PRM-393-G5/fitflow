import '../muscle_volume.dart' show Muscle;

/// Which way the demo figure is drawn: [side] faces right (the far limbs
/// are dimmed), [front] faces the viewer with its left side on the right.
enum MotionView { side, front }

/// The part of the body that stays put while the rest moves: the feet in
/// a squat, the hands on the bench in a dip, nothing for [hips].
enum MotionAnchor { feet, hands, hips }

/// What the demo holds or uses: [dumbbells] one in each hand,
/// [dumbbell] one held upright in both hands (overhead extension, goblet
/// squat), a [barbell], or a [bench] under the hands.
enum MotionEquipment { none, dumbbells, dumbbell, barbell, bench }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Joint angles of one demo pose, in degrees. What each angle turns is
/// described in `MotionRig`; 0 everywhere is standing tall, arms down.
class MotionPose {
  const MotionPose._(this.values);

  /// The angles in JSON key order: torso, then left/right pairs.
  static const fields = [
    'torso',
    'shoulderL',
    'shoulderR',
    'elbowL',
    'elbowR',
    'hipL',
    'hipR',
    'kneeL',
    'kneeR',
    'ankleL',
    'ankleR',
  ];

  static const standing = MotionPose._([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  /// Both sides alike, as most demos move.
  factory MotionPose.symmetric({
    double torso = 0,
    double shoulder = 0,
    double elbow = 0,
    double hip = 0,
    double knee = 0,
    double ankle = 0,
  }) => MotionPose._(
    List.unmodifiable([
      torso,
      shoulder,
      shoulder,
      elbow,
      elbow,
      hip,
      hip,
      knee,
      knee,
      ankle,
      ankle,
    ]),
  );

  /// Missing angles are 0; a non-number throws a [FormatException].
  factory MotionPose.fromJson(Map<String, dynamic> json) => MotionPose._(
    List.unmodifiable([
      for (final field in fields)
        switch (json[field]) {
          null => 0.0,
          final num value when value.isFinite => value.toDouble(),
          final other => throw FormatException('Bad $field: $other'),
        },
    ]),
  );

  final List<double> values;

  double get torso => values[0];
  double get shoulderL => values[1];
  double get shoulderR => values[2];
  double get elbowL => values[3];
  double get elbowR => values[4];
  double get hipL => values[5];
  double get hipR => values[6];
  double get kneeL => values[7];
  double get kneeR => values[8];
  double get ankleL => values[9];
  double get ankleR => values[10];

  /// Angle by angle from this pose (t = 0) to [other] (t = 1).
  MotionPose lerp(MotionPose other, double t) => MotionPose._([
    for (var i = 0; i < values.length; i++)
      values[i] + (other.values[i] - values[i]) * t,
  ]);

  Map<String, double> toJson() => {
    for (var i = 0; i < fields.length; i++) fields[i]: values[i],
  };
}

/// A pose the demo holds for [holdMs], then moves away from over [moveMs]
/// towards the next keyframe (the last one moves back to the first).
class MotionKeyframe {
  const MotionKeyframe({
    required this.pose,
    this.holdMs = 0,
    this.moveMs = 1000,
    this.cue,
  });

  final MotionPose pose;
  final int holdMs;
  final int moveMs;

  /// Shown from this keyframe until the next one, e.g. "Sit back".
  final String? cue;

  Map<String, Object> toJson() => {
    'pose': pose.toJson(),
    'holdMs': holdMs,
    'moveMs': moveMs,
    'cue': ?cue,
  };

  factory MotionKeyframe.fromJson(Map<String, dynamic> json) => MotionKeyframe(
    pose: MotionPose.fromJson(json['pose'] as Map<String, dynamic>),
    holdMs: ((json['holdMs'] as num?) ?? 0).toInt().clamp(0, 60000),
    moveMs: ((json['moveMs'] as num?) ?? 0).toInt().clamp(0, 60000),
    cue: switch (json['cue']) {
      final String cue when cue.trim().isNotEmpty => cue.trim(),
      _ => null,
    },
  );
}

/// The pose a motion shows at some moment, and the keyframe it is in.
typedef MotionFrame = ({MotionPose pose, int keyframe});

/// A looping stick-figure demo of one exercise: keyframed joint angles,
/// the muscles it works (lit up) and short form tips. Bundled ones
/// live in `ExerciseMotions`; the admin web can override them and add
/// more through `GET /api/motions`.
class ExerciseMotion {
  const ExerciseMotion({
    required this.id,
    required this.name,
    required this.keyframes,
    this.keywords = const [],
    this.view = MotionView.side,
    this.anchor = MotionAnchor.feet,
    this.equipment = MotionEquipment.none,
    this.muscles = const {},
    this.tips = const [],
  }) : assert(keyframes.length > 0);

  final String id;
  final String name;

  /// Words that pick this motion for an exercise named with any of them;
  /// unused by the built-in motions, which match like the camera check.
  final List<String> keywords;
  final MotionView view;
  final MotionAnchor anchor;
  final MotionEquipment equipment;
  final List<MotionKeyframe> keyframes;

  /// The muscles it mainly works, lit up on the figure.
  final Set<Muscle> muscles;
  final List<String> tips;

  /// Length of one loop; 0 for a single held pose.
  int get loopMs =>
      keyframes.fold(0, (sum, frame) => sum + frame.holdMs + frame.moveMs);

  /// The pose [ms] into the loop (any value; it wraps around).
  MotionFrame frameAt(double ms) {
    final loop = loopMs;
    if (loop == 0) return (pose: keyframes.first.pose, keyframe: 0);
    var t = ms % loop;
    for (final (index, frame) in keyframes.indexed) {
      if (t < frame.holdMs) return (pose: frame.pose, keyframe: index);
      t -= frame.holdMs;
      if (t < frame.moveMs) {
        final next = keyframes[(index + 1) % keyframes.length].pose;
        return (
          pose: frame.pose.lerp(next, _ease(t / frame.moveMs)),
          keyframe: index,
        );
      }
      t -= frame.moveMs;
    }
    return (pose: keyframes.first.pose, keyframe: 0);
  }

  /// Smoothstep: starts and stops gently, like a controlled rep.
  static double _ease(double t) => t * t * (3 - 2 * t);

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'keywords': keywords,
    'view': view.name,
    'anchor': anchor.name,
    'equipment': equipment.name,
    'muscles': muscles.map((muscle) => muscle.name).toList(),
    'tips': tips,
    'keyframes': keyframes.map((frame) => frame.toJson()).toList(),
  };

  /// Unknown views, anchors, equipment and muscles fall back or are
  /// skipped, so a newer server can add options without breaking older
  /// apps; a motion without keyframes throws a [FormatException].
  factory ExerciseMotion.fromJson(Map<String, dynamic> json) {
    final keyframes = [
      for (final frame in json['keyframes'] as List)
        MotionKeyframe.fromJson(frame as Map<String, dynamic>),
    ];
    if (keyframes.isEmpty) throw const FormatException('No keyframes');
    final known = {for (final muscle in Muscle.values) muscle.name: muscle};
    return ExerciseMotion(
      id: json['id'] as String,
      name: json['name'] as String,
      keywords: [
        for (final word in json['keywords'] as List? ?? const [])
          if (word is String && word.trim().isNotEmpty)
            word.trim().toLowerCase(),
      ],
      view: _enumByName(MotionView.values, json['view'], MotionView.side),
      anchor: _enumByName(
        MotionAnchor.values,
        json['anchor'],
        MotionAnchor.feet,
      ),
      equipment: _enumByName(
        MotionEquipment.values,
        json['equipment'],
        MotionEquipment.none,
      ),
      keyframes: keyframes,
      muscles: {
        for (final name in json['muscles'] as List? ?? const []) ?known[name],
      },
      tips: [
        for (final tip in json['tips'] as List? ?? const [])
          if (tip is String && tip.trim().isNotEmpty) tip.trim(),
      ],
    );
  }

  /// The motion in [json], or null when it is malformed.
  static ExerciseMotion? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return ExerciseMotion.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
