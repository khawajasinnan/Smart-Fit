import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

import '../../helpers/fake_dio_adapter.dart';

/// The server's photo checks (HRNet person check, clothes check) come back as
/// a "retake this photo" failure for the right side, never a generic error.
void main() {
  Future<Object> startWithError(String code, Map<String, dynamic> details) async {
    final adapter = FakeDioAdapter((_) => {
          'error': {'code': code, 'message': 'Reason from the server.', 'details': details},
        })
      ..status = 422;
    final api = TryOnApiService(fakeDio(adapter));
    try {
      await api.start(productId: 'p', photos: {TryOnAngle.front: Uint8List(4), TryOnAngle.back: Uint8List(4)});
    } catch (e) {
      return e;
    }
    fail('expected a failure');
  }

  for (final code in ['NO_PERSON', 'MULTIPLE_PEOPLE', 'POSE_NOT_UPRIGHT', 'PERSON_TOO_SMALL', 'BODY_CUT_OFF']) {
    test('$code asks to retake that side', () async {
      final error = await startWithError(code, {'angle': 'back'});
      expect(error, isA<TryOnPhotoFailure>());
      final failure = error as TryOnPhotoFailure;
      expect(failure.angle, 'back');
      expect(failure.code, code);
      expect(failure.message, 'Reason from the server.');
    });
  }

  test('a refused clothes photo points at the garment', () async {
    final error = await startWithError('NOT_CLOTHING', {'angle': 'garment'});
    expect((error as TryOnPhotoFailure).angle, 'garment');
  });

  test('an item the brand no longer sells is "unavailable: gone", not an error', () async {
    final error = await startWithError('TRYON_UNAVAILABLE', {'reason': 'gone'});
    expect(error, isA<TryOnUnavailableFailure>());
    expect((error as TryOnUnavailableFailure).reason, 'gone');
    expect(error.message, 'Reason from the server.');
  });

  test('SFR-025: your size sold out is "unavailable: size_sold_out" with the message from the server', () async {
    final error = await startWithError('TRYON_UNAVAILABLE', {'reason': 'size_sold_out'});
    expect(error, isA<TryOnUnavailableFailure>());
    expect((error as TryOnUnavailableFailure).reason, 'size_sold_out');
    expect(error.message, 'Reason from the server.');
  });
}
