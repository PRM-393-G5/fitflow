import 'squat_analyzer.dart';

/// Upright detector image the landmarks were measured in. Converts pixel
/// coordinates into the analyzers' isotropic frame space: both axes are
/// divided by the image *height*, so y spans 0..1 and x spans
/// 0..[aspectRatio]. Dividing x by width instead would stretch one axis and
/// skew every joint angle and distance threshold.
class PoseFrame {
  const PoseFrame({required this.width, required this.height});

  final double width;
  final double height;

  /// Width / height of the upright image — x's upper bound in frame space.
  double get aspectRatio => width / height;

  SquatPoint point(double x, double y, {double confidence = 1}) =>
      SquatPoint(x / height, y / height, confidence: confidence);
}
