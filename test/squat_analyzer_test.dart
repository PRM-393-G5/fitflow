import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

void main() {
  test('angleDegrees calculates a right angle', () {
    expect(
      angleDegrees(
        const SquatPoint(0, 0),
        const SquatPoint(0, 1),
        const SquatPoint(1, 1),
      ),
      closeTo(90, .001),
    );
  });

  test(
    'counts one full standing-bottom-standing cycle without double count',
    () {
      final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);

      Map<SquatJoint, SquatPoint> pose(double kneeX, double kneeY) => {
        SquatJoint.leftShoulder: const SquatPoint(.4, .1),
        SquatJoint.leftHip: const SquatPoint(.4, .45),
        SquatJoint.leftKnee: SquatPoint(kneeX, kneeY),
        SquatJoint.leftAnkle: const SquatPoint(.4, .9),
        SquatJoint.leftFoot: const SquatPoint(.5, .9),
      };

      void frames(Map<SquatJoint, SquatPoint> value, int count) {
        for (var i = 0; i < count; i++) {
          analyzer.analyze(value);
        }
      }

      frames(pose(.4, .7), 3); // standing
      frames(pose(.7, .65), 3); // bottom, ~90 degrees
      expect(analyzer.repetitions, 0);
      frames(pose(.4, .7), 3); // standing again
      expect(analyzer.repetitions, 1);
      frames(pose(.4, .7), 5);
      expect(analyzer.repetitions, 1);
    },
  );

  test('records a rep with knee-valgus fault', () {
    final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);

    // Knee pushed far off the ankle line -> valgus; depth ~90 deg.
    Map<SquatJoint, SquatPoint> pose(double kneeX, double kneeY) => {
      SquatJoint.leftShoulder: const SquatPoint(.4, .1),
      SquatJoint.leftHip: const SquatPoint(.4, .45),
      SquatJoint.leftKnee: SquatPoint(kneeX, kneeY),
      SquatJoint.leftAnkle: const SquatPoint(.4, .9),
      SquatJoint.leftFoot: const SquatPoint(.5, .9),
    };

    var us = 0;
    void frames(Map<SquatJoint, SquatPoint> value, int count) {
      for (var i = 0; i < count; i++) {
        us += 100000; // 100ms per frame, strictly increasing
        analyzer.analyze(value, timestampUs: us);
      }
    }

    frames(pose(.4, .7), 3); // standing
    frames(pose(.7, .65), 6); // deep + valgus
    frames(pose(.4, .7), 5); // stand back up

    expect(analyzer.repetitions, 1);
    expect(analyzer.repRecords, hasLength(1));
    expect(analyzer.repRecords.single.faults, contains('kneeValgus'));
    expect(analyzer.repRecords.single.minKneeAngle, lessThan(105));
  });

  test('clean aligned rep records no faults', () {
    final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);

    // Knee stays over the ankle-to-toe line while reaching depth.
    Map<SquatJoint, SquatPoint> pose(double kneeX, double kneeY) => {
      SquatJoint.leftShoulder: const SquatPoint(.4, .1),
      SquatJoint.leftHip: const SquatPoint(.4, .45),
      SquatJoint.leftKnee: SquatPoint(kneeX, kneeY),
      SquatJoint.leftAnkle: const SquatPoint(.4, .9),
      SquatJoint.leftFoot: const SquatPoint(.58, .9),
    };

    var us = 0;
    void frames(Map<SquatJoint, SquatPoint> value, int count) {
      for (var i = 0; i < count; i++) {
        us += 300000; // 300ms per frame, strictly increasing
        analyzer.analyze(value, timestampUs: us);
      }
    }

    frames(pose(.4, .7), 3);
    frames(pose(.65, .75), 6); // ~80 deg, aligned
    frames(pose(.4, .7), 5);

    expect(analyzer.repRecords, hasLength(1));
    expect(analyzer.repRecords.single.faults, isEmpty);
  });

  test('asks user to move back when body confidence is insufficient', () {
    final result = SquatAnalyzer().analyze({
      SquatJoint.leftShoulder: const SquatPoint(.5, .2, confidence: .2),
    });
    expect(result.bodyVisible, isFalse);
    expect(result.cue, 'Lùi ra để thấy toàn thân');
  });
}
