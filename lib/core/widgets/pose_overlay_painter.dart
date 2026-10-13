import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:smartfit/core/constants/app_colors.dart';

/// Draws pose landmarks and skeleton connections on the camera preview.
class PoseOverlayPainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;

  PoseOverlayPainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    this.isFrontCamera = true,
  });

  // Skeleton connections for body outline
  static const List<(PoseLandmarkType, PoseLandmarkType)> _connections = [
    // Torso
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    // Left arm
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    // Right arm
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    // Left leg
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    // Right leg
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final landmarkPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = AppColors.secondaryContainer.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (final pose in poses) {
      // Draw connections (skeleton lines)
      for (final connection in _connections) {
        final from = pose.landmarks[connection.$1];
        final to = pose.landmarks[connection.$2];
        if (from != null && to != null &&
            from.likelihood > 0.5 && to.likelihood > 0.5) {
          final fromPoint = _translatePoint(from.x, from.y, size);
          final toPoint = _translatePoint(to.x, to.y, size);
          canvas.drawLine(fromPoint, toPoint, linePaint);
        }
      }

      // Draw landmark points
      for (final landmark in pose.landmarks.values) {
        if (landmark.likelihood > 0.5) {
          final point = _translatePoint(landmark.x, landmark.y, size);
          // Glow effect
          canvas.drawCircle(point, 8, glowPaint);
          // Core dot
          canvas.drawCircle(point, 4, landmarkPaint);
        }
      }
    }
  }

  Offset _translatePoint(double x, double y, Size canvasSize) {
    // Scale from image coordinates to canvas coordinates
    final scaleX = canvasSize.width / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;

    double tx = x * scaleX;
    double ty = y * scaleY;

    // Mirror for front camera
    if (isFrontCamera) {
      tx = canvasSize.width - tx;
    }

    return Offset(tx, ty);
  }

  @override
  bool shouldRepaint(PoseOverlayPainter oldDelegate) {
    return oldDelegate.poses != poses;
  }
}
