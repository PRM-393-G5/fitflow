import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/plank_analyzer.dart';
import 'package:prm/features/squat_form/domain/pushup_analyzer.dart';
import 'package:prm/features/squat_form/domain/shoulder_press_analyzer.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

import 'support/form_simulator.dart';

/// End-to-end checks of the form-check analyzers on simulated sets: a 3D
/// skeleton projected through a phone camera with detector noise, replayed
/// over many random seeds. Good form must count exactly and score clean;
/// each fault must be caught.
const _seeds = 20;

List<SimResult> _runs(
  Movement movement,
  RepAnalyzer Function() analyzer, {
  SimCamera camera = const SimCamera(),
  SimNoise noise = const SimNoise(),
}) => [
  for (var seed = 1; seed <= _seeds; seed++)
    replay(
      analyzer(),
      simulate(movement, camera: camera, noise: noise, seed: seed),
    ),
];

/// Share of all reps, across runs, carrying [fault].
double _faultRate(List<SimResult> runs, String fault) {
  final reps = [for (final run in runs) ...run.records];
  return reps.where((rep) => rep.faults.contains(fault)).length / reps.length;
}

double _cleanRate(List<SimResult> runs) => 1 - _anyFaultRate(runs);

double _anyFaultRate(List<SimResult> runs) {
  final reps = [for (final run in runs) ...run.records];
  return reps.where((rep) => rep.faults.isNotEmpty).length / reps.length;
}

/// Camera on the floor, far enough for a prone body to fit a portrait frame.
/// The phone on the floor aims low, at the prone body.
const _prone = SimCamera(
  scale: .33,
  floorY: .72,
  centerU: -.65,
  aimHeightM: .25,
);

SimCamera _proneAt(double azimuth, {double scale = .33}) => SimCamera(
  azimuthDeg: azimuth,
  scale: scale,
  floorY: .72,
  centerU: -.65,
  aimHeightM: .25,
);

void main() {
  group('squat, good form', () {
    test('side-on: every rep counts, is clean and scores 100 throughout', () {
      for (final run in _runs(SquatMovement(), SquatAnalyzer.new)) {
        expect(run.count, 5);
        expect(run.faults, isEmpty);
        expect(run.minScore, 100);
      }
    });

    // Further off side-on the knee bend foreshortens fast: a 75° squat
    // reads ~98° at 60°, so only near side-on is promised.
    for (final azimuth in [75.0, 80.0]) {
      test('angled $azimuth°: counts every rep with no false faults', () {
        final runs = _runs(
          SquatMovement(),
          SquatAnalyzer.new,
          camera: SimCamera(azimuthDeg: azimuth),
        );
        for (final run in runs) {
          expect(run.count, 5);
          expect(run.faults, isEmpty);
          expect(run.perfectShare, greaterThan(.98));
        }
      });
    }

    test('depth anywhere from 65° to 100° is clean', () {
      for (final knee in [65.0, 85.0, 95.0]) {
        final runs = _runs(SquatMovement(kneeMinDeg: knee), SquatAnalyzer.new);
        expect(runs.every((run) => run.count == 5), isTrue, reason: '$knee°');
        expect(_cleanRate(runs), 1, reason: '$knee°');
      }
    });

    test('a wide stance is not knee valgus', () {
      final runs = _runs(SquatMovement(stanceHalfM: .26), SquatAnalyzer.new);
      expect(_cleanRate(runs), 1);
    });

    test('survives heavy jitter, low frame rate and a far camera', () {
      for (final (camera, noise) in [
        (const SimCamera(), const SimNoise(sigma: .008)),
        (const SimCamera(), const SimNoise(fps: 10)),
        (const SimCamera(scale: .3), const SimNoise()),
      ]) {
        final runs = _runs(
          SquatMovement(),
          SquatAnalyzer.new,
          camera: camera,
          noise: noise,
        );
        expect(runs.every((run) => run.count == 5), isTrue);
        expect(_cleanRate(runs), greaterThan(.95));
      }
    });
  });

  group('squat, faults', () {
    test('a half squat never counts', () {
      final runs = _runs(SquatMovement(kneeMinDeg: 115), SquatAnalyzer.new);
      expect(runs.every((run) => run.count == 0), isTrue);
    });

    test('just short of depth counts but is flagged shallow', () {
      // Held at the bottom, so smoothing settles inside the 100–105° band.
      final runs = _runs(
        SquatMovement(kneeMinDeg: 103, pauseS: .6),
        SquatAnalyzer.new,
      );
      expect(runs.every((run) => run.count == 5), isTrue);
      expect(_faultRate(runs, 'shallowDepth'), greaterThan(.4));
    });

    test('leaning far forward is flagged, cued and scored down', () {
      final runs = _runs(SquatMovement(leanBottomDeg: 60), SquatAnalyzer.new);
      expect(_faultRate(runs, 'forwardLean'), greaterThan(.9));
      expect(
        runs.every((run) => run.cues.contains('Giữ thân ổn định')),
        isTrue,
      );
      expect(runs.every((run) => run.minScore <= 80), isTrue);
    });

    test('heels lifting is flagged', () {
      final runs = _runs(SquatMovement(heelLiftM: .05), SquatAnalyzer.new);
      expect(_faultRate(runs, 'heelsUp'), greaterThan(.5));
    });

    test('dropping fast is flagged; a controlled descent is not', () {
      final fast = _runs(SquatMovement(descentS: .5), SquatAnalyzer.new);
      expect(_faultRate(fast, 'fastEccentric'), greaterThan(.8));
      final controlled = _runs(SquatMovement(descentS: 1.2), SquatAnalyzer.new);
      expect(_faultRate(controlled, 'fastEccentric'), 0);
    });

    test('one leg bending less is flagged side-on', () {
      final runs = _runs(SquatMovement(asymmetryDeg: 25), SquatAnalyzer.new);
      expect(_faultRate(runs, 'asymmetry'), greaterThan(.6));
    });

    for (final azimuth in [30.0, 45.0, 60.0]) {
      test('knees caving in are caught at $azimuth°', () {
        final camera = SimCamera(azimuthDeg: azimuth);
        final caving = _runs(
          SquatMovement(valgusM: .25),
          SquatAnalyzer.new,
          camera: camera,
        );
        expect(_faultRate(caving, 'kneeValgus'), greaterThan(.9));
        expect(
          caving.every(
            (run) => run.cues.contains('Giữ gối theo hướng mũi chân'),
          ),
          isTrue,
        );
        // Knees travelling forward over the toes must not read as caving.
        final good = _runs(SquatMovement(), SquatAnalyzer.new, camera: camera);
        expect(_faultRate(good, 'kneeValgus'), 0);
      });
    }
  });

  group('push-up', () {
    test('good form counts every rep and scores 100', () {
      for (final run in _runs(
        PushupMovement(),
        PushupAnalyzer.new,
        camera: _prone,
      )) {
        expect(run.count, 5);
        expect(run.perfectShare, greaterThan(.98));
      }
    });

    test('counts with flared elbows, from an angle, far away, and with '
        'dropped frames', () {
      for (final (movement, camera, noise) in [
        (PushupMovement(flareDeg: 45), _prone, const SimNoise()),
        (PushupMovement(flareDeg: 60), _prone, const SimNoise()),
        (PushupMovement(), _proneAt(60), const SimNoise()),
        (PushupMovement(), _proneAt(90, scale: .25), const SimNoise()),
        (PushupMovement(), _prone, const SimNoise(dropoutRate: .05)),
        (PushupMovement(), _prone, const SimNoise(sigma: .008)),
      ]) {
        final runs = _runs(
          movement,
          PushupAnalyzer.new,
          camera: camera,
          noise: noise,
        );
        expect(
          runs.where((run) => run.count == 5).length,
          greaterThanOrEqualTo(_seeds - 1),
        );
      }
    });

    test('a 90° rep counts', () {
      final runs = _runs(
        PushupMovement(elbowMinDeg: 90),
        PushupAnalyzer.new,
        camera: _prone,
      );
      final reps = runs.fold(0, (sum, run) => sum + run.count);
      expect(reps / (runs.length * 5), greaterThan(.9));
    });

    test('a shallow rep never counts', () {
      final runs = _runs(
        PushupMovement(elbowMinDeg: 110),
        PushupAnalyzer.new,
        camera: _prone,
      );
      expect(runs.every((run) => run.count == 0), isTrue);
    });

    test('sagging hips are cued and scored down but still counted', () {
      final runs = _runs(
        PushupMovement(sagM: .12),
        PushupAnalyzer.new,
        camera: _prone,
      );
      for (final run in runs) {
        expect(run.count, 5);
        expect(run.cues, contains('Đừng để hông xệ'));
        expect(run.perfectShare, lessThan(.1));
      }
    });
  });

  group('plank', () {
    test('a good 20 s hold is credited in full', () {
      for (final run in _runs(
        PlankMovement(),
        PlankAnalyzer.new,
        camera: _prone,
      )) {
        expect(run.count, inInclusiveRange(18, 20));
        expect(run.minScore, greaterThanOrEqualTo(70));
        expect(run.cues, contains('Tốt lắm, giữ nguyên'));
      }
    });

    test('sagging or piking hips earn no hold time', () {
      for (final (sag, cue) in [
        (.12, 'Đừng để hông xệ'),
        (-.12, 'Hạ hông thấp hơn'),
      ]) {
        final runs = _runs(
          PlankMovement(sagM: sag),
          PlankAnalyzer.new,
          camera: _prone,
        );
        for (final run in runs) {
          expect(run.count, 0);
          expect(run.cues, contains(cue));
        }
      }
    });
  });

  group('live feedback: what the user sees and hears', () {
    List<List<SimFrame>> sets(
      Movement movement, {
      SimCamera camera = const SimCamera(),
    }) => [
      for (var seed = 1; seed <= _seeds; seed++)
        simulate(movement, camera: camera, seed: seed),
    ];

    Set<String> warnings(List<(String, CueTone)> shown) => {
      for (final (cue, tone) in shown)
        if (tone == CueTone.warn) cue,
    };

    test('good squats: only the count is spoken, no warning ever shows', () {
      for (final azimuth in [75.0, 90.0]) {
        for (final frames in sets(
          SquatMovement(),
          camera: SimCamera(azimuthDeg: azimuth),
        )) {
          expect(spoken(SquatAnalyzer(), frames), ['1', '2', '3', '4', '5']);
          final shown = shownCues(SquatAnalyzer(), frames);
          expect(warnings(shown), isEmpty);
          expect(shown.map((c) => c.$1), contains('Rep chuẩn!'));
          // Dropped detector frames mid-set never flash "step back".
          final tracking = shown
              .map((c) => c.$1)
              .skipWhile((cue) => cue != 'Sẵn sàng, bắt đầu squat');
          expect(tracking, isNot(contains('Lùi ra để thấy toàn thân')));
        }
      }
    });

    test('good push-ups and planks raise no warning', () {
      for (final frames in sets(PushupMovement(), camera: _prone)) {
        expect(spoken(PushupAnalyzer(), frames), ['1', '2', '3', '4', '5']);
        expect(warnings(shownCues(PushupAnalyzer(), frames)), isEmpty);
      }
      for (final frames in sets(PlankMovement(holdS: 25), camera: _prone)) {
        expect(spoken(PlankAnalyzer(), frames, timed: true), [
          'Bắt đầu tính giờ',
          '10 giây',
          '20 giây',
        ]);
        expect(
          warnings(shownCues(PlankAnalyzer(), frames, timed: true)),
          isEmpty,
        );
      }
    });

    for (final (name, movement, warning, tip) in [
      (
        'heels lifting',
        SquatMovement(heelLiftM: .05),
        'Giữ gót chân chạm sàn',
        'giữ gót chạm sàn',
      ),
      (
        'uneven legs',
        SquatMovement(asymmetryDeg: 25),
        'Dồn đều lực hai chân',
        'dồn đều lực hai chân',
      ),
      (
        'dropping fast',
        SquatMovement(descentS: .5),
        'Hạ người chậm hơn',
        'hạ người chậm hơn',
      ),
      (
        'leaning forward',
        SquatMovement(leanBottomDeg: 60),
        'Giữ thân ổn định',
        'giữ ngực thẳng',
      ),
    ]) {
      test('$name: warned live and told how to fix the next rep', () {
        for (final frames in sets(movement)) {
          expect(
            warnings(shownCues(SquatAnalyzer(), frames)),
            contains(warning),
          );
          final said = spoken(SquatAnalyzer(), frames);
          expect(said, contains(warning));
          expect(said.where((s) => s.endsWith('. $tip')), isNotEmpty);
        }
      });
    }

    test('a shallow squat is told to go deeper on the next rep', () {
      for (final frames in sets(SquatMovement(kneeMinDeg: 103, pauseS: .6))) {
        final cues = shownCues(SquatAnalyzer(), frames).map((c) => c.$1);
        expect(cues, contains('Rep sau: xuống sâu hơn'));
      }
    });

    test('facing the camera for squats is told to turn side-on', () {
      for (final azimuth in [0.0, 45.0]) {
        for (final frames in sets(
          SquatMovement(),
          camera: SimCamera(azimuthDeg: azimuth),
        )) {
          expect(
            spoken(SquatAnalyzer(), frames),
            contains('Xoay nghiêng người về phía camera'),
          );
        }
      }
    });

    test('lying head-on to the camera is told to turn sideways', () {
      const headOn = SimCamera(
        azimuthDeg: 0,
        scale: .33,
        floorY: .72,
        aimHeightM: .25,
      );
      for (final frames in sets(PushupMovement(), camera: headOn)) {
        expect(
          spoken(PushupAnalyzer(), frames),
          contains('Xoay người nằm ngang so với camera'),
        );
      }
      for (final frames in sets(PlankMovement(), camera: headOn)) {
        expect(
          spoken(PlankAnalyzer(), frames, timed: true),
          contains('Xoay người nằm ngang so với camera'),
        );
      }
    });

    test('sagging hips are said aloud and become the next-rep fix', () {
      for (final frames in sets(PushupMovement(sagM: .12), camera: _prone)) {
        final said = spoken(PushupAnalyzer(), frames);
        expect(said, contains('Đừng để hông xệ'));
        expect(said, contains('2. siết bụng, giữ hông thẳng'));
      }
    });

    test('faulty joints are highlighted, good form highlights nothing', () {
      final heels = replay(
        SquatAnalyzer(),
        simulate(SquatMovement(heelLiftM: .05)),
      );
      expect(
        heels.outputs.any((o) => o.faultJoints.contains(SquatJoint.leftHeel)),
        isTrue,
      );
      final sag = replay(
        PlankAnalyzer(),
        simulate(PlankMovement(sagM: .12), camera: _prone),
      );
      expect(
        sag.outputs.any((o) => o.faultJoints.contains(SquatJoint.leftHip)),
        isTrue,
      );
      final good = replay(SquatAnalyzer(), simulate(SquatMovement()));
      expect(good.outputs.every((o) => o.faultJoints.isEmpty), isTrue);
    });
  });

  group('post-set review data', () {
    test('push-up reps are recorded, sagging ones flagged', () {
      final good = replay(
        PushupAnalyzer(),
        simulate(PushupMovement(), camera: _prone),
      );
      expect(good.records, hasLength(5));
      expect(good.faults, isEmpty);
      expect(good.records.every((rep) => rep.descentMs > 0), isTrue);
      // The elbow angle misleads with flared elbows: never sent as depth.
      expect(
        good.records.every(
          (rep) => !rep.toJson().containsKey('minKneeAngleDeg'),
        ),
        isTrue,
      );
      final sag = _runs(
        PushupMovement(sagM: .12),
        PushupAnalyzer.new,
        camera: _prone,
      );
      expect(_faultRate(sag, 'hipSag'), greaterThan(.8));
    });

    test('a plank hold is broken down into good form and sagging', () {
      final good = PlankAnalyzer();
      replay(good, simulate(PlankMovement(), camera: _prone));
      final summary = good.summary;
      expect(summary.goodMs, greaterThan(summary.trackedMs * .95));
      expect(summary.sagMs, 0);

      final sagging = PlankAnalyzer();
      replay(sagging, simulate(PlankMovement(sagM: .12), camera: _prone));
      expect(sagging.summary.goodMs, 0);
      expect(sagging.summary.sagMs, greaterThan(15000));
    });
  });

  group('shoulder press (facing the camera, upper body only)', () {
    /// Framed from the waist up, 2 m away.
    SimCamera upperBody({double pitch = 0, double azimuth = 0}) => SimCamera(
      azimuthDeg: azimuth,
      pitchDeg: pitch,
      scale: .6,
      floorY: 1.35,
      distanceM: 2,
    );

    List<List<SimFrame>> sets(
      Movement movement, {
      SimCamera? camera,
      SimNoise noise = const SimNoise(),
    }) => [
      for (var seed = 1; seed <= _seeds; seed++)
        simulate(
          movement,
          camera: camera ?? upperBody(),
          noise: noise,
          seed: seed,
        ),
    ];

    Set<String> warnings(List<SimFrame> frames) => {
      for (final (cue, tone) in shownCues(ShoulderPressAnalyzer(), frames))
        if (tone == CueTone.warn) cue,
    };

    test('good presses: counted, clean, 100, only the count spoken', () {
      for (final camera in [
        upperBody(),
        // A phone on a shelf or projector, tilted down.
        upperBody(pitch: 30),
        upperBody(pitch: 60),
        // Not squarely facing the camera.
        upperBody(azimuth: 35),
        // Whole body in frame, further away.
        const SimCamera(azimuthDeg: 0, scale: .4, floorY: .95),
      ]) {
        for (final frames in sets(ShoulderPressMovement(), camera: camera)) {
          final run = replay(ShoulderPressAnalyzer(), frames);
          expect(run.count, 5);
          expect(run.faults, isEmpty);
          expect(run.minScore, 100);
          expect(spoken(ShoulderPressAnalyzer(), frames), [
            '1',
            '2',
            '3',
            '4',
            '5',
          ]);
          expect(warnings(frames), isEmpty);
        }
      }
    });

    test('survives jitter, low frame rate and quick reps', () {
      for (final (movement, noise) in [
        (ShoulderPressMovement(), const SimNoise(sigma: .008)),
        (ShoulderPressMovement(), const SimNoise(fps: 10)),
        (
          ShoulderPressMovement(pressS: .4, lowerS: .5, pauseS: .1, restS: .2),
          const SimNoise(),
        ),
      ]) {
        for (final frames in sets(movement, noise: noise)) {
          final run = replay(ShoulderPressAnalyzer(), frames);
          expect(run.count, 5);
          expect(run.faults, isEmpty);
        }
      }
    });

    test('arms left bent overhead: counted, flagged, told to lock out', () {
      for (final frames in sets(ShoulderPressMovement(elbowTopDeg: 140))) {
        final run = replay(ShoulderPressAnalyzer(), frames);
        expect(run.count, 5);
        expect(
          run.records.every((r) => r.faults.contains('noLockout')),
          isTrue,
        );
        expect(
          spoken(ShoulderPressAnalyzer(), frames),
          contains('2. đẩy thẳng tay lên hết'),
        );
      }
    });

    test('one arm lagging: warned live, highlighted, told to press evenly', () {
      for (final frames in sets(ShoulderPressMovement(rightLag: .6))) {
        final run = replay(ShoulderPressAnalyzer(), frames);
        expect(run.count, 5);
        expect(
          run.records.every((r) => r.faults.first == 'unevenArms'),
          isTrue,
        );
        expect(warnings(frames), contains('Đẩy đều hai tay'));
        expect(
          run.outputs.any((o) => o.faultJoints.contains(SquatJoint.rightWrist)),
          isTrue,
        );
        expect(
          spoken(ShoulderPressAnalyzer(), frames),
          contains('2. đẩy đều hai tay'),
        );
      }
    });

    test('pressing again before reaching the shoulders is not a rep', () {
      for (final frames in sets(ShoulderPressMovement(lowestP: .4))) {
        final run = replay(ShoulderPressAnalyzer(), frames);
        // Only the final full lowering completes one, partial-range, rep.
        expect(run.count, 1);
        expect(run.records.single.faults, contains('partialRange'));
        expect(warnings(frames), contains('Hạ khuỷu xuống ngang vai'));
      }
    });

    test('standing side-on is told to face the camera, never counts', () {
      for (final frames in sets(
        ShoulderPressMovement(),
        camera: upperBody(azimuth: 90),
      )) {
        expect(replay(ShoulderPressAnalyzer(), frames).count, 0);
        expect(
          spoken(ShoulderPressAnalyzer(), frames),
          contains('Quay mặt về phía camera'),
        );
      }
    });

    test('rep tempo is recorded for the review', () {
      final run = replay(
        ShoulderPressAnalyzer(),
        simulate(ShoulderPressMovement(), camera: upperBody()),
      );
      expect(run.records, hasLength(5));
      expect(
        run.records.every((r) => r.descentMs > 0 && r.ascentMs > 0),
        isTrue,
      );
      expect(run.records.every((r) => r.minKneeAngle == null), isTrue);
    });
  });
}
