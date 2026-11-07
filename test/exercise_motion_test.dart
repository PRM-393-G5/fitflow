import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/exercise_motions.dart';
import 'package:prm/domain/models/exercise_motion.dart';
import 'package:prm/domain/motion_rig.dart';
import 'package:prm/domain/muscle_volume.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

Map<String, dynamic> motionJson({
  String id = 'lunge',
  List<String> keywords = const ['lunge'],
}) => {
  'id': id,
  'name': 'Lunge',
  'keywords': keywords,
  'view': 'side',
  'anchor': 'feet',
  'equipment': 'dumbbells',
  'muscles': ['quadriceps', 'glutes'],
  'tips': ['Front knee over the ankle'],
  'keyframes': [
    {
      'pose': {'hipL': 20},
      'holdMs': 200,
      'moveMs': 1000,
      'cue': 'Step back',
    },
    {
      'pose': {'hipL': 90, 'kneeL': 90, 'kneeR': 90},
      'holdMs': 0,
      'moveMs': 800,
    },
  ],
};

ExerciseMotion bundled(String id) =>
    ExerciseMotions.bundled.firstWhere((motion) => motion.id == id);

void expectPoint(RigPoint? actual, double x, double y) {
  expect(actual, isNotNull);
  expect(actual!.x, closeTo(x, 1e-4));
  expect(actual.y, closeTo(y, 1e-4));
}

void main() {
  group('ExerciseMotion JSON', () {
    test('round-trips', () {
      final motion = ExerciseMotion.fromJson(motionJson());
      final again = ExerciseMotion.fromJson(motion.toJson());
      expect(again.toJson(), motion.toJson());
      expect(again.equipment, MotionEquipment.dumbbells);
      expect(again.muscles, {Muscle.quadriceps, Muscle.glutes});
      expect(again.keyframes.first.cue, 'Step back');
      expect(again.keyframes.last.cue, isNull);
      expect(again.keyframes.last.pose.kneeR, 90);
      expect(again.keyframes.first.pose.kneeR, 0);
    });

    test('tolerates options it does not know', () {
      final motion = ExerciseMotion.fromJson({
        ...motionJson(),
        'view': 'top',
        'equipment': 'kettlebell',
        'muscles': ['quadriceps', 'nose'],
        'keywords': [' Lunge ', '', 3],
      });
      expect(motion.view, MotionView.side);
      expect(motion.equipment, MotionEquipment.none);
      expect(motion.muscles, {Muscle.quadriceps});
      expect(motion.keywords, ['lunge']);
    });

    test('rejects motions it cannot play', () {
      expect(
        ExerciseMotion.tryParse({...motionJson(), 'keyframes': []}),
        isNull,
      );
      expect(
        ExerciseMotion.tryParse({
          ...motionJson(),
          'keyframes': [
            {
              'pose': {'torso': 'bent'},
            },
          ],
        }),
        isNull,
      );
      expect(ExerciseMotion.tryParse('squat'), isNull);
    });
  });

  group('frameAt', () {
    final motion = ExerciseMotion.fromJson(motionJson());

    test('holds, eases between keyframes and loops', () {
      expect(motion.loopMs, 2000);
      expect(motion.frameAt(100).pose.hipL, 20);
      expect(motion.frameAt(100).keyframe, 0);
      // Halfway through the first move.
      expect(motion.frameAt(700).pose.hipL, closeTo(55, 1e-9));
      // A quarter of the way, eased: slower than linear at the start.
      expect(motion.frameAt(450).pose.hipL, lessThan(20 + 70 * .25));
      expect(motion.frameAt(1300).keyframe, 1);
      // The last keyframe moves back to the first.
      expect(motion.frameAt(1999).pose.hipL, closeTo(20, .01));
      expect(motion.frameAt(2100).pose.hipL, 20);
      expect(motion.frameAt(-100).pose.hipL, motion.frameAt(1900).pose.hipL);
    });

    test('a single held keyframe stays still', () {
      final plank = bundled('plank');
      expect(plank.frameAt(0).pose.torso, 79);
      expect(plank.frameAt(123456).pose.torso, 79);
    });
  });

  group('MotionRig', () {
    // The same numbers are checked in the admin web's motionRig.test.ts.
    test('poses a side-view squat with the feet planted', () {
      final pose = bundled('squat').keyframes[1].pose;
      final rig = MotionRig.anchored(pose, MotionView.side, MotionAnchor.feet);
      expectPoint(rig.joints[SquatJoint.leftKnee], .0464, -.2241);
      expectPoint(rig.joints[SquatJoint.leftWrist], .3233, -.4811);
      expectPoint(rig.joints[SquatJoint.leftHeel], -.13, 0);
      expectPoint(rig.head, .064, -.5543);
    });

    test('mirrors the right side in front view', () {
      final pose = bundled('shoulder-press').keyframes[1].pose;
      final rig = MotionRig.anchored(pose, MotionView.front, MotionAnchor.feet);
      expectPoint(rig.joints[SquatJoint.leftWrist], .1237, -1.1297);
      expectPoint(rig.joints[SquatJoint.rightWrist], -.1237, -1.1297);
      expectPoint(rig.joints[SquatJoint.leftFoot], .2255, 0);
      expectPoint(rig.joints[SquatJoint.rightHeel], -.0955, 0);
    });

    test('moves every angle on its own', () {
      final pose = MotionPose.fromJson({
        'torso': 10,
        'shoulderL': 30,
        'shoulderR': -20,
        'elbowL': 45,
        'elbowR': 10,
        'hipL': 20,
        'hipR': -5,
        'kneeL': 30,
        'ankleL': 5,
        'ankleR': -5,
      });
      final rig = MotionRig.anchored(
        pose,
        MotionView.front,
        MotionAnchor.hands,
      );
      expectPoint(rig.joints[SquatJoint.leftWrist], .183, -.0312);
      expectPoint(rig.joints[SquatJoint.rightKnee], -.2498, .2445);
      expectPoint(rig.joints[SquatJoint.leftHeel], -.1766, .5163);
      expectPoint(rig.head, -.0972, -.3694);
    });

    test('stands about one unit tall on the floor', () {
      final rig = MotionRig.anchored(
        MotionPose.standing,
        MotionView.side,
        MotionAnchor.feet,
      );
      expect(rig.joints[SquatJoint.leftHeel]!.y, closeTo(0, 1e-9));
      final top = rig.head.y - MotionRig.headRadius;
      expect(-top, inInclusiveRange(.9, 1.05));
    });
  });

  group('bundled motions', () {
    test('cover every exercise the camera checks', () {
      expect(
        ExerciseMotions.bundled.map((motion) => motion.id).toSet(),
        ExerciseMotions.ids.values.toSet(),
      );
      for (final motion in ExerciseMotions.bundled) {
        expect(motion.muscles, isNotEmpty, reason: motion.id);
        expect(motion.tips, isNotEmpty, reason: motion.id);
        expect(motion.loopMs, greaterThan(0), reason: motion.id);
      }
    });

    test('keep standing feet flat on the floor', () {
      for (final id in ['squat', 'shoulder-press', 'biceps-curl']) {
        final motion = bundled(id);
        for (final frame in motion.keyframes) {
          final rig = MotionRig.anchored(
            frame.pose,
            motion.view,
            motion.anchor,
          );
          for (final heel in [SquatJoint.leftHeel, SquatJoint.rightHeel]) {
            expect(rig.joints[heel]!.y, closeTo(0, .005), reason: id);
          }
        }
      }
    });

    test('keep the other contact with the floor nearly still', () {
      double drift(ExerciseMotion motion, SquatJoint joint) {
        final start = MotionRig.at(motion, 0).joints[joint]!;
        var worst = 0.0;
        for (var i = 0; i < 100; i++) {
          final point = MotionRig.at(motion, motion.loopMs * i / 100);
          worst = math.max(worst, point.joints[joint]!.distanceTo(start));
        }
        return worst;
      }

      expect(drift(bundled('push-up'), SquatJoint.leftWrist), lessThan(.06));
      expect(drift(bundled('dip'), SquatJoint.leftHeel), lessThan(.06));
    });

    test('frame the whole loop with the floor at the bottom', () {
      for (final motion in ExerciseMotions.bundled) {
        final bounds = MotionRig.bounds(motion);
        expect(bounds.width, greaterThan(0), reason: motion.id);
        for (var i = 0; i < 20; i++) {
          final rig = MotionRig.at(motion, motion.loopMs * i / 20);
          for (final point in rig.joints.values) {
            expect(point.y, lessThanOrEqualTo(bounds.bottom + 1e-9));
          }
        }
      }
    });
  });

  group('MotionLibrary', () {
    test('matches exercises like the camera check', () {
      final library = MotionLibrary();
      expect(
        library.forExercise('Barbell Back Squat', timed: false)?.id,
        'squat',
      );
      expect(library.forExercise('Push-ups', timed: false)?.id, 'push-up');
      expect(library.forExercise('Plank', timed: true)?.id, 'plank');
      expect(
        library.forExercise('Bulgarian Split Squat', timed: false),
        isNull,
      );
      expect(library.forExercise('Dumbbell Row', timed: false), isNull);
      expect(library.forForm(FormExercise.dip)?.id, 'dip');
    });

    test('uses the server copy of a bundled motion', () {
      final served = ExerciseMotion.fromJson({
        ...bundled('squat').toJson(),
        'tips': ['Edited'],
      });
      final library = MotionLibrary([served]);
      expect(library.forExercise('Goblet Squat', timed: false)?.tips, [
        'Edited',
      ]);
    });

    test('matches admin-made motions by keyword, before built-ins', () {
      final library = MotionLibrary([
        ExerciseMotion.fromJson(motionJson()),
        ExerciseMotion.fromJson(motionJson(id: 'goblet', keywords: ['goblet'])),
        ExerciseMotion.fromJson(motionJson(id: 'row', keywords: ['row'])),
        // Keywords on a built-in id are not used for matching.
        ExerciseMotion.fromJson(motionJson(id: 'plank', keywords: ['curl'])),
      ]);
      expect(library.forExercise('Walking Lunges', timed: false)?.id, 'lunge');
      expect(library.forExercise('Goblet Squat', timed: false)?.id, 'goblet');
      expect(library.forExercise('Barbell Row', timed: false)?.id, 'row');
      // "row" starts no word of "Narrow".
      expect(
        library.forExercise('Narrow Push-up', timed: false)?.id,
        'push-up',
      );
      expect(
        library.forExercise('Biceps Curl', timed: false)?.id,
        'biceps-curl',
      );
    });
  });

  group('seen from an angle', () {
    test('side-on is the pose as posed', () {
      final motion = bundled('squat');
      final pose = motion.keyframes[1].pose;
      final flat = MotionRig.anchored(pose, motion.view, motion.anchor);
      final seen = MotionRig.seen(
        pose,
        motion.view,
        motion.anchor,
        MotionAngle.side,
      );
      for (final joint in SquatJoint.values) {
        expectPoint(
          seen.pose.joints[joint],
          flat.joints[joint]!.x,
          flat.joints[joint]!.y,
        );
      }
      // The figure's right side faces the viewer.
      expect(
        seen.depth[SquatJoint.rightKnee],
        greaterThan(seen.depth[SquatJoint.leftKnee]!),
      );
    });

    test('from the front, forward is towards the viewer', () {
      final motion = bundled('squat');
      final bottom = MotionRig.seen(
        motion.keyframes[1].pose,
        motion.view,
        motion.anchor,
        MotionAngle.front,
      );
      final joints = bottom.pose.joints;
      // The figure's left is on screen right, hip width apart.
      expect(
        joints[SquatJoint.leftHip]!.x,
        closeTo(MotionRig.halfHipWidth, 1e-9),
      );
      expect(
        joints[SquatJoint.rightHip]!.x,
        closeTo(-MotionRig.halfHipWidth, 1e-9),
      );
      // Thighs reaching forward point at the viewer: the knees are nearer
      // than the hips, and the thighs look short.
      expect(
        bottom.depth[SquatJoint.leftKnee],
        greaterThan(bottom.depth[SquatJoint.leftHip]!),
      );
      final thigh = joints[SquatJoint.leftKnee]!.distanceTo(
        joints[SquatJoint.leftHip]!,
      );
      expect(thigh, lessThan(MotionRig.thighLength * .5));
    });

    test('from behind, left and right swap sides', () {
      final motion = bundled('shoulder-press');
      final pose = motion.keyframes[0].pose;
      final front = MotionRig.seen(
        pose,
        motion.view,
        motion.anchor,
        MotionAngle.front,
      ).pose;
      final back = MotionRig.seen(
        pose,
        motion.view,
        motion.anchor,
        MotionAngle.back,
      ).pose;
      expect(
        back.joints[SquatJoint.leftWrist]!.x,
        closeTo(-front.joints[SquatJoint.leftWrist]!.x, 1e-9),
      );
    });

    test('feet posed from the front point forward side-on', () {
      final motion = bundled('shoulder-press');
      final side = MotionRig.seen(
        motion.keyframes[0].pose,
        motion.view,
        motion.anchor,
        MotionAngle.side,
      ).pose;
      final toe = side.joints[SquatJoint.rightFoot]!;
      final heel = side.joints[SquatJoint.rightHeel]!;
      expect(toe.x - heel.x, closeTo(MotionRig.footLength, 1e-9));
      expect(toe.y, closeTo(heel.y, 1e-9));
    });

    test('offers the angles a motion reads well from', () {
      expect(MotionRig.angles(bundled('squat')), MotionAngle.values);
      expect(MotionRig.angles(bundled('shoulder-press')), [
        MotionAngle.side,
        MotionAngle.front,
        MotionAngle.back,
      ]);
      // Lying down, only side-on.
      expect(MotionRig.angles(bundled('push-up')), [MotionAngle.side]);
      expect(MotionRig.angles(bundled('plank')), [MotionAngle.side]);
    });
  });
}
