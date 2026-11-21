import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_api_service.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';
import 'package:smartfit/features/hairstyle/providers/hairstyle_provider.dart';
import 'package:smartfit/features/hairstyle/screens/hairstyle_screen.dart';
import 'package:smartfit/features/hairstyle/widgets/face_capture_camera.dart';

import '../helpers/screenshot_harness.dart';

/// Visual review of the hairstyle flow. Skipped unless SF_SCREENSHOT_DIR is set.
/// The faces are drawn stand-ins (tests can't use real photos).

class _Fixed extends HairstyleController {
  _Fixed(HairstyleState s) : super(HairstyleApiService(Dio())) {
    state = s;
  }
}

Future<Uint8List> _drawFace(Color hair, {bool bangs = false, bool long = false}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 300, 400), Paint()..color = const Color(0xFFE6E1EA));
  final skin = Paint()..color = const Color(0xFFC08A6A);
  c.drawRect(const Rect.fromLTWH(120, 250, 60, 80), skin); // neck
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(60, 320, 180, 120), const Radius.circular(40)),
      Paint()..color = const Color(0xFF2E3A59));
  if (long) c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(70, 80, 160, 250), const Radius.circular(60)), Paint()..color = hair);
  c.drawOval(const Rect.fromLTWH(95, 95, 110, 150), skin);
  c.drawArc(const Rect.fromLTWH(85, 70, 130, 110), 3.14, 3.14, true, Paint()..color = hair);
  if (bangs) c.drawRect(const Rect.fromLTWH(100, 120, 100, 22), Paint()..color = hair);
  final eye = Paint()..color = const Color(0xFF2B1D16);
  c.drawCircle(const Offset(128, 165), 5, eye);
  c.drawCircle(const Offset(172, 165), 5, eye);
  c.drawArc(const Rect.fromLTWH(132, 195, 36, 18), 0.2, 2.7, false, Paint()
    ..color = const Color(0xFF8A3B3B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3);
  final img = await rec.endRecording().toImage(300, 400);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late Map<String, Uint8List> faces;

  Future<void> shoot(WidgetTester tester, String name, HairstyleState state, ThemeMode mode,
      {Widget screen = const HairstyleScreen()}) async {
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, screen, mode: mode, overrides: [
      hairstyleControllerProvider.overrideWith((ref) => _Fixed(state)),
      currentUserProvider.overrideWithValue(null),
    ]);
    await tester.runAsync(() async {
      for (final b in faces.values) {
        await precacheImage(MemoryImage(b), tester.element(find.byType(MaterialApp)));
      }
    });
    await pumpFrames(tester);
    await saveScreenshot(tester, 'hairstyle_${name}_${mode.name}');
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('hairstyle screens (${mode.name})', (tester) async {
      await tester.runAsync(() async {
        faces = {
          'original': await _drawFace(const Color(0xFF2B1D16)),
          'a': await _drawFace(const Color(0xFF5A3A22), bangs: true, long: true),
          'b': await _drawFace(const Color(0xFF1E1410), long: true),
          'c': await _drawFace(const Color(0xFF8C6A3F), bangs: true),
        };
      });
      HairstylePreview p(String id, String name, String reason) => HairstylePreview(
          id: id, name: name, colour: 'brown', reason: reason, score: 0.8, image: faces[id]!);
      final result = HairstyleResult(
        faceShape: 'Heart',
        faceShapeNote: 'Estimated from face-mesh proportions.',
        styles: [
          p('a', 'Long wavy hair with bangs', 'Bangs balance a wider forehead.'),
          p('b', 'Long straight hair', 'A neutral choice for a heart face.'),
          p('c', 'Short wavy cut with bangs', 'Bangs balance a wider forehead.'),
        ],
        original: faces['original']!,
        hairLength: 'long',
        hairTexture: 'wavy',
        hairTextureSource: 'estimated',
        isAi: true,
      );
      await shoot(tester, '1_intro', const HairstyleState(), mode);
      await shoot(tester, '2_analysing', HairstyleState(phase: HairstylePhase.analysing, photo: faces['original']), mode);
      await shoot(tester, '3_result', HairstyleState(phase: HairstylePhase.result, photo: faces['original'], result: result),
          mode);
      await shoot(
        tester,
        '4_retake',
        HairstyleState(
          phase: HairstylePhase.error,
          photo: faces['original'],
          failure: const ValidationFailure('Look straight at the camera.', code: 'FACE_TURNED'),
        ),
        mode,
      );
      // the camera's guide overlay on a drawn frame
      await shoot(
        tester,
        '5_guide',
        const HairstyleState(),
        mode,
        screen: Builder(
          builder: (context) => Stack(fit: StackFit.expand, children: [
            Image.memory(faces['original']!, fit: BoxFit.cover),
            CustomPaint(
              painter: GuidePainter(circle: GuideCircle.forFrame(390, 844), state: GuideState.ready, progress: 0.5),
            ),
          ]),
        ),
      );
      expect(base64Encode(faces['a']!).isNotEmpty, isTrue);
    }, skip: !screenshotsEnabled);
  }
}
