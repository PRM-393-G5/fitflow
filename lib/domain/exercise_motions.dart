import '../features/squat_form/domain/squat_analyzer.dart';
import 'muscle_volume.dart';
import 'models/exercise_motion.dart';

/// The demos bundled with the app, one per exercise the camera can check.
/// The API's `exercise-motions.defaults.ts` holds the same motions (the
/// admin web edits start from them): keep the two in step.
abstract final class ExerciseMotions {
  /// The motion id of each camera-checked exercise.
  static const ids = {
    FormExercise.squat: 'squat',
    FormExercise.pushup: 'push-up',
    FormExercise.plank: 'plank',
    FormExercise.shoulderPress: 'shoulder-press',
    FormExercise.curl: 'biceps-curl',
    FormExercise.tricepsExtension: 'triceps-extension',
    FormExercise.dip: 'dip',
  };

  static final bundled = <ExerciseMotion>[
    ExerciseMotion(
      id: 'squat',
      name: 'Squat',
      muscles: const {Muscle.quadriceps, Muscle.glutes, Muscle.adductors},
      tips: const [
        'Push your knees out over your toes',
        'Keep your chest up',
        'Heels stay on the floor',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(shoulder: 8, elbow: 12),
          holdMs: 400,
          moveMs: 1200,
          cue: 'Sit back and down',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(
            torso: 42,
            shoulder: 128,
            elbow: 8,
            hip: 122,
            knee: 118,
            ankle: 38,
          ),
          holdMs: 250,
          moveMs: 900,
          cue: 'Drive up through your heels',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'push-up',
      name: 'Push-up',
      muscles: const {Muscle.chest, Muscle.triceps, Muscle.deltoids},
      tips: const [
        'Body in one straight line',
        'Elbows about 45° from your body',
        'Chest close to the floor',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(torso: 72, shoulder: 72, ankle: -6),
          holdMs: 300,
          moveMs: 1000,
          cue: 'Lower your chest',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(torso: 86, elbow: 126, ankle: -10),
          holdMs: 150,
          moveMs: 800,
          cue: 'Push the floor away',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'plank',
      name: 'Plank',
      muscles: const {Muscle.abs, Muscle.obliques},
      tips: const [
        'Elbows under your shoulders',
        'Squeeze your glutes, hips level',
        'Breathe steadily',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(
            torso: 79,
            shoulder: 79,
            elbow: 90,
            ankle: -8,
          ),
          holdMs: 4000,
          moveMs: 0,
          cue: 'Hold a straight line',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'shoulder-press',
      name: 'Shoulder press',
      view: MotionView.front,
      equipment: MotionEquipment.dumbbells,
      muscles: const {Muscle.deltoids, Muscle.triceps, Muscle.trapezius},
      tips: const [
        'Press straight up to full lockout',
        'Both arms move together',
        'Ribs down, no arching',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(
            shoulder: 82,
            elbow: 98,
            hip: 7,
            ankle: -7,
          ),
          holdMs: 300,
          moveMs: 1000,
          cue: 'Press up',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(
            shoulder: 172,
            elbow: 8,
            hip: 7,
            ankle: -7,
          ),
          holdMs: 250,
          moveMs: 1200,
          cue: 'Lower to shoulder height',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'biceps-curl',
      name: 'Biceps curl',
      equipment: MotionEquipment.dumbbells,
      muscles: const {Muscle.biceps, Muscle.forearms},
      tips: const [
        'Elbows pinned to your sides',
        'Straighten fully at the bottom',
        'No swinging',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(shoulder: 4, elbow: 6),
          holdMs: 300,
          moveMs: 1000,
          cue: 'Curl up',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(shoulder: 10, elbow: 140),
          holdMs: 250,
          moveMs: 1200,
          cue: 'Lower slowly',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'triceps-extension',
      name: 'Triceps extension',
      equipment: MotionEquipment.dumbbell,
      muscles: const {Muscle.triceps},
      tips: const [
        'Elbows close to your head',
        'Straighten fully at the top',
        'Upper arms stay still',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(shoulder: 176, elbow: 6),
          holdMs: 300,
          moveMs: 1200,
          cue: 'Lower behind your head',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(shoulder: 182, elbow: 140),
          holdMs: 250,
          moveMs: 1000,
          cue: 'Extend up',
        ),
      ],
    ),
    ExerciseMotion(
      id: 'dip',
      name: 'Dip',
      anchor: MotionAnchor.hands,
      equipment: MotionEquipment.bench,
      muscles: const {Muscle.triceps, Muscle.chest, Muscle.deltoids},
      tips: const [
        'Shoulders down, chest up',
        'Lower until your elbows reach 90°',
        'Straighten fully at the top',
      ],
      keyframes: [
        MotionKeyframe(
          pose: MotionPose.symmetric(
            torso: 2,
            shoulder: -30,
            hip: 82,
            knee: 28,
            ankle: 22,
          ),
          holdMs: 300,
          moveMs: 1000,
          cue: 'Bend your elbows, lower',
        ),
        MotionKeyframe(
          pose: MotionPose.symmetric(
            torso: 6,
            shoulder: -78,
            elbow: 96,
            hip: 88,
            knee: 8,
            ankle: 22,
          ),
          holdMs: 200,
          moveMs: 900,
          cue: 'Press back up',
        ),
      ],
    ),
  ];
}

/// Picks the demo for an exercise: the bundled motions, replaced by the
/// server's copies ([served], from `GET /api/motions`) where it has them.
class MotionLibrary {
  MotionLibrary([List<ExerciseMotion> served = const []])
    : _byId = {
        for (final motion in ExerciseMotions.bundled) motion.id: motion,
        for (final motion in served) motion.id: motion,
      },
      _byKeyword = [
        for (final motion in served)
          if (!ExerciseMotions.ids.containsValue(motion.id) &&
              motion.keywords.isNotEmpty)
            (
              motion,
              RegExp(
                motion.keywords
                    .map((word) => '\\b${RegExp.escape(word)}')
                    .join('|'),
                caseSensitive: false,
              ),
            ),
      ];

  final Map<String, ExerciseMotion> _byId;
  final List<(ExerciseMotion, RegExp)> _byKeyword;

  ExerciseMotion? forForm(FormExercise exercise) =>
      _byId[ExerciseMotions.ids[exercise]];

  /// An admin-made motion whose keyword starts a word of [name] (the
  /// first in the server's order), else the camera-checked exercise
  /// [name] matches, else null.
  ExerciseMotion? forExercise(String name, {required bool timed}) {
    for (final (motion, pattern) in _byKeyword) {
      if (pattern.hasMatch(name)) return motion;
    }
    final form = FormExercise.match(name, timed: timed);
    return form == null ? null : forForm(form);
  }
}
