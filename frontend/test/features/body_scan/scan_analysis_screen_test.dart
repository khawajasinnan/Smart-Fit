import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/body_scan/screens/scan_analysis_screen.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';

// 1x1 PNG
final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakeCv extends CvAnalysisApiService {
  _FakeCv() : super(Dio());

  final calls = <bool>[];
  Completer<CvAnalysisResult> next = Completer();

  @override
  Future<CvAnalysisResult> analyzeBody({
    String? imageUrl,
    String? imageBase64,
    String? gender,
    double? heightCm,
    double? weightKg,
    UserProfileModel? profile,
    bool detailed = false,
  }) {
    calls.add(detailed);
    return next.future;
  }
}

void main() {
  late _FakeCv cv;
  BodyScanOutcome? popped;

  // Created inside each test: the fake's futures must belong to the test's
  // fake-async zone, or completing them never reaches the screen.
  Future<void> open(WidgetTester tester) async {
    cv = _FakeCv();
    popped = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cvAnalysisApiServiceProvider.overrideWithValue(cv),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, app) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: app!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => popped = await Navigator.of(context).push<BodyScanOutcome>(
                MaterialPageRoute(builder: (_) => ScanAnalysisScreen(bytes: _photo)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // decode the photo
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('runs a detailed scan, then shows the results and returns them', (tester) async {
    await open(tester);
    expect(cv.calls, [true]);
    expect(find.text('Analyzing your scan'), findsOneWidget);
    expect(find.text('Detecting 33 body landmarks'), findsOneWidget);

    cv.next.complete(CvAnalysisResult.fromJson(const {
      'success': true,
      'body_shape': 'Rectangle',
      'face': {'face_shape': 'Oval', 'length_to_cheek': 1.2, 'forehead_to_cheek': 0.86, 'jaw_to_cheek': 0.79},
      'shoulders': {'tilt_deg': 1.0, 'level': 'Level', 'sources': ['MediaPipe', 'HRNet']},
      'model_agreement': {'compared_points': 12, 'mean_offset_pct': 8.0, 'agreement': 'Strong'},
      'models_used': ['MediaPipe Pose', 'HRNet-W32 (COCO-17)'],
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Your scan results'), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Oval'), findsOneWidget);
    expect(find.text('Strong agreement'), findsOneWidget);

    await tester.tap(find.text('Send to stylist'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(popped!.analysis!.bodyShape, 'Rectangle');
    expect(popped!.bytes, _photo);
  });

  testWidgets('a failed scan offers a retry or the photo on its own', (tester) async {
    await open(tester);
    cv.next.complete(const CvAnalysisResult(success: false, error: 'Could not reach the analysis server.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Scan not finished'), findsOneWidget);
    expect(find.text('Could not reach the analysis server.'), findsOneWidget);

    cv.next = Completer();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(cv.calls, [true, true]);

    cv.next.complete(const CvAnalysisResult(success: false, error: 'Still down.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Photo only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(popped!.analysis, isNull);
    expect(popped!.bytes, _photo);
  });
}
