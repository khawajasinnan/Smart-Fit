import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mlkit;
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/body_scan/widgets/body_scan_card.dart';
import 'package:smartfit/features/body_scan/widgets/live_scan_painter.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';

/// A detailed /analyze/app response, trimmed (shape as the CV service sends it).
const _detailedJson = <String, dynamic>{
  'success': true,
  'error': null,
  'body_shape': 'Rectangle',
  'estimated_size': 'M',
  'skin_tone': {'dominant_hex': '#C49A6C', 'fitzpatrick_type': 'Type III', 'tone_label': 'Medium'},
  'image_width': 768,
  'image_height': 1024,
  'pose_landmarks': [
    {'name': 'left_shoulder', 'x': 0.65, 'y': 0.36, 'z': 0, 'visibility': 0.99},
  ],
  'hrnet_keypoints': [
    {'name': 'right_shoulder', 'x': 0.326, 'y': 0.2955, 'confidence': 0.59},
  ],
  'face': {
    'face_shape': 'Round',
    'note': 'Estimated from face-mesh proportions.',
    'length_to_cheek': 1.114,
    'forehead_to_cheek': 0.841,
    'jaw_to_cheek': 0.806,
    'points': [
      [0.5, 0.2],
      [0.51, 0.21],
    ],
    'contours': {
      'cheekbone_width': [
        [0.4, 0.3],
        [0.6, 0.3],
      ],
    },
  },
  'shoulders': {
    'tilt_deg': -12.8,
    'level': 'Right shoulder higher',
    'build': 'Balanced with hips',
    'width_cm': null,
    'sources': ['MediaPipe', 'HRNet'],
  },
  'model_agreement': {'compared_points': 13, 'mean_offset_pct': 9.1, 'agreement': 'Strong'},
  'models_used': ['MediaPipe Pose', 'MediaPipe Face Detector', 'MediaPipe Face Mesh', 'HRNet-W32 (COCO-17)'],
  'processing_time_ms': 2342,
};

void main() {
  group('CvAnalysisResult detailed fields', () {
    test('parse from the backend response', () {
      final r = CvAnalysisResult.fromJson(_detailedJson);
      expect(r.face!.faceShape, 'Round');
      expect(r.face!.points, hasLength(2));
      expect(r.face!.contours['cheekbone_width'], [const Offset(0.4, 0.3), const Offset(0.6, 0.3)]);
      expect(r.shoulders!.tiltDeg, -12.8);
      expect(r.shoulders!.sources, ['MediaPipe', 'HRNet']);
      expect(r.modelAgreement!.agreement, 'Strong');
      expect(r.hrnetKeypoints.single.name, 'right_shoulder');
      expect(r.modelsUsed, hasLength(4));
      expect(r.processingTimeMs, 2342);
    });

    test('a plain (non-detailed) response leaves them empty', () {
      final r = CvAnalysisResult.fromJson(const {'success': true, 'body_shape': 'Pear'});
      expect(r.face, isNull);
      expect(r.shoulders, isNull);
      expect(r.modelAgreement, isNull);
      expect(r.hrnetKeypoints, isEmpty);
      expect(r.modelsUsed, isEmpty);
    });
  });

  group('ScanSummary', () {
    final summary = ScanSummary.fromResult(CvAnalysisResult.fromJson(_detailedJson));

    test('reads the headline results', () {
      expect(summary.lines, [
        'Body shape: Rectangle',
        'Shoulders: Right shoulder higher (13°), balanced with hips',
        'Face shape: Round',
        'Skin tone: Medium',
        'Estimated size: M',
      ]);
      expect(summary.agreement, startsWith('Strong'));
    });

    test('survives the chat-message metadata round trip', () {
      final back = ScanSummary.fromMap(summary.toMap());
      expect(back.lines, summary.lines);
      expect(back.skinHex, '#C49A6C');
      expect(summary.toMap()['type'], ScanSummary.metadataType);
    });

    test('briefs the stylist with the models and findings', () {
      expect(summary.stylistContext, contains('HRNet-W32 (COCO-17)'));
      expect(summary.stylistContext, contains('- Face shape: Round'));
    });
  });

  group('live overlay geometry', () {
    test('same aspect ratio: points scale straight onto the preview', () {
      final m = FrameMapper(imageSize: const Size(720, 1280), canvasSize: const Size(360, 640), mirror: false);
      expect(m.map(360, 640), const Offset(180, 320));
      expect(m.map(0, 0), Offset.zero);
    });

    test('front camera mirrors horizontally', () {
      final m = FrameMapper(imageSize: const Size(720, 1280), canvasSize: const Size(360, 640), mirror: true);
      expect(m.map(0, 0), const Offset(360, 0));
    });

    test('a 4:3 frame on a 16:9 preview is cover-fitted around the centre', () {
      final m = FrameMapper(imageSize: const Size(480, 640), canvasSize: const Size(720, 1280), mirror: false);
      // scale = max(720/480, 1280/640) = 2; width 960 overflows by 240 -> shift -120
      expect(m.map(240, 320), const Offset(360, 640));
      expect(m.map(0, 0), const Offset(-120, 0));
    });

    mlkit.Pose pose({required double leftY, required double rightY, double likelihood = 0.9}) => mlkit.Pose(
          landmarks: {
            mlkit.PoseLandmarkType.leftShoulder: mlkit.PoseLandmark(
                type: mlkit.PoseLandmarkType.leftShoulder, x: 300, y: leftY, z: 0, likelihood: likelihood),
            mlkit.PoseLandmarkType.rightShoulder: mlkit.PoseLandmark(
                type: mlkit.PoseLandmarkType.rightShoulder, x: 100, y: rightY, z: 0, likelihood: likelihood),
          },
        );

    test('shoulder tilt sign matches the backend (> 0: left shoulder higher)', () {
      expect(shoulderTiltDeg(pose(leftY: 200, rightY: 200)), 0);
      expect(shoulderTiltDeg(pose(leftY: 180, rightY: 200))!, greaterThan(0));
      expect(shoulderTiltDeg(pose(leftY: 200, rightY: 180))!, lessThan(0));
      expect(shoulderTiltDeg(pose(leftY: 200, rightY: 200, likelihood: 0.2)), isNull);
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: Center(child: child))),
        );

    testWidgets('SFLoader spins the 3D tee when large and is just the ring when small', (tester) async {
      bool isTee(Widget w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.startsWith('assets/loader/cloth_');
      await pump(tester, const SFLoader(label: 'Loading admin data…'));
      expect(find.byWidgetPredicate(isTee), findsOneWidget);
      expect(find.text('Loading admin data…'), findsOneWidget);

      await pump(tester, const SFLoader.small());
      expect(find.byWidgetPredicate(isTee), findsNothing);
    });

    testWidgets('BodyScanCard lists the results', (tester) async {
      await pump(tester, BodyScanCard(summary: ScanSummary.fromResult(CvAnalysisResult.fromJson(_detailedJson))));
      expect(find.text('Body & face scan'), findsOneWidget);
      expect(find.text('Rectangle'), findsOneWidget);
      expect(find.text('Round'), findsOneWidget);
      expect(find.textContaining('MediaPipe vs HRNet: Strong'), findsOneWidget);
    });
  });
}
