import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/scoring/data/look_score_models.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_api_service.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';
import 'package:smartfit/features/hairstyle/providers/hairstyle_provider.dart';
import 'package:smartfit/features/hairstyle/screens/hairstyle_screen.dart';
import 'package:smartfit/features/hairstyle/widgets/face_capture_camera.dart';

import '../../helpers/fake_dio_adapter.dart';

/// A valid 1x1 PNG (Image.memory needs real image bytes).
const _pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
final _photo = base64Decode(_pixel);

Map<String, dynamic> preview(String id, String name, {double score = 0.7}) => {
      'hairstyle_id': id,
      'name': name,
      'colour': 'black',
      'reason': 'Bangs balance a wider forehead.',
      'score': score,
      'preview_base64': _pixel,
    };

Map<String, dynamic> resultJson({int skipped = 0}) => {
      'face_shape': 'Heart',
      'face_shape_note': 'Estimated from face-mesh proportions.',
      'length_to_cheek': 1.25,
      'forehead_to_cheek': 0.93,
      'jaw_to_cheek': 0.75,
      'default': preview('a', 'Long wavy hair with bangs', score: 0.9),
      'alternatives': [preview('b', 'Shoulder-length straight hair'), preview('c', 'Short wavy cut')],
      'original_base64': _pixel,
      'skipped_shorter': skipped,
    };

class FakeHairstyleApi extends HairstyleApiService {
  FakeHairstyleApi() : super(Dio());

  Object? next; // a HairstyleResult or a Failure
  final calls = <String?>[];

  final occasions = <String?>[];
  final textures = <String?>[];
  final outfits = <String?>[];

  @override
  Future<HairstyleResult> suggest(
    Uint8List photo, {
    String? gender,
    int count = 6,
    String? occasion,
    String? hairTexture,
    String? outfit,
  }) async {
    calls.add(gender);
    occasions.add(occasion);
    textures.add(hairTexture);
    outfits.add(outfit);
    final n = next;
    if (n is Failure) throw n;
    return n as HairstyleResult? ?? HairstyleResult.fromJson(resultJson());
  }
}

void main() {
  group('models', () {
    test('the guide circle fits portrait phones and landscape webcams', () {
      final portrait = GuideCircle.forFrame(720, 1280);
      expect(portrait.r, closeTo(0.30, 1e-9)); // 30 % of the shorter side (the width)
      final landscape = GuideCircle.forFrame(1280, 720);
      expect(landscape.r * 1280, closeTo(0.30 * 720, 1e-6)); // same size in pixels of the shorter side
      expect(guideRect(const Size(1280, 720), landscape).height, lessThan(720)); // fits on screen
      expect(portrait.toJson(), {'cx': 0.5, 'cy': 0.45, 'r': 0.30});
    });

    test('the result keeps the best match first', () {
      final r = HairstyleResult.fromJson(resultJson(skipped: 2));
      expect(r.faceShape, 'Heart');
      expect(r.styles.map((s) => s.id), ['a', 'b', 'c']);
      expect(r.styles.first.image, _photo);
      expect(r.skippedShorter, 2);
    });

    test('profile gender -> catalog', () {
      expect(catalogGender('Male'), 'male');
      expect(catalogGender('Female'), 'female');
      expect(catalogGender('Non-binary'), isNull);
      expect(catalogGender(null), isNull);
    });
  });

  group('auto capture', () {
    test('needs two ready frames in a row', () {
      final auto = AutoCapture();
      const ready = FaceCheck(ready: true, message: 'ok');
      const notReady = FaceCheck(ready: false, code: 'TOO_FAR', message: 'Come a little closer.');
      expect(auto.add(ready), isFalse);
      expect(auto.add(notReady), isFalse); // the streak restarts
      expect(auto.add(ready), isFalse);
      expect(auto.add(ready), isTrue);
    });
  });

  group('api', () {
    test('a frame is sent with the circle', () async {
      final adapter = FakeDioAdapter((_) => {'ready': false, 'code': 'TOO_FAR', 'message': 'Come a little closer.'});
      final check = await HairstyleApiService(fakeDio(adapter))
          .checkFrame(_photo, const GuideCircle(cx: 0.5, cy: 0.45, r: 0.3));
      expect(check.ready, isFalse);
      expect(check.code, 'TOO_FAR');
      final sent = adapter.requests.single;
      expect(sent.path, '/hairstyles/face-check');
      expect((sent.data as Map)['circle'], {'cx': 0.5, 'cy': 0.45, 'r': 0.3});
    });

    test('suggest sends the gender and reads the previews', () async {
      final adapter = FakeDioAdapter((_) => resultJson());
      final r = await HairstyleApiService(fakeDio(adapter)).suggest(_photo, gender: 'female');
      expect(r.styles, hasLength(3));
      expect((adapter.requests.single.data as Map)['gender'], 'female');
    });

    test('a refused photo is a validation failure with the reason', () async {
      final adapter = FakeDioAdapter((_) => {
            'error': {'code': 'BLURRY', 'message': 'Hold still, the picture is blurry.'},
          })
        ..status = 422;
      await expectLater(
        HairstyleApiService(fakeDio(adapter)).suggest(_photo),
        throwsA(isA<ValidationFailure>().having((f) => f.code, 'code', 'BLURRY')),
      );
    });
  });

  group('controller', () {
    test('analyse -> result, select, before/after, reset', () async {
      final api = FakeHairstyleApi();
      final c = HairstyleController(api);
      await c.analyse(_photo, gender: 'male');
      expect(api.calls, ['male']);
      expect(c.state.phase, HairstylePhase.result);
      expect(c.state.current!.id, 'a');
      c.select(2);
      expect(c.state.current!.id, 'c');
      c.select(9); // out of range: ignored
      expect(c.state.selected, 2);
      c.toggleOriginal(true);
      expect(c.state.showOriginal, isTrue);
      c.select(1);
      expect(c.state.showOriginal, isFalse); // a new style shows the "after"
      c.reset();
      expect(c.state.phase, HairstylePhase.intro);
    });

    test('a refused photo vs a server problem', () async {
      final api = FakeHairstyleApi()..next = const ValidationFailure('Look straight at the camera.', code: 'FACE_TURNED');
      final c = HairstyleController(api);
      await c.analyse(_photo);
      expect(c.state.phase, HairstylePhase.error);
      expect(c.state.photoProblem, isTrue);
      api.next = const NetworkFailure();
      await c.analyse(_photo);
      expect(c.state.photoProblem, isFalse);
      expect(c.state.photo, _photo); // kept for "Try again"
    });
  });

  group('screen', () {
    late FakeHairstyleApi api;

    // Test fonts are wider than the real ones: scroll a button into view, then tap it.
    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.scrollUntilVisible(find.text(text), 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(text)); // fully on screen, not just touching the edge
      await tester.pump();
      await tester.tap(find.text(text));
    }

    // The page background animates forever, so pumpAndSettle would never settle.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pump(WidgetTester tester) async {
      api = FakeHairstyleApi();
      debugHairstylePhoto = _photo;
      addTearDown(() => debugHairstylePhoto = null);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hairstyleApiServiceProvider.overrideWithValue(api),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const HairstyleScreen()),
      ));
      await settle(tester);
    }

    testWidgets('intro -> upload -> results with the best match first', (tester) async {
      await pump(tester);
      expect(find.text('Find the hairstyle that suits your face'), findsOneWidget);
      await tapText(tester, 'Upload a photo');
      await settle(tester);
      expect(find.text('Heart'), findsOneWidget);
      expect(find.text('Long wavy hair with bangs'), findsOneWidget);
      expect(find.text('Best match'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('3 styles for you'), 150, scrollable: find.byType(Scrollable).first);
      expect(find.text('3 styles for you'), findsOneWidget);

      await tester.scrollUntilVisible(find.bySemanticsLabel('Short wavy cut'), 150,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.bySemanticsLabel('Short wavy cut'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Short wavy cut'));
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000)); // back to the big preview
      await settle(tester);
      expect(find.text('Short wavy cut'), findsWidgets);
      expect(find.text('Best match'), findsNothing);

      await tapText(tester, 'Before');
      await settle(tester);
      expect(find.bySemanticsLabel('Your photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refused photo asks for a new one', (tester) async {
      await pump(tester);
      api.next = const ValidationFailure('Hold still, the picture is blurry.', code: 'BLURRY');
      await tapText(tester, 'Open camera');
      await settle(tester);
      expect(find.text("Let's retake that photo"), findsOneWidget);
      expect(find.text('Hold still, the picture is blurry.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing); // the same photo would fail again
    });

    testWidgets('a server problem offers "Try again"', (tester) async {
      await pump(tester);
      api.next = const NetworkFailure();
      await tapText(tester, 'Upload a photo');
      await settle(tester);
      expect(find.text('Something went wrong'), findsOneWidget);
      api.next = null;
      await tapText(tester, 'Try again');
      await settle(tester);
      expect(find.text('Heart'), findsOneWidget);
    });

    testWidgets('shows the hair it measured and re-runs when the user corrects it', (tester) async {
      await pump(tester);
      api.next = HairstyleResult.fromJson({...resultJson(), 'hair_length': 'long', 'hair_texture': 'wavy',
          'hair_texture_source': 'estimated', 'renderer': 'ai'});
      await tapText(tester, 'Upload a photo');
      await settle(tester);
      expect(find.text('Long · wavy (our guess)'), findsOneWidget);
      await tapText(tester, 'Straight');
      await settle(tester);
      expect(api.textures.last, 'straight');
      await tapText(tester, 'Mehndi');
      await settle(tester);
      expect(api.occasions.last, 'mehndi');
      await tester.scrollUntilVisible(find.textContaining('your own hair redrawn'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('your own hair redrawn'), findsOneWidget);
    });

    testWidgets('a quick-preview note is shown when the AI preview was unavailable', (tester) async {
      await pump(tester);
      api.next = HairstyleResult.fromJson({...resultJson(), 'note': 'Showing a quick 2D preview: the realistic AI '
          "preview isn't available right now."});
      await tapText(tester, 'Upload a photo');
      await settle(tester);
      expect(find.textContaining('quick 2D preview'), findsOneWidget);
    });
  });

  // ── SFR-029 / SFR-035 / SFR-036: hairstyles for the chosen outfit, kept in the wardrobe ──

  group('outfit', () {
    test('suggest sends the outfit, trimmed, and leaves it out when there is none', () async {
      final adapter = FakeDioAdapter((_) => resultJson());
      final api = HairstyleApiService(fakeDio(adapter));
      await api.suggest(_photo, outfit: '  Bridal Lehenga, lehenga  ');
      await api.suggest(_photo, outfit: 'x' * 300);
      await api.suggest(_photo, outfit: '   ');
      await api.suggest(_photo);
      final sent = [for (final r in adapter.requests) (r.data as Map)['outfit']];
      expect(sent[0], 'Bridal Lehenga, lehenga');
      expect((sent[1] as String).length, 160);
      expect(sent.sublist(2), [null, null]);
      expect((adapter.requests.last.data as Map).containsKey('outfit'), isFalse);
    });

    test('the controller asks for hairstyles that go with the outfit', () async {
      final api = FakeHairstyleApi();
      final c = HairstyleController(api, outfitText: () => 'Prince Coat, prince-coats');
      await c.analyse(_photo, gender: 'male');
      expect(api.outfits, ['Prince Coat, prince-coats']);
      c.dispose();
    });

    test('previews keep their small picture for the wardrobe', () {
      final json = resultJson();
      (json['default'] as Map<String, dynamic>)['thumb_base64'] = _pixel;
      expect(HairstyleResult.fromJson(json).styles.first.thumbBase64, _pixel);
    });

    test('a hairstyle saved with a product survives saving and loading', () {
      const hair = ChosenHairstyle(id: 'a', name: 'Long waves', score: 0.9, faceShape: 'Heart', thumbBase64: 'abc');
      expect(hair.toJson().containsKey('thumb_base64'), isFalse); // the look score needs no picture
      final product = ProductRecommendation.fromJson({
        'id': 'outfitters:tee', 'brand': 'Outfitters', 'title': 'Tee', 'price_pkr': 2990,
        'product_url': 'https://outfitters.com.pk/products/tee', 'tryon_paths': {'front': 'u/x.jpg'},
      });
      final saved = ProductRecommendation.fromJson(product.withHairstyle(hair.toWardrobeJson()).toJson());
      expect(saved.hasHairstyle, isTrue);
      expect(saved.tryOnPaths, {'front': 'u/x.jpg'}); // the try-on is kept
      final back = ChosenHairstyle.fromWardrobeJson(saved.hairstyle)!;
      expect([back.id, back.name, back.score, back.faceShape, back.thumbBase64], ['a', 'Long waves', 0.9, 'Heart', 'abc']);
      expect(ChosenHairstyle.fromWardrobeJson(null), isNull);
      expect(ChosenHairstyle.fromWardrobeJson({'name': 'no id'}), isNull);
      expect(product.hasHairstyle, isFalse);
    });
  });
}
