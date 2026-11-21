import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

final tryOnApiServiceProvider = Provider<TryOnApiService>((ref) => TryOnApiService(ref.watch(apiDioProvider)));

/// Calls the gateway's /tryon routes (SFR-026..028). Every error becomes a
/// [Failure] with plain, user-facing text.
class TryOnApiService {
  TryOnApiService(this._dio);

  final Dio _dio;

  /// Starts a try-on of a catalog product ([productId]) or of a photo of the
  /// user's own clothes ([garmentImage] + [garmentCategory] "upper" | "lower" | "dress").
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
    assert((productId == null) != (garmentImage == null), 'pass a product or a garment photo, not both');
    assert(garmentImage == null || garmentCategory != null, 'a garment photo needs its category');
    final body = {
      'product_id': ?productId,
      if (garmentImage != null)
        'garment': {
          'image_base64': base64Encode(garmentImage),
          'category': garmentCategory,
          'name': ?garmentName,
          'chest_width_cm': ?garmentChestWidthCm,
          'waist_width_cm': ?garmentWaistWidthCm,
        },
      'views': [
        for (final e in photos.entries) {'angle': e.key.id, 'image_base64': base64Encode(e.value)},
      ],
      'size_compatible': ?sizeCompatible,
      'size': ?size,
    };
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.tryOnPath,
        data: body,
        // a little longer than the gateway's 90 s, so its clear message reaches the user first
        options: Options(sendTimeout: const Duration(seconds: 90), receiveTimeout: const Duration(seconds: 100)),
      );
      return TryOnJob.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  Future<TryOnJob> poll(String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${ApiEndpoints.tryOnPath}/$jobId',
        options: Options(receiveTimeout: const Duration(seconds: 70)),
      );
      return TryOnJob.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Fresh signed URLs for saved try-on images (wardrobe).
  Future<Map<String, String>> sign(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.tryOnSignPath, data: {'paths': paths});
      final urls = (res.data?['urls'] as Map?) ?? const {};
      return {for (final e in urls.entries) e.key.toString(): e.value.toString()};
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  static const _photoCodes = {
    'INVALID_IMAGE',
    'IMAGE_TOO_SMALL',
    'IMAGE_TOO_LARGE',
    'NO_PERSON',
    'MULTIPLE_PEOPLE',
    'POSE_NOT_UPRIGHT',
    'PERSON_TOO_SMALL',
    'BODY_CUT_OFF',
  };

  static Failure _failure(DioException e) {
    final data = e.response?.data;
    final error = data is Map ? data['error'] : null;
    if (error is Map) {
      final code = error['code']?.toString();
      final message = error['message']?.toString() ?? 'Try-on is not available right now.';
      final details = error['details'] is Map ? error['details'] as Map : const {};
      if (code == 'TRYON_UNAVAILABLE') {
        return TryOnUnavailableFailure(message, reason: details['reason']?.toString() ?? 'not_supported');
      }
      if (code == 'NOT_CLOTHING' || code == 'GARMENT_MISMATCH') {
        // The clothes photo was checked and refused: back to step 1 with the reason.
        return TryOnPhotoFailure(message, angle: 'garment', code: code);
      }
      if (_photoCodes.contains(code)) {
        // A person photo to retake (bad file, or HRNet's check: cut off, too far, not upright...).
        return TryOnPhotoFailure(message, angle: details['angle']?.toString(), code: code);
      }
    }
    return Failure.fromDio(e);
  }
}
