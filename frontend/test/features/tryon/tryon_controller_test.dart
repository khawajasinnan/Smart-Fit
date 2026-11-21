import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/features/tryon/providers/tryon_provider.dart';

const _product = ProductRecommendation(
  id: 'outfitters:hoodie',
  brand: 'Outfitters',
  title: 'Relaxed Fit Hoodie',
  productUrl: 'https://outfitters.com.pk/products/hoodie',
);

Map<String, dynamic> _job(String status, List<(String, String)> views, {String mode = 'modal'}) => {
  'job_id': 'job-1',
  'status': status,
  'product_id': 'outfitters:hoodie',
  'category': 'upper',
  'mode': mode,
  'model_version': 'idm-vton+dresscode-v1',
  'elapsed_seconds': 12.5,
  'estimated_seconds': 150,
  'views': [
    for (final (angle, s) in views)
      {
        'angle': angle,
        'status': s,
        if (s == 'done') 'image_url': 'https://signed/$angle.jpg',
        if (s == 'done') 'storage_path': 'user-a/$angle.jpg',
        if (s == 'failed') 'error_code': 'NO_PERSON',
        if (s == 'failed') 'message': 'No body in the $angle photo.',
      },
  ],
};

class _FakeApi extends TryOnApiService {
  _FakeApi() : super(Dio());

  Object? startResult; // a job map or a Failure to throw
  final List<Object> polls = []; // job maps or Failures, one per poll
  Map<TryOnAngle, Uint8List>? sentPhotos;
  String? sentProductId;
  Uint8List? sentGarment;
  String? sentCategory;
  String? sentName;
  double? sentChest;
  double? sentWaist;
  int pollCount = 0;

  @override
  Future<TryOnJob> start({
    String? productId,
    Uint8List? garmentImage,
    String? garmentCategory,
    String? garmentName,
    double? garmentChestWidthCm,
    double? garmentWaistWidthCm,
    required Map<TryOnAngle, Uint8List> photos,
    bool? sizeCompatible,
    String? size,
  }) async {
    sentPhotos = photos;
    sentProductId = productId;
    sentGarment = garmentImage;
    sentCategory = garmentCategory;
    sentName = garmentName;
    sentChest = garmentChestWidthCm;
    sentWaist = garmentWaistWidthCm;
    final r = startResult;
    if (r is Failure) throw r;
    return TryOnJob.fromJson(r! as Map<String, dynamic>);
  }

  @override
  Future<TryOnJob> poll(String jobId) async {
    final r = polls[pollCount < polls.length ? pollCount : polls.length - 1];
    pollCount++;
    if (r is Failure) throw r;
    return TryOnJob.fromJson(r as Map<String, dynamic>);
  }
}

Uint8List _photo() => Uint8List.fromList(List.filled(10, 1));

Future<void> _waitFor(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _FakeApi api;
  late TryOnController c;

  setUp(() {
    api = _FakeApi();
    c = TryOnController(api, pollEvery: const Duration(milliseconds: 10));
  });
  tearDown(() => c.dispose());

  test('quick mode is the default; 360 mode needs all four sides', () {
    expect(c.state.spin360, isFalse);
    expect(c.state.step, 1); // nothing chosen yet
    c.selectProduct(_product);
    expect(c.state.step, 2);
    expect(c.state.readyToStart, isFalse);
    c.setPhoto(TryOnAngle.front, _photo());
    expect(c.state.readyToStart, isTrue);
    c.setSpin360(true);
    expect(c.state.readyToStart, isFalse);
    expect(c.state.missingPhotos, 3);
  });

  test("the user's own clothes photo is sent instead of a product", () async {
    final garment = Uint8List.fromList(List.filled(20, 7));
    c
      ..selectOwnGarment(garment, GarmentType.lower, name: '  blue jeans ', chestWidthCm: 50, waistWidthCm: 42)
      ..setPhoto(TryOnAngle.front, _photo());
    expect(c.state.product, isNull);
    expect(c.state.ownGarment!.title, 'blue jeans');
    api.startResult = _job('done', [('front', 'done')]);
    await c.start();
    expect(api.sentProductId, isNull);
    expect(api.sentGarment, garment);
    expect(api.sentCategory, 'lower');
    expect(api.sentName, 'blue jeans');
    expect(api.sentWaist, 42); // bottoms send the waist ...
    expect(api.sentChest, isNull); // ... and never a chest width
    expect(c.state.job!.fit, isNull); // the fake job has no fit block
    expect(c.state.phase, TryOnPhase.result);
    expect(c.state.step, 3);
  });

  test('an empty clothes name is not sent and the type names it', () {
    c.selectOwnGarment(_photo(), GarmentType.dress, name: '   ');
    expect(c.state.ownGarment!.name, isNull);
    expect(c.state.ownGarment!.title, 'My full outfit');
  });

  test('choosing a product replaces the own clothes photo (never both)', () {
    c
      ..selectOwnGarment(_photo(), GarmentType.upper)
      ..selectProduct(_product);
    expect(c.state.ownGarment, isNull);
    expect(c.state.product, _product);
    c.selectOwnGarment(_photo(), GarmentType.upper);
    expect(c.state.product, isNull);
  });

  test('a rejected clothes photo goes back to step 1 with the reason, keeping the photos', () async {
    c
      ..selectOwnGarment(_photo(), GarmentType.upper)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = const TryOnPhotoFailure('Too small.', angle: 'garment', code: 'IMAGE_TOO_SMALL');
    await c.start();
    expect(c.state.step, 1);
    expect(c.state.ownGarment, isNull);
    expect((c.state.failure! as TryOnPhotoFailure).angle, 'garment');
    expect(c.state.photos.keys, [TryOnAngle.front]);
  });

  test('a 360 job runs, polls and ends with every side in turntable order', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(true);
    for (final a in TryOnAngle.values) {
      c.setPhoto(a, _photo());
    }
    api.startResult = _job('running', [
      ('front', 'running'),
      ('right', 'running'),
      ('back', 'running'),
      ('left', 'running'),
    ]);
    api.polls.addAll([
      _job('running', [('front', 'done'), ('right', 'running'), ('back', 'running'), ('left', 'running')]),
      _job('done', [('front', 'done'), ('right', 'done'), ('back', 'done'), ('left', 'done')]),
    ]);
    await c.start();
    expect(c.state.phase, TryOnPhase.running);
    expect(api.sentPhotos!.keys, TryOnAngle.values);
    await _waitFor(() => c.state.phase == TryOnPhase.result);
    expect(c.state.phase, TryOnPhase.result);
    expect(c.state.job!.finishedViews.map((v) => v.angle), TryOnAngle.values);
    expect(c.state.job!.storagePaths, {
      'front': 'user-a/front.jpg',
      'right': 'user-a/right.jpg',
      'back': 'user-a/back.jpg',
      'left': 'user-a/left.jpg',
    });
  });

  test('a partial result still shows the sides that worked', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(false)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = _job('partial', [('front', 'done'), ('back', 'failed')]);
    await c.start();
    expect(c.state.phase, TryOnPhase.result);
    expect(c.state.job!.finishedViews.length, 1);
  });

  test('every side failing is an error with the friendly message', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(false)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = _job('failed', [('front', 'failed')]);
    await c.start();
    expect(c.state.phase, TryOnPhase.error);
    expect(c.state.failure!.message, 'No body in the front photo.');
  });

  test('SFR-027: an unavailable item gets its own state', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(false)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = const TryOnUnavailableFailure('Not for fabric.', reason: 'not_supported');
    await c.start();
    expect(c.state.phase, TryOnPhase.unavailable);
  });

  test('a rejected photo goes back to the photos with that side named', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(false)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = const TryOnPhotoFailure('Too small.', angle: 'front', code: 'IMAGE_TOO_SMALL');
    await c.start();
    expect(c.state.phase, TryOnPhase.setup);
    expect((c.state.failure! as TryOnPhotoFailure).angle, 'front');
  });

  test('brief connection drops are tolerated; a long outage ends in an error', () async {
    c
      ..selectProduct(_product)
      ..setSpin360(false)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = _job('running', [('front', 'running')]);
    api.polls.addAll([
      const NetworkFailure(),
      const NetworkFailure(),
      _job('done', [('front', 'done')]),
    ]);
    await c.start();
    await _waitFor(() => c.state.phase != TryOnPhase.running);
    expect(c.state.phase, TryOnPhase.result);

    api
      ..pollCount = 0
      ..polls.replaceRange(0, api.polls.length, [const NetworkFailure()]);
    c.backToSetup();
    await c.start();
    await _waitFor(() => c.state.phase != TryOnPhase.running);
    expect(c.state.phase, TryOnPhase.error);
    expect(api.pollCount, greaterThanOrEqualTo(5));
  });

  test('changing the product keeps the photos', () {
    c
      ..selectProduct(_product)
      ..setPhoto(TryOnAngle.front, _photo())
      ..clearProduct();
    expect(c.state.product, isNull);
    expect(c.state.photos.keys, [TryOnAngle.front]);
  });

  test("the server's fit check is read from the job", () {
    final fits = TryOnJob.fromJson({
      ..._job('done', [('front', 'done')]),
      'fit': {'status': 'fits', 'basis': 'size_chart', 'size': 'L', 'note': 'Size L from this chart'},
    });
    expect(fits.fit!.fits, isTrue);
    expect(fits.fit!.size, 'L');
    final unknown = TryOnJob.fromJson({
      ..._job('done', [('front', 'done')]),
      'fit': {'status': 'unknown', 'basis': 'unknown', 'note': 'No size chart'},
    });
    expect(unknown.fit!.fits, isFalse);
  });

  test('a refused clothes photo (not clothing / wrong type) goes back to step 1', () async {
    c
      ..selectOwnGarment(_photo(), GarmentType.upper, chestWidthCm: 52)
      ..setPhoto(TryOnAngle.front, _photo());
    api.startResult = const TryOnPhotoFailure('This looks like a bottom.', angle: 'garment', code: 'GARMENT_MISMATCH');
    await c.start();
    expect(c.state.step, 1);
    expect(c.state.failure!.message, 'This looks like a bottom.');
  });

  test('test mode is recognised from the job', () {
    final job = TryOnJob.fromJson(_job('done', [('front', 'done')], mode: 'mock'));
    expect(job.isTestMode, isTrue);
  });

  test('saved try-on paths survive the wardrobe JSON round trip', () {
    final saved = _product.withTryOn({'front': 'user-a/f.jpg', 'back': 'user-a/b.jpg'});
    final back = ProductRecommendation.fromJson(saved.toJson());
    expect(back.tryOnPaths, {'front': 'user-a/f.jpg', 'back': 'user-a/b.jpg'});
    expect(back.hasTryOn, isTrue);
    expect(ProductRecommendation.fromJson(_product.toJson()).toJson().containsKey('tryon_paths'), isFalse);
  });
}
