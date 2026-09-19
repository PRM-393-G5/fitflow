import 'package:material_ui/material_ui.dart';

import 'pose_render_model.dart';

class PoseOverlay extends CustomPainter {
  PoseOverlay({required this.model, required this.mirrored})
    : super(repaint: model);

  final PoseRenderModel model;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (model.points.isEmpty) return;
    final line = Paint()
      ..color = const Color(0xFF62E6A5)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final joint = Paint()..color = Colors.white;
    for (final bone in PoseRenderModel.bones) {
      final a = model.points[bone.$1];
      final b = model.points[bone.$2];
      if (a != null && b != null && a.confidence > .45 && b.confidence > .45) {
        canvas.drawLine(
          model.offset(a, size, mirrored),
          model.offset(b, size, mirrored),
          line,
        );
      }
    }
    for (final point in model.points.values) {
      if (point.confidence > .45) {
        canvas.drawCircle(model.offset(point, size, mirrored), 5, joint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlay oldDelegate) =>
      oldDelegate.model != model || oldDelegate.mirrored != mirrored;
}
