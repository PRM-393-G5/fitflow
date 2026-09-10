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

  test('asks user to move back when body confidence is insufficient', () {
    final result = SquatAnalyzer().analyze({
      SquatJoint.leftShoulder: const SquatPoint(.5, .2, confidence: .2),
    });
    expect(result.bodyVisible, isFalse);
    expect(result.cue, 'Lùi ra để thấy toàn thân');
  });
}
