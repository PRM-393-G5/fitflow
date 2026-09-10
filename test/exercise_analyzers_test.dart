import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/plank_analyzer.dart';
import 'package:prm/features/squat_form/domain/pushup_analyzer.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

void main() {
  test('push-up analyzer counts one top-bottom-top rep', () {
    final analyzer = PushupAnalyzer(smoothingFactor: 1, transitionFrames: 2);

    Map<SquatJoint, SquatPoint> pose(double wristX, double wristY) => {
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftElbow: const SquatPoint(.4, .4),
      SquatJoint.leftWrist: SquatPoint(wristX, wristY),
      SquatJoint.leftHip: const SquatPoint(.55, .4),
      SquatJoint.leftAnkle: const SquatPoint(.75, .4),
    };

    void frames(Map<SquatJoint, SquatPoint> value, int count) {
      for (var i = 0; i < count; i++) {
        analyzer.analyze(value);
      }
    }

    frames(pose(.5, .4), 3); // arms straight, top position
    frames(pose(.4, .55), 3); // elbow ~90 degrees, bottom
    expect(analyzer.repetitions, 0);
    frames(pose(.5, .4), 3); // back to top
    expect(analyzer.repetitions, 1);
  });

  test('plank analyzer flags sagging hips and times good holds', () {
    final analyzer = PlankAnalyzer();

    Map<SquatJoint, SquatPoint> pose(double hipY) => {
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftHip: SquatPoint(.55, hipY),
      SquatJoint.leftAnkle: const SquatPoint(.75, .4),
    };

    var result = analyzer.analyze(pose(.4), timestampUs: 1000000);
    expect(result.bodyVisible, isTrue);
    expect(result.score, greaterThan(90));
    result = analyzer.analyze(pose(.4), timestampUs: 3000000);
    expect(result.repetitions, 2);
    result = analyzer.analyze(pose(.5), timestampUs: 4000000);
    expect(result.cue, 'Đừng để hông xệ');
    expect(result.repetitions, 2);
  });
}
