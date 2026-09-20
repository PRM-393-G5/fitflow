import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/pose_frame.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';
import 'package:prm/features/squat_form/presentation/pose_render_model.dart';

void main() {
  group('PoseFrame normalization', () {
    const frame = PoseFrame(width: 480, height: 640);

    test('keeps angles isotropic on a non-square image', () {
      // A diagonal right angle in pixel space must stay 90 deg.
      final angle = angleDegrees(
        frame.point(100, 100),
        frame.point(200, 200),
        frame.point(300, 100),
      );
      expect(angle, closeTo(90, .001));

      // Per-axis normalization (x / width) would skew it.
      final stretched = angleDegrees(
        const SquatPoint(100 / 480, 100 / 640),
        const SquatPoint(200 / 480, 200 / 640),
        const SquatPoint(300 / 480, 100 / 640),
      );
      expect(stretched, isNot(closeTo(90, 1)));
    });

    test('y spans 0..1 and x spans 0..aspectRatio', () {
      expect(frame.aspectRatio, .75);
      final corner = frame.point(480, 640, confidence: .7);
      expect(corner.x, closeTo(.75, 1e-9));
      expect(corner.y, 1);
      expect(corner.confidence, .7);
    });
  });

  group('PoseRenderModel.project (BoxFit.cover)', () {
    // 3:4 preview on a 1:2 canvas: height fills (800), width 600 overflows
    // and is cropped 100px on each side.
    Offset project(double u, double v, {bool mirrored = false}) =>
        PoseRenderModel.project(
          SquatPoint(u * .75, v),
          canvas: const Size(400, 800),
          imageAspect: .75,
          previewAspect: .75,
          mirrored: mirrored,
        );

    test('image center maps to canvas center', () {
      expect(project(.5, .5), const Offset(200, 400));
    });

    test('accounts for the cropped overflow', () {
      expect(project(0, 0), const Offset(-100, 0));
      expect(project(1 / 6, 1).dx, closeTo(0, 1e-9));
      expect(project(5 / 6, 1).dx, closeTo(400, 1e-9));
    });

    test('mirrors around the preview center for the front camera', () {
      expect(project(0, .25, mirrored: true), const Offset(500, 200));
      expect(project(.25, .5, mirrored: true).dx, project(.75, .5).dx);
    });

    test('crops vertically when the preview is wider than the canvas', () {
      final offset = PoseRenderModel.project(
        const SquatPoint(.75, 0),
        canvas: const Size(400, 400),
        imageAspect: .75,
        previewAspect: .75,
        mirrored: false,
      );
      // Width fills: scale = 400 / .75 = 533.3, so 66.7px cropped top.
      expect(offset.dx, closeTo(400, 1e-9));
      expect(offset.dy, closeTo((400 - 400 / .75) / 2, 1e-9));
    });

    test('cover-fits a wider analysis image into a narrower preview', () {
      // 9:16 preview on a square canvas: width fills, preview rect is
      // 400 x 711.1. The 3:4 analysis frame shares its height, so it spans
      // 533.3px and the preview shows only its central 400px (u .125-.875).
      Offset at(double u, double v, {bool mirrored = false}) =>
          PoseRenderModel.project(
            SquatPoint(u * .75, v),
            canvas: const Size(400, 400),
            imageAspect: .75,
            previewAspect: 9 / 16,
            mirrored: mirrored,
          );
      final previewHeight = 400 / (9 / 16);
      expect(at(.5, .5).dx, closeTo(200, 1e-9));
      expect(at(.5, .5).dy, closeTo(200, 1e-9));
      expect(at(.125, 0).dx, closeTo(0, 1e-9));
      expect(at(.875, 1).dx, closeTo(400, 1e-9));
      expect(at(0, 0).dy, closeTo((400 - previewHeight) / 2, 1e-9));
      expect(at(0, 1).dy, closeTo((400 + previewHeight) / 2, 1e-9));
      // Isotropic: equal frame-space steps on both axes give equal pixels.
      final origin = at(.5, .5);
      final dx = at(.5 + .1 / .75, .5).dx - origin.dx;
      final dy = at(.5, .6).dy - origin.dy;
      expect(dx, closeTo(dy, 1e-9));
      expect(at(.125, .5, mirrored: true).dx, closeTo(400, 1e-9));
    });
  });
}
