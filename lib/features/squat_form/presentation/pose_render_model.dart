import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/squat_analyzer.dart';

class PoseRenderModel extends ChangeNotifier {
  static const bones = <(SquatJoint, SquatJoint)>[
    (SquatJoint.leftShoulder, SquatJoint.rightShoulder),
    (SquatJoint.leftShoulder, SquatJoint.leftElbow),
    (SquatJoint.leftElbow, SquatJoint.leftWrist),
    (SquatJoint.rightShoulder, SquatJoint.rightElbow),
    (SquatJoint.rightElbow, SquatJoint.rightWrist),
    (SquatJoint.leftShoulder, SquatJoint.leftHip),
    (SquatJoint.rightShoulder, SquatJoint.rightHip),
    (SquatJoint.leftHip, SquatJoint.rightHip),
    (SquatJoint.leftHip, SquatJoint.leftKnee),
    (SquatJoint.leftKnee, SquatJoint.leftAnkle),
    (SquatJoint.leftAnkle, SquatJoint.leftFoot),
    (SquatJoint.leftAnkle, SquatJoint.leftHeel),
    (SquatJoint.leftHeel, SquatJoint.leftFoot),
    (SquatJoint.rightHip, SquatJoint.rightKnee),
    (SquatJoint.rightKnee, SquatJoint.rightAnkle),
    (SquatJoint.rightAnkle, SquatJoint.rightFoot),
    (SquatJoint.rightAnkle, SquatJoint.rightHeel),
    (SquatJoint.rightHeel, SquatJoint.rightFoot),
  ];

  final Map<SquatJoint, SquatPoint> points = {};
  int _lastUs = 0;
  Set<SquatJoint> _highlight = const {};

  /// Joints behind the current form fault, painted in the warning color.
  Set<SquatJoint> get highlight => _highlight;
  set highlight(Set<SquatJoint> joints) {
    if (setEquals(joints, _highlight)) return;
    _highlight = joints;
    notifyListeners();
  }

  /// Width / height of the upright detector image the points came from.
  double imageAspect = 3 / 4;

  void update(
    Map<SquatJoint, SquatPoint> sample,
    int nowUs, {
    required double imageAspect,
  }) {
    this.imageAspect = imageAspect;
    final dt = _lastUs == 0 ? 1 / 15 : (nowUs - _lastUs) / 1000000;
    _lastUs = nowUs;
    final alpha = (1 - math.exp(-dt / .075)).clamp(.18, .8);
    for (final entry in sample.entries) {
      final old = points[entry.key];
      final value = entry.value;
      points[entry.key] = old == null
          ? value
          : SquatPoint(
              old.x + alpha * (value.x - old.x),
              old.y + alpha * (value.y - old.y),
              confidence: value.confidence,
            );
    }
    points.removeWhere((joint, _) => !sample.containsKey(joint));
    notifyListeners();
  }

  void clear() {
    if (points.isEmpty && _highlight.isEmpty) return;
    points.clear();
    _highlight = const {};
    notifyListeners();
  }

  Offset offset(
    SquatPoint point,
    Size size, {
    required bool mirrored,
    required double previewAspect,
  }) => project(
    point,
    canvas: size,
    imageAspect: imageAspect,
    previewAspect: previewAspect,
    mirrored: mirrored,
  );

  /// Maps a frame-space point (both axes in image-height units, see
  /// `PoseFrame`) onto a [canvas] that shows the camera preview with
  /// `BoxFit.cover`: the preview is scaled to fill the canvas and centered,
  /// so the overflowing axis is cropped equally on both sides.
  ///
  /// The analysis stream may use a different aspect than the preview (e.g.
  /// a 4:3 analysis frame behind a 16:9 preview). Both are center crops of
  /// the same sensor, and the analysis stream is assumed to keep the wider
  /// field of view, so the preview is a center crop of the analysis image:
  /// the analysis image is cover-fitted into the displayed preview rect.
  /// Stretching it to the preview rect instead would distort the skeleton.
  static Offset project(
    SquatPoint point, {
    required Size canvas,
    required double imageAspect,
    required double previewAspect,
    required bool mirrored,
  }) {
    // Displayed preview rect (cover-fit into the canvas, centered).
    final previewHeight = math.max(canvas.width / previewAspect, canvas.height);
    final previewWidth = previewAspect * previewHeight;
    // Analysis image cover-fitted into that rect, sharing its center.
    final height = math.max(previewWidth / imageAspect, previewHeight);
    final width = imageAspect * height;
    final u = point.x / imageAspect;
    return Offset(
      (canvas.width - width) / 2 + (mirrored ? 1 - u : u) * width,
      (canvas.height - height) / 2 + point.y * height,
    );
  }
}
