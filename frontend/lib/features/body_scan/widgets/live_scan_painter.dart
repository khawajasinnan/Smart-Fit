import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';

/// Shoulder line, skeleton and joints below this ML Kit likelihood are hidden.
const double kMinLikelihood = 0.5;

/// Signed shoulder tilt in degrees (> 0: the person's left shoulder is higher),
/// or null when either shoulder isn't confidently visible.
double? shoulderTiltDeg(Pose pose) {
  final l = pose.landmarks[PoseLandmarkType.leftShoulder];
  final r = pose.landmarks[PoseLandmarkType.rightShoulder];
  if (l == null || r == null || l.likelihood < kMinLikelihood || r.likelihood < kMinLikelihood) return null;
  final dx = (l.x - r.x).abs();
  if (dx == 0) return 0;
  return math.atan2(r.y - l.y, dx) * 180 / math.pi;
}

/// Maps points from the ML Kit image (upright, [imageSize]) onto the preview
/// canvas: the analysis frame is "cover"-fitted to the preview (they share the
/// sensor centre), and mirrored for the front camera like the preview is.
class FrameMapper {
  FrameMapper({required this.imageSize, required this.canvasSize, required this.mirror});

  final Size imageSize;
  final Size canvasSize;
  final bool mirror;

  late final double _scale = math.max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height);
  late final Offset _shift = Offset(
    (canvasSize.width - imageSize.width * _scale) / 2,
    (canvasSize.height - imageSize.height * _scale) / 2,
  );

  Offset map(double x, double y) {
    final p = Offset(x * _scale, y * _scale) + _shift;
    return mirror ? Offset(canvasSize.width - p.dx, p.dy) : p;
  }
}

/// Live overlay on the camera preview: the ML Kit pose skeleton (MediaPipe
/// BlazePose model), the shoulder line with its tilt, and the face contours.
class LiveScanPainter extends CustomPainter {
  LiveScanPainter({
    required this.poses,
    required this.faces,
    required this.imageSize,
    required this.mirror,
    required this.pulse,
  });

  final List<Pose> poses;
  final List<Face> faces;
  final Size imageSize;
  final bool mirror;

  /// 0..1, drives the joint glow.
  final double pulse;

  static const List<(PoseLandmarkType, PoseLandmarkType)> _bones = [
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  ];

  static const List<PoseLandmarkType> _joints = [
    PoseLandmarkType.nose,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;
    final m = FrameMapper(imageSize: imageSize, canvasSize: size, mirror: mirror);
    for (final face in faces) {
      _paintFace(canvas, m, face);
    }
    for (final pose in poses) {
      _paintPose(canvas, m, pose);
    }
  }

  void _paintPose(Canvas canvas, FrameMapper m, Pose pose) {
    Offset? at(PoseLandmarkType t) {
      final lm = pose.landmarks[t];
      if (lm == null || lm.likelihood < kMinLikelihood) return null;
      return m.map(lm.x, lm.y);
    }

    final bone = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary400.withValues(alpha: 0.95);
    for (final (a, b) in _bones) {
      final pa = at(a), pb = at(b);
      if (pa != null && pb != null) canvas.drawLine(pa, pb, bone);
    }

    // Shoulder line: the measurement the scan is about.
    final ls = at(PoseLandmarkType.leftShoulder), rs = at(PoseLandmarkType.rightShoulder);
    if (ls != null && rs != null) {
      canvas.drawLine(
        ls,
        rs,
        Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = kBrandLime,
      );
      final tilt = shoulderTiltDeg(pose);
      if (tilt != null) {
        _label(canvas, (ls + rs) / 2 - const Offset(0, 22), '${tilt.abs().toStringAsFixed(1)}°');
      }
    }

    final glow = Paint()..color = AppColors.accent600.withValues(alpha: 0.18 + 0.22 * pulse);
    final dot = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.accent600;
    for (final t in _joints) {
      final p = at(t);
      if (p == null) continue;
      canvas.drawCircle(p, 9 + 3 * pulse, glow);
      canvas.drawCircle(p, 4.5, dot);
      canvas.drawCircle(p, 4.5, ring);
    }
  }

  void _paintFace(Canvas canvas, FrameMapper m, Face face) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF7DF9E0).withValues(alpha: 0.9);
    for (final entry in face.contours.entries) {
      final points = entry.value?.points;
      if (points == null || points.length < 2) continue;
      final start = m.map(points.first.x.toDouble(), points.first.y.toDouble());
      final path = Path()..moveTo(start.dx, start.dy);
      for (final p in points.skip(1)) {
        final o = m.map(p.x.toDouble(), p.y.toDouble());
        path.lineTo(o.dx, o.dy);
      }
      final closed = entry.key == FaceContourType.face || entry.key == FaceContourType.leftEye ||
          entry.key == FaceContourType.rightEye;
      if (closed) path.close();
      canvas.drawPath(path, line);
    }

    // Corner brackets around the face box.
    final box = face.boundingBox;
    final a = m.map(box.left, box.top), b = m.map(box.right, box.bottom);
    final r = Rect.fromPoints(a, b);
    final c = math.min(r.width, r.height) * 0.18;
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = kBrandLime;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(c * dx, 0), bracket);
      canvas.drawLine(corner, corner + Offset(0, c * dy), bracket);
    }
  }

  void _label(Canvas canvas, Offset center, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: AppColors.ink900, fontSize: 12, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: center, width: tp.width + 14, height: tp.height + 6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)), Paint()..color = kBrandLime);
    tp.paint(canvas, rect.topLeft + const Offset(7, 3));
  }

  @override
  bool shouldRepaint(LiveScanPainter old) =>
      old.poses != poses || old.faces != faces || old.pulse != pulse || old.imageSize != imageSize;
}
