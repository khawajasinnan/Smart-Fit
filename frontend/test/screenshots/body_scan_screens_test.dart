import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/body_scan/screens/scan_analysis_screen.dart';
import 'package:smartfit/features/body_scan/widgets/body_scan_card.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

import '../helpers/screenshot_harness.dart';

/// Visual review of the body & face scan. Needs SF_SCREENSHOT_DIR and
/// SF_SCAN_FIXTURE_DIR (a folder with photo.jpg and the CV service's
/// detailed /analyze/app response for it as scan.json); skipped otherwise.
final String? _fixtureDir = Platform.environment['SF_SCAN_FIXTURE_DIR'];
final bool _enabled = screenshotsEnabled && _fixtureDir != null;

class _FixedCv extends CvAnalysisApiService {
  _FixedCv(this.result) : super(Dio());

  final Future<CvAnalysisResult> result;

  @override
  Future<CvAnalysisResult> analyzeBody({
    String? imageUrl,
    String? imageBase64,
    String? gender,
    double? heightCm,
    double? weightKg,
    UserProfileModel? profile,
    bool detailed = false,
  }) => result;
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode.name;

    Future<void> scan(WidgetTester tester, {required bool finished, required String name}) async {
      final photo = File('$_fixtureDir/photo.jpg').readAsBytesSync();
      final json = jsonDecode(File('$_fixtureDir/scan.json').readAsStringSync()) as Map<String, dynamic>;
      final result = finished ? Future.value(CvAnalysisResult.fromJson(json)) : Completer<CvAnalysisResult>().future;
      await pumpScreen(
        tester,
        ScanAnalysisScreen(bytes: photo),
        mode: mode,
        overrides: [
          cvAnalysisApiServiceProvider.overrideWithValue(_FixedCv(result)),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await pumpFrames(tester, Duration(milliseconds: finished ? 2400 : 1500));
      await tester.runAsync(() => precacheImage(MemoryImage(photo), tester.element(find.byType(ScanAnalysisScreen))));
      await tester.pump();
      await saveScreenshot(tester, '${name}_$suffix');
    }

    testWidgets('scan: analyzing ($suffix)', (tester) => scan(tester, finished: false, name: 'scan_analyzing'),
        skip: !_enabled);

    testWidgets('scan: results ($suffix)', (tester) => scan(tester, finished: true, name: 'scan_results'),
        skip: !_enabled);

    testWidgets('scan: chat card + loaders ($suffix)', (tester) async {
      final json = jsonDecode(File('$_fixtureDir/scan.json').readAsStringSync()) as Map<String, dynamic>;
      await pumpScreen(
        tester,
        SFScaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                BodyScanCard(summary: ScanSummary.fromResult(CvAnalysisResult.fromJson(json))),
                const SizedBox(height: 24),
                const Center(child: SFLoader(label: 'Loading admin data…')),
                const SizedBox(height: 24),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SFLoader(size: 56), SizedBox(width: 24), SFLoader.small()]),
              ],
            ),
          ),
        ),
        mode: mode,
      );
      await pumpFrames(tester, const Duration(milliseconds: 700));
      await saveScreenshot(tester, 'scan_card_$suffix');
    }, skip: !_enabled);
  }
}
