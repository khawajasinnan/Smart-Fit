import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';

/// Colours of the two pose models and the face mesh in the scan view (and its legend).
const Color kMediaPipeColor = AppColors.primary400;
const Color kHrnetColor = AppColors.accent600;
const Color kFaceMeshColor = Color(0xFF7DF9E0);

/// Draws the backend scan on the photo: the MediaPipe skeleton, the HRNet
/// skeleton, the face mesh + contours and the measurement lines. All points
/// are normalised, so the canvas only needs the photo's aspect ratio.
/// [progress] (0..1) reveals the layers in turn.
class ScanResultPainter extends CustomPainter {
  ScanResultPainter({required this.result, required this.progress});

  final CvAnalysisResult result;
  final double progress;

  static const List<(String, String)> _mediaPipeBones = [
    ('left_shoulder', 'right_shoulder'),
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('left_shoulder', 'left_hip'),
    ('right_shoulder', 'right_hip'),
    ('left_hip', 'right_hip'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
  ];

  // HRNet's COCO-17 limbs.
  static const List<(String, String)> _hrnetBones = [
    ('left_shoulder', 'right_shoulder'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('right_shoulder', 'right_hip'),
    ('left_shoulder', 'left_hip'),
    ('left_hip', 'right_hip'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('nose', 'right_eye'),
    ('right_eye', 'right_ear'),
    ('nose', 'left_eye'),
    ('left_eye', 'left_ear'),
  ];

  static const _measureLines = {'face_length', 'forehead_width', 'cheekbone_width', 'jaw_width'};

  /// Layer reveal: 0..1 within its slot of [progress].
  double _phase(int i, int of) => ((progress * of) - i).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(double x, double y) => Offset(x * size.width, y * size.height);

    // 1. face mesh dots, then contours and measurement lines
    final face = result.face;
    final meshT = _phase(0, 4);
    if (face != null && meshT > 0) {
      final dot = Paint()..color = kFaceMeshColor.withValues(alpha: 0.55 * meshT);
      final shown = (face.points.length * meshT).round();
      for (final p in face.points.take(shown)) {
        canvas.drawCircle(at(p.dx, p.dy), 0.9, dot);
      }
      final contourT = _phase(1, 4);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = kFaceMeshColor.withValues(alpha: contourT);
      final measure = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = kBrandLime.withValues(alpha: contourT);
      for (final entry in face.contours.entries) {
        final pts = entry.value;
        if (pts.length < 2 || contourT == 0) continue;
        if (_measureLines.contains(entry.key)) {
          canvas.drawLine(at(pts.first.dx, pts.first.dy), at(pts.last.dx, pts.last.dy), measure);
          continue;
        }
        final start = at(pts.first.dx, pts.first.dy);
        final path = Path()..moveTo(start.dx, start.dy);
        for (final p in pts.skip(1)) {
          final o = at(p.dx, p.dy);
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, line);
      }
    }

    // 2. MediaPipe skeleton
    final mpT = _phase(2, 4);
    if (mpT > 0) {
      final byName = {for (final lm in result.poseLandmarks) if (lm.visibility >= 0.5) lm.name: lm};
      _skeleton(
        canvas,
        _mediaPipeBones,
        (name) => byName[name] == null ? null : at(byName[name]!.x, byName[name]!.y),
        kMediaPipeColor.withValues(alpha: mpT),
        width: 3.4,
      );
    }

    // 3. HRNet skeleton (thinner, on top, so both stay visible)
    final opT = _phase(3, 4);
    if (opT > 0) {
      final byName = {for (final k in result.hrnetKeypoints) k.name: k};
      _skeleton(
        canvas,
        _hrnetBones,
        (name) => byName[name] == null ? null : at(byName[name]!.x, byName[name]!.y),
        kHrnetColor.withValues(alpha: opT),
        width: 2,
      );
    }
  }

  void _skeleton(
    Canvas canvas,
    List<(String, String)> bones,
    Offset? Function(String) point,
    Color color, {
    required double width,
  }) {
    final bone = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    final joints = <Offset>{};
    for (final (a, b) in bones) {
      final pa = point(a), pb = point(b);
      if (pa == null || pb == null) continue;
      canvas.drawLine(pa, pb, bone);
      joints
        ..add(pa)
        ..add(pb);
    }
    final fill = Paint()..color = Colors.white.withValues(alpha: color.a);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    for (final j in joints) {
      canvas.drawCircle(j, width + 1.2, fill);
      canvas.drawCircle(j, width + 1.2, ring);
    }
  }

  @override
  bool shouldRepaint(ScanResultPainter old) => old.result != result || old.progress != progress;
}
