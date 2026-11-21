import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/features/tryon/providers/tryon_provider.dart';
import 'package:smartfit/features/tryon/screens/tryon_screen.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_bottom_nav_bar.dart';

import '../helpers/fake_wardrobe.dart';
import '../helpers/screenshot_harness.dart';

/// Visual review of the try-on flow. Skipped unless SF_SCREENSHOT_DIR is set.
/// The "person" photos are drawn stand-ins (tests can't use real photos).

class _Fixed extends TryOnController {
  _Fixed(TryOnState s) : super(TryOnApiService(Dio())) {
    state = s;
  }

  void refresh() => state = state.copyWith();
}

const _product = ProductRecommendation(
  id: 'outfitters:hoodie',
  brand: 'Outfitters',
  title: 'Relaxed Fit Hoodie',
  pricePkr: 6490,
  imageUrl: 'https://cdn.shopify.com/s/files/photo-1001-2001.jpg',
  productUrl: 'https://outfitters.com.pk/products/hoodie',
);

Future<Uint8List> _drawPerson(Color background, Color garment, {bool back = false}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 300, 400), Paint()..color = background);
  final skin = Paint()..color = const Color(0xFFBB8768);
  c.drawCircle(const Offset(150, 70), 34, back ? (Paint()..color = const Color(0xFF2B1D16)) : skin);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(95, 110, 110, 150), const Radius.circular(28)),
      Paint()..color = garment);
  c.drawRect(const Rect.fromLTWH(108, 255, 36, 120), Paint()..color = const Color(0xFF33363F));
  c.drawRect(const Rect.fromLTWH(156, 255, 36, 120), Paint()..color = const Color(0xFF33363F));
  final img = await rec.endRecording().toImage(300, 400);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

TryOnJob _job(String status, Map<TryOnAngle, String> views,
        {bool testMode = false, bool fit = false, String fitStatus = 'fits', String? fitNote}) =>
    TryOnJob.fromJson({
      if (fit)
        'fit': {
          'status': fitStatus,
          'basis': 'measurements',
          'note': fitNote ?? 'Chest 110 cm on you 96 cm',
        },
      'job_id': 'j',
      'status': status,
      'product_id': _product.id,
      'category': 'upper',
      'mode': testMode ? 'mock' : 'modal',
      'model_version': 'idm-vton+dresscode-v1',
      'elapsed_seconds': 40.0,
      'estimated_seconds': 150,
      'views': [
        for (final e in views.entries)
          {
            'angle': e.key.id,
            'status': e.value,
            if (e.value == 'done') 'image_url': 'https://signed.example/${e.key.id}.jpg',
            if (e.value == 'done') 'storage_path': 'u/${e.key.id}.jpg',
            if (e.value == 'failed') 'message': "We couldn't find your whole body in the ${e.key.id} photo.",
          },
      ],
    });

void main() {
  late Map<TryOnAngle, Uint8List> photos;
  late Map<TryOnAngle, Uint8List> dressed;

  Future<void> prepare(WidgetTester tester) async {
    await tester.runAsync(() async {
      photos = {
        for (final a in TryOnAngle.values)
          a: await _drawPerson(const Color(0xFFE9E4EF), const Color(0xFF7A8A9A), back: a == TryOnAngle.back),
      };
      dressed = {
        for (final a in TryOnAngle.values)
          a: await _drawPerson(const Color(0xFFE9E4EF), const Color(0xFF6C4CE0), back: a == TryOnAngle.back),
      };
    });
  }

  Future<void> shoot(WidgetTester tester, String name, TryOnState state, ThemeMode mode) async {
    final fixed = _Fixed(state);
    // A fresh ProviderScope per shot (a re-pumped scope keeps its providers).
    await tester.pumpWidget(const SizedBox());
    // Like the app shell: the floating nav bar over an extended body.
    final screen = Scaffold(
      extendBody: true,
      body: const TryOnScreen(),
      bottomNavigationBar: SFBottomNavBar(currentIndex: 1, onTap: (_) {}),
    );
    await pumpScreen(tester, screen, mode: mode, overrides: [
      tryOnControllerProvider.overrideWith((ref) => fixed),
      wardrobeNotifierProvider.overrideWith((ref) => FakeWardrobe(sampleWardrobe(DateTime.now()))),
    ]);
    // result images: the drawn "dressed" figures instead of the network
    ImageProvider local(String url) {
      for (final a in TryOnAngle.values) {
        if (url.endsWith('/${a.id}.jpg')) return MemoryImage(dressed[a]!);
      }
      return MemoryImage(photos[TryOnAngle.front]!);
    }

    SafeNetworkImage.debugImageProviderOverride = local;
    debugTryOnImageOverride = local;
    addTearDown(() => debugTryOnImageOverride = null);
    fixed.refresh();
    await tester.runAsync(() async {
      for (final b in [...photos.values, ...dressed.values]) {
        await precacheImage(MemoryImage(b), tester.element(find.byType(TryOnScreen)));
      }
    });
    await pumpFrames(tester);
    await saveScreenshot(tester, 'tryon_${name}_${mode.name}');
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('try-on screens (${mode.name})', (tester) async {
      await prepare(tester);
      final own = OwnGarment(bytes: dressed[TryOnAngle.front]!, type: GarmentType.upper, name: 'Purple cotton tee');
      await shoot(tester, '1_clothes', const TryOnState(), mode);
      debugPickedClothes = (dressed[TryOnAngle.front]!, GarmentType.dress);
      await shoot(tester, '1_own_measure', const TryOnState(), mode);
      debugPickedClothes = null;
      await shoot(
        tester,
        'own_too_small',
        TryOnState(
          ownGarment: own,
          phase: TryOnPhase.result,
          photos: {TryOnAngle.front: photos[TryOnAngle.front]!},
          job: _job('done', {TryOnAngle.front: 'done'},
              fit: true,
              fitStatus: 'small',
              fitNote: 'Too small at the chest (92 cm around, you need at least 100 cm)'),
        ),
        mode,
      );
      await shoot(
        tester,
        'own_too_big',
        TryOnState(
          ownGarment: own,
          phase: TryOnPhase.result,
          photos: {TryOnAngle.front: photos[TryOnAngle.front]!},
          job: _job('done', {TryOnAngle.front: 'done'},
              fit: true, fitStatus: 'big', fitNote: 'Chest 180 cm on you 96 cm. Loose at the chest'),
        ),
        mode,
      );
      await shoot(tester, '2_quick_empty', const TryOnState(product: _product), mode);
      await shoot(
        tester,
        '2_quick_ready',
        TryOnState(product: _product, photos: {TryOnAngle.front: photos[TryOnAngle.front]!}),
        mode,
      );
      await shoot(
        tester,
        '2_360_partial',
        TryOnState(
          ownGarment: own,
          spin360: true,
          photos: {TryOnAngle.front: photos[TryOnAngle.front]!, TryOnAngle.back: photos[TryOnAngle.back]!},
        ),
        mode,
      );
      await shoot(
        tester,
        'own_result',
        TryOnState(
          ownGarment: own,
          phase: TryOnPhase.result,
          photos: {TryOnAngle.front: photos[TryOnAngle.front]!},
          job: _job('done', {TryOnAngle.front: 'done'}, fit: true),
        ),
        mode,
      );
      await shoot(
        tester,
        'running',
        TryOnState(
          product: _product,
          phase: TryOnPhase.running,
          photos: photos,
          job: _job('running', {
            TryOnAngle.front: 'done',
            TryOnAngle.right: 'running',
            TryOnAngle.back: 'running',
            TryOnAngle.left: 'queued',
          }),
        ),
        mode,
      );
      await shoot(
        tester,
        'result',
        TryOnState(
          product: _product,
          phase: TryOnPhase.result,
          photos: photos,
          job: _job('partial', {
            TryOnAngle.front: 'done',
            TryOnAngle.right: 'done',
            TryOnAngle.back: 'done',
            TryOnAngle.left: 'failed',
          }, testMode: true),
        ),
        mode,
      );
      await shoot(
        tester,
        'unavailable',
        const TryOnState(
          product: _product,
          phase: TryOnPhase.unavailable,
          failure: TryOnUnavailableFailure(
            "Try-on isn't available for this item (unstitched fabric or an accessory). You can still see its photos "
            'and view it on the store.',
            reason: 'not_supported',
          ),
        ),
        mode,
      );
      await shoot(
        tester,
        'unavailable_gone',
        const TryOnState(
          product: _product,
          phase: TryOnPhase.unavailable,
          failure: TryOnUnavailableFailure(
            "Outfitters no longer sells this item, so it can't be tried on. Try something similar instead.",
            reason: 'gone',
          ),
        ),
        mode,
      );
    }, skip: !screenshotsEnabled);
  }
}
