import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/curl_analyzer.dart';
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

  test('push-up analyzer drops a half rep when the arms leave the frame', () {
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

    frames(pose(.5, .4), 3); // top
    frames(pose(.4, .55), 3); // bottom: depth armed
    // Arms gone for longer than a detector dropout.
    for (var i = 0; i <= analyzer.dropoutFrames; i++) {
      expect(analyzer.analyze(const {}).bodyVisible, isFalse);
    }
    frames(pose(.5, .4), 3); // straight arms back in view
    expect(analyzer.repetitions, 0);
    frames(pose(.4, .55), 3);
    frames(pose(.5, .4), 3);
    expect(analyzer.repetitions, 1);
  });

  test('push-up analyzer keeps the rep through a brief dropout at the '
      'bottom', () {
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

    frames(pose(.5, .4), 3); // top
    frames(pose(.4, .55), 3); // bottom
    frames(const {}, 2); // chest near the floor: landmarks lost
    frames(pose(.5, .4), 3); // pushed back up
    expect(analyzer.repetitions, 1);
  });

  test('push-up analyzer does not count a rep started at the bottom', () {
    final analyzer = PushupAnalyzer(smoothingFactor: 1, transitionFrames: 2);
    Map<SquatJoint, SquatPoint> pose(double wristX, double wristY) => {
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftElbow: const SquatPoint(.4, .4),
      SquatJoint.leftWrist: SquatPoint(wristX, wristY),
      SquatJoint.leftHip: const SquatPoint(.55, .4),
      SquatJoint.leftAnkle: const SquatPoint(.75, .4),
    };
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(pose(.4, .55)); // first seen bent
    }
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(pose(.5, .4));
    }
    expect(analyzer.repetitions, 0);
  });

  test('plank analyzer forgets the old hips after leaving the plank', () {
    final analyzer = PlankAnalyzer();
    Map<SquatJoint, SquatPoint> plank(double hipY) => {
      SquatJoint.leftShoulder: const SquatPoint(.2, .5),
      SquatJoint.leftElbow: const SquatPoint(.2, .65),
      SquatJoint.leftHip: SquatPoint(.45, hipY),
      SquatJoint.leftAnkle: const SquatPoint(.75, .6),
    };
    var us = 0;
    SquatAnalysis feed(Map<SquatJoint, SquatPoint> pose, int count) {
      late SquatAnalysis result;
      for (var i = 0; i < count; i++) {
        us += 66000;
        result = analyzer.analyze(pose, timestampUs: us);
      }
      return result;
    }

    expect(feed(plank(.68), 10).cue, 'Đừng để hông xệ');
    feed(const {}, 30); // dropped to the knees for a couple of seconds
    expect(feed(plank(.545), 1).cue, 'Tốt lắm, giữ nguyên');
  });

  test('standing facing the camera is not read as lying head-on', () {
    // Upright, shoulders .8 torso lengths wide.
    final result = PlankAnalyzer().analyze({
      SquatJoint.leftShoulder: const SquatPoint(.3, .3),
      SquatJoint.rightShoulder: const SquatPoint(.5, .3),
      SquatJoint.leftHip: const SquatPoint(.33, .55),
      SquatJoint.rightHip: const SquatPoint(.47, .55),
      SquatJoint.leftElbow: const SquatPoint(.28, .45),
      SquatJoint.leftAnkle: const SquatPoint(.32, .95),
    });
    expect(result.cue, isNot('Xoay người nằm ngang so với camera'));
  });

  test('push-up analyzer flags sagging hips in torso lengths', () {
    final result = PushupAnalyzer().analyze({
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftElbow: const SquatPoint(.4, .4),
      SquatJoint.leftWrist: const SquatPoint(.5, .4),
      // .05 below the line on a ~.25 torso: ~0.2 torso lengths.
      SquatJoint.leftHip: const SquatPoint(.55, .45),
      SquatJoint.leftAnkle: const SquatPoint(.75, .4),
    });
    expect(result.cue, 'Đừng để hông xệ');
  });

  test('push-up analyzer ignores elbow bends while standing upright', () {
    final analyzer = PushupAnalyzer(smoothingFactor: 1, transitionFrames: 2);

    // Same arm motion as a push-up, but the torso is vertical.
    Map<SquatJoint, SquatPoint> pose(double wristX, double wristY) => {
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftElbow: const SquatPoint(.4, .4),
      SquatJoint.leftWrist: SquatPoint(wristX, wristY),
      SquatJoint.leftHip: const SquatPoint(.3, .7),
      SquatJoint.leftAnkle: const SquatPoint(.3, .95),
    };

    SquatAnalysis? result;
    for (var cycle = 0; cycle < 3; cycle++) {
      for (var i = 0; i < 3; i++) {
        result = analyzer.analyze(pose(.5, .4));
      }
      for (var i = 0; i < 3; i++) {
        result = analyzer.analyze(pose(.4, .55));
      }
    }
    expect(analyzer.repetitions, 0);
    expect(result!.cue, 'Giữ thân nằm ngang để bắt đầu');
  });

  group('plank analyzer', () {
    // Forearm plank: elbow under the shoulder.
    Map<SquatJoint, SquatPoint> pose(double hipY, {double elbowY = .55}) => {
      SquatJoint.leftShoulder: const SquatPoint(.3, .4),
      SquatJoint.leftElbow: SquatPoint(.3, elbowY),
      SquatJoint.leftHip: SquatPoint(.55, hipY),
      SquatJoint.leftAnkle: const SquatPoint(.75, .4),
    };

    /// Feeds [count] frames 100ms apart, starting after [startUs].
    int hold(
      PlankAnalyzer analyzer,
      Map<SquatJoint, SquatPoint> value,
      int startUs,
      int count,
    ) {
      var us = startUs;
      for (var i = 0; i < count; i++) {
        us += 100000;
        analyzer.analyze(value, timestampUs: us);
      }
      return us;
    }

    test('flags sagging hips and times good holds', () {
      final analyzer = PlankAnalyzer();
      final first = analyzer.analyze(pose(.4), timestampUs: 0);
      expect(first.bodyVisible, isTrue);
      expect(first.score, greaterThan(90));
      final us = hold(analyzer, pose(.4), 0, 20);
      expect(analyzer.repetitions, 2);
      final sag = analyzer.analyze(pose(.5), timestampUs: us + 100000);
      expect(sag.cue, 'Đừng để hông xệ');
      expect(sag.repetitions, 2);
    });

    test('keeps the hold time when the body briefly drops out', () {
      final analyzer = PlankAnalyzer();
      final us = hold(analyzer, pose(.4), 0, 21);
      expect(analyzer.repetitions, 2);
      final lost = analyzer.analyze(const {}, timestampUs: us + 100000);
      expect(lost.bodyVisible, isFalse);
      expect(lost.repetitions, 2);
    });

    test('does not credit a long gap (pause/background) as hold time', () {
      final analyzer = PlankAnalyzer();
      var us = hold(analyzer, pose(.4), 0, 11); // 1.1s
      expect(analyzer.repetitions, 1);
      us += 30000000; // 30s without frames
      analyzer.analyze(pose(.4), timestampUs: us);
      expect(analyzer.repetitions, 1);
      hold(analyzer, pose(.4), us, 10); // +1s of real holding
      expect(analyzer.repetitions, 2);
    });

    test('pauseTiming drops the anchor even for a short gap', () {
      final analyzer = PlankAnalyzer();
      final us = hold(analyzer, pose(.4), 0, 9); // 0.9s
      analyzer.pauseTiming();
      // 0.4s later — under the gap cap, but it spans a pause.
      hold(analyzer, pose(.4), us + 300000, 1);
      expect(analyzer.repetitions, 0);
    });

    test('lying flat with arms level with the shoulders is not a plank', () {
      final analyzer = PlankAnalyzer();
      final result = analyzer.analyze(pose(.4, elbowY: .42), timestampUs: 0);
      expect(result.bodyVisible, isFalse);
      hold(analyzer, pose(.4, elbowY: .42), 0, 30);
      expect(analyzer.repetitions, 0);
    });
  });

  test('curl analyzer starts after stepping in close then back', () {
    final analyzer = CurlAnalyzer(smoothingFactor: 1, transitionFrames: 2);

    // One arm, scaled by distance: upper arm [drop] long, the wrist
    // [rise] forearm lengths above the elbow (-1 hanging).
    Map<SquatJoint, SquatPoint> pose(double drop, double rise) => {
      SquatJoint.leftShoulder: const SquatPoint(.5, .2),
      SquatJoint.leftElbow: SquatPoint(.5, .2 + drop),
      SquatJoint.leftWrist: SquatPoint(.5, .2 + drop - rise * drop * .9),
    };

    // Stepping in close: one frame with the arm hanging (too few to
    // start), then half bent. That one frame used to fix the arm length.
    analyzer.analyze(pose(.3, -1));
    for (var i = 0; i < 4; i++) {
      analyzer.analyze(pose(.3, -.3));
    }
    // Back at a normal distance, arm hanging, then one curl.
    for (var i = 0; i < 4; i++) {
      analyzer.analyze(pose(.15, -1));
    }
    expect(analyzer.analyze(pose(.15, -1)).cue, 'Sẵn sàng, cuộn tạ lên');
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(pose(.15, .8));
    }
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(pose(.15, -1));
    }
    expect(analyzer.repetitions, 1);
  });
}
