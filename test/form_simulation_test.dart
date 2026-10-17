import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/plank_analyzer.dart';
import 'package:prm/features/squat_form/domain/pushup_analyzer.dart';
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
const _prone = SimCamera(scale: .33, floorY: .72, centerU: -.65);

SimCamera _proneAt(double azimuth, {double scale = .33}) =>
    SimCamera(azimuthDeg: azimuth, scale: scale, floorY: .72, centerU: -.65);

void main() {
  group('squat, good form', () {
    test('side-on: every rep counts, is clean and scores 100 throughout', () {
      for (final run in _runs(SquatMovement(), SquatAnalyzer.new)) {
        expect(run.count, 5);
        expect(run.faults, isEmpty);
        expect(run.minScore, 100);
      }
    });

    for (final azimuth in [60.0, 75.0]) {
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
      for (final knee in [65.0, 85.0, 100.0]) {
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
      final runs = _runs(SquatMovement(kneeMinDeg: 103), SquatAnalyzer.new);
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
}
