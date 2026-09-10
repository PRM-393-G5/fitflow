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
    (SquatJoint.rightHip, SquatJoint.rightKnee),
    (SquatJoint.rightKnee, SquatJoint.rightAnkle),
    (SquatJoint.rightAnkle, SquatJoint.rightFoot),
  ];

  final Map<SquatJoint, SquatPoint> points = {};
  int _lastUs = 0;

  void update(Map<SquatJoint, SquatPoint> sample, int nowUs) {
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
    if (points.isEmpty) return;
    points.clear();
    notifyListeners();
  }

  Offset offset(SquatPoint point, Size size, bool mirrored) => Offset(
    (mirrored ? 1 - point.x : point.x).clamp(0, 1) * size.width,
    point.y.clamp(0, 1) * size.height,
  );
}
