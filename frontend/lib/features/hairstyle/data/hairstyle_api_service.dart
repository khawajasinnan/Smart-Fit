import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';

final hairstyleApiServiceProvider = Provider<HairstyleApiService>((ref) => HairstyleApiService(ref.watch(apiDioProvider)));

/// Hairstyle service via the gateway (SFR-029..031). Photos are sent, checked
/// and rendered in memory on the server; nothing is stored.
class HairstyleApiService {
  HairstyleApiService(this._dio);

  final Dio _dio;

  /// One camera frame: is the face in [circle], straight, sharp and well lit?
  Future<FaceCheck> checkFrame(Uint8List jpeg, GuideCircle circle) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.hairstyleFaceCheckPath,
        data: {'image_base64': base64Encode(jpeg), 'circle': circle.toJson()},
        options: Options(sendTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)),
      );
      return FaceCheck.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// The face photo -> face shape + hairstyles rendered on it.
  /// [gender] "male" / "female" picks the catalog; null shows both.
  /// [occasion] (e.g. "mehndi") favours fitting styles; [hairTexture] "straight" / "wavy"
  /// is the user's own description (null: estimated from the photo).
  Future<HairstyleResult> suggest(
    Uint8List photo, {
    String? gender,
    int count = 6,
    String? occasion,
    String? hairTexture,
    String? outfit,
  }) async {
    final outfitText = outfit == null || outfit.trim().isEmpty
        ? null
        : (outfit.trim().length > 160 ? outfit.trim().substring(0, 160) : outfit.trim());
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.hairstylesPath,
        data: {
          'image_base64': base64Encode(photo),
          'gender': ?gender,
          'count': count,
          'occasion': ?occasion,
          'hair_texture': ?hairTexture,
          // SFR-029: the chosen outfit's name and type steer the suggestions
          'outfit': ?outfitText,
        },
        // the AI previews are made on a GPU: the first request after a quiet spell can take a minute or two
        options: Options(sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 200)),
      );
      return HairstyleResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}

/// The profile's gender as the catalog understands it (others: both catalogs).
String? catalogGender(String? profileGender) {
  final g = profileGender?.trim().toLowerCase();
  if (g == 'male' || g == 'man') return 'male';
  if (g == 'female' || g == 'woman') return 'female';
  return null;
}
