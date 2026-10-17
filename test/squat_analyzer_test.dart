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

  group('knee valgus is directional', () {
    // Left leg drives the angles; the right leg mirrors it about the
    // midline at x=.5 (to the left knee's +x side).
    Map<SquatJoint, SquatPoint> pose(double kneeX, double kneeY) => {
      SquatJoint.leftShoulder: const SquatPoint(.4, .1),
      SquatJoint.leftHip: const SquatPoint(.4, .45),
      SquatJoint.rightHip: const SquatPoint(.6, .45),
      SquatJoint.leftKnee: SquatPoint(kneeX, kneeY),
      SquatJoint.rightKnee: SquatPoint(1 - kneeX, kneeY),
      SquatJoint.leftAnkle: const SquatPoint(.4, .9),
      SquatJoint.rightAnkle: const SquatPoint(.6, .9),
      SquatJoint.leftFoot: const SquatPoint(.5, .9),
    };

    List<String> repFaults(double bottomKneeX) {
      final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);
      var us = 0;
      void frames(Map<SquatJoint, SquatPoint> value, int count) {
        for (var i = 0; i < count; i++) {
          us += 100000; // 100ms per frame, strictly increasing
          analyzer.analyze(value, timestampUs: us);
        }
      }

      frames(pose(.4, .7), 3); // standing
      frames(pose(bottomKneeX, .65), 6); // ~73 deg either way
      frames(pose(.4, .7), 5); // stand back up
      expect(analyzer.repetitions, 1);
      expect(analyzer.repRecords, hasLength(1));
      expect(analyzer.repRecords.single.minKneeAngle, lessThan(100));
      return analyzer.repRecords.single.faults;
    }

    test('knee caving toward the midline records valgus', () {
      expect(repFaults(.7), contains('kneeValgus'));
    });

    test('knee pushed out away from the midline is not valgus', () {
      expect(repFaults(.1), isNot(contains('kneeValgus')));
    });

    test('frontal view: live cue only when knees cave in', () {
      Map<SquatJoint, SquatPoint> frontal(double kneeOffset) => {
        SquatJoint.leftShoulder: const SquatPoint(.3, .1),
        SquatJoint.rightShoulder: const SquatPoint(.5, .1),
        SquatJoint.leftHip: const SquatPoint(.33, .45),
        SquatJoint.rightHip: const SquatPoint(.47, .45),
        // Positive offset moves both knees medially, negative laterally.
        SquatJoint.leftKnee: SquatPoint(.3 + kneeOffset, .68),
        SquatJoint.rightKnee: SquatPoint(.5 - kneeOffset, .68),
        SquatJoint.leftAnkle: const SquatPoint(.3, .9),
        SquatJoint.rightAnkle: const SquatPoint(.5, .9),
      };

      // Stand tall, then bend: valgus is judged only while bending, so a
      // wide stance standing up is never flagged.
      Map<SquatJoint, SquatPoint> standing() => {
        ...frontal(0),
        SquatJoint.leftKnee: const SquatPoint(.315, .68),
        SquatJoint.rightKnee: const SquatPoint(.485, .68),
      };
      SquatAnalysis bend(double kneeOffset) {
        final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);
        for (var i = 0; i < 3; i++) {
          expect(
            analyzer.analyze(standing()).cue,
            isNot('Giữ gối theo hướng mũi chân'),
          );
        }
        // Lower the hips so the knee angle reads as a bend.
        final bent = {
          ...frontal(kneeOffset),
          SquatJoint.leftHip: const SquatPoint(.33, .6),
          SquatJoint.rightHip: const SquatPoint(.47, .6),
          SquatJoint.leftShoulder: const SquatPoint(.3, .3),
          SquatJoint.rightShoulder: const SquatPoint(.5, .3),
          SquatJoint.leftKnee: SquatPoint(.3 + kneeOffset, .62),
          SquatJoint.rightKnee: SquatPoint(.5 - kneeOffset, .62),
        };
        // Held a few frames: the live cue waits for a sustained cave-in.
        late SquatAnalysis result;
        for (var i = 0; i < 5; i++) {
          result = analyzer.analyze(bent);
        }
        expect(result.phase, isNot(SquatPhase.standing));
        return result;
      }

      expect(bend(.08).cue, 'Giữ gối theo hướng mũi chân');
      final out = bend(-.08);
      expect(out.cue, isNot('Giữ gối theo hướng mũi chân'));
      expect(out.score, isNot(lessThan(80)));
    });

    test('side-on view with overlapping hips is never flagged', () {
      final result = SquatAnalyzer().analyze({
        ...pose(.7, .65),
        SquatJoint.rightHip: const SquatPoint(.41, .45),
      });
      expect(result.cue, isNot('Giữ gối theo hướng mũi chân'));
    });
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

  // Side view with both legs; [rightKneeX] lets one leg differ.
  Map<SquatJoint, SquatPoint> twoLegs(
    double kneeX,
    double kneeY, {
    double? rightKneeX,
    double? rightKneeY,
  }) => {
    SquatJoint.leftShoulder: const SquatPoint(.4, .1),
    SquatJoint.rightShoulder: const SquatPoint(.4, .1, confidence: .9),
    SquatJoint.leftHip: const SquatPoint(.4, .45),
    SquatJoint.rightHip: const SquatPoint(.4, .45, confidence: .9),
    SquatJoint.leftKnee: SquatPoint(kneeX, kneeY),
    SquatJoint.rightKnee: SquatPoint(
      rightKneeX ?? kneeX,
      rightKneeY ?? kneeY,
      confidence: .9,
    ),
    SquatJoint.leftAnkle: const SquatPoint(.4, .9),
    SquatJoint.rightAnkle: const SquatPoint(.4, .9, confidence: .9),
  };

  test('identical legs with smoothing lag record no asymmetry', () {
    // Default time-based smoothing: the smoothed angle lags the raw one
    // by >15 deg on a fast descent, which used to read as asymmetry.
    final analyzer = SquatAnalyzer();
    var us = 0;
    void frames(Map<SquatJoint, SquatPoint> value, int count) {
      for (var i = 0; i < count; i++) {
        us += 100000;
        analyzer.analyze(value, timestampUs: us);
      }
    }

    frames(twoLegs(.4, .7), 5);
    frames(twoLegs(.62, .7), 8);
    frames(twoLegs(.4, .7), 8);
    expect(analyzer.repetitions, 1);
    expect(analyzer.repRecords.single.faults, isNot(contains('asymmetry')));
  });

  test('one leg staying straight records asymmetry', () {
    final analyzer = SquatAnalyzer(transitionFrames: 2);
    final feed = _Feeder(analyzer);
    feed(twoLegs(.4, .7), 3);
    feed(twoLegs(.62, .7, rightKneeX: .45), 6);
    feed(twoLegs(.4, .7), 3);
    expect(analyzer.repRecords.single.faults, contains('asymmetry'));
  });

  test('counts a rep when the body shrinks at the bottom and drops out', () {
    // Distant user: shoulder-ankle span .45 standing, .30 at the bottom —
    // under the .35 needed to *acquire* tracking.
    final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);
    const standing = {
      SquatJoint.leftShoulder: SquatPoint(.4, .45),
      SquatJoint.leftHip: SquatPoint(.4, .6),
      SquatJoint.leftKnee: SquatPoint(.4, .75),
      SquatJoint.leftAnkle: SquatPoint(.4, .9),
    };
    const bottom = {
      SquatJoint.leftShoulder: SquatPoint(.35, .6),
      SquatJoint.leftHip: SquatPoint(.3, .75),
      SquatJoint.leftKnee: SquatPoint(.45, .78),
      SquatJoint.leftAnkle: SquatPoint(.4, .9),
    };
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(standing);
    }
    for (var i = 0; i < 3; i++) {
      expect(analyzer.analyze(bottom).bodyVisible, isTrue);
    }
    expect(analyzer.phase, SquatPhase.bottom);
    // A couple of lost frames keep the rep in progress.
    analyzer.analyze(const {});
    analyzer.analyze(const {});
    expect(analyzer.phase, SquatPhase.bottom);
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(standing);
    }
    expect(analyzer.repetitions, 1);
  });

  test('a long dropout resets the rep in progress', () {
    final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.4, .7));
    }
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.62, .7));
    }
    for (var i = 0; i < 20; i++) {
      analyzer.analyze(const {});
    }
    expect(analyzer.phase, SquatPhase.findingBody);
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.4, .7));
    }
    expect(analyzer.repetitions, 0);
  });

  test('a crouched start does not count a rep on the first stand', () {
    final analyzer = SquatAnalyzer(smoothingFactor: 1, transitionFrames: 2);
    for (var i = 0; i < 4; i++) {
      final result = analyzer.analyze(twoLegs(.62, .7)); // already at depth
      expect(result.phase, SquatPhase.findingBody);
      expect(result.cue, 'Đứng thẳng để bắt đầu');
    }
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.4, .7));
    }
    expect(analyzer.phase, SquatPhase.standing);
    expect(analyzer.repetitions, 0);
    // A real rep from standing still counts.
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.62, .7));
    }
    for (var i = 0; i < 3; i++) {
      analyzer.analyze(twoLegs(.4, .7));
    }
    expect(analyzer.repetitions, 1);
  });

  group('heels up', () {
    Map<SquatJoint, SquatPoint> pose(double kneeX, {double heelY = .9}) => {
      SquatJoint.leftShoulder: const SquatPoint(.4, .1),
      SquatJoint.leftHip: const SquatPoint(.4, .45),
      SquatJoint.leftKnee: SquatPoint(kneeX, .7),
      SquatJoint.leftAnkle: const SquatPoint(.4, .88),
      SquatJoint.leftHeel: SquatPoint(.38, heelY),
    };

    List<String> faults(int raisedFrames) {
      final analyzer = SquatAnalyzer(transitionFrames: 2);
      final feed = _Feeder(analyzer);
      feed(pose(.4), 3);
      feed(pose(.62), 3);
      feed(pose(.62, heelY: .87), raisedFrames);
      feed(pose(.62), 3);
      feed(pose(.4), 3);
      expect(analyzer.repRecords, hasLength(1));
      return analyzer.repRecords.single.faults;
    }

    test('a single jittery heel frame is ignored', () {
      expect(faults(1), isNot(contains('heelsUp')));
    });

    test('a sustained heel lift is flagged', () {
      expect(faults(4), contains('heelsUp'));
    });
  });

  test('live cue, label and review share one depth threshold', () {
    expect(squatCountDepthDegrees, greaterThanOrEqualTo(squatGoodDepthDegrees));
    final analyzer = SquatAnalyzer(transitionFrames: 2);
    final feed = _Feeder(analyzer);
    Map<SquatJoint, SquatPoint> pose(double kneeX) => {
      SquatJoint.leftShoulder: const SquatPoint(.4, .1),
      SquatJoint.leftHip: const SquatPoint(.4, .45),
      SquatJoint.leftKnee: SquatPoint(kneeX, .7),
      SquatJoint.leftAnkle: const SquatPoint(.4, .9),
    };
    feed(pose(.4), 3);
    final bottom = feed(pose(.58), 3); // ~102 deg: counts, not deep
    expect(bottom.phase, SquatPhase.bottom);
    expect(bottom.cue, 'Xuống thêm một chút');
    expect(bottom.phaseLabel, 'Chưa đủ sâu');
    feed(pose(.4), 3);
    expect(analyzer.repetitions, 1);
    expect(analyzer.repRecords.single.faults, contains('shallowDepth'));
  });
}

/// Feeds timestamped frames (rep records need timestamps). 1s apart, so
/// the time-based smoothing settles on each pose almost immediately.
class _Feeder {
  _Feeder(this.analyzer);

  final SquatAnalyzer analyzer;
  var _us = 0;

  SquatAnalysis call(Map<SquatJoint, SquatPoint> pose, int count) {
    late SquatAnalysis result;
    for (var i = 0; i < count; i++) {
      _us += 1000000;
      result = analyzer.analyze(pose, timestampUs: _us);
    }
    return result;
  }
}
