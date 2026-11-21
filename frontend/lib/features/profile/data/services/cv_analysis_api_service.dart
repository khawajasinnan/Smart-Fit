import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

final cvAnalysisApiServiceProvider = Provider<CvAnalysisApiService>(
  (ref) => CvAnalysisApiService(ref.watch(apiDioProvider)),
);

/// Service that calls the FastAPI backend to analyze a user's photo
/// for body detection, pose estimation, body shape, size, and skin tone.
///
/// SRDS refs: SFR-019 (body shape), SFR-020 (size estimation)
class CvAnalysisApiService {
  CvAnalysisApiService(this._dio);

  final Dio _dio;

  static const Duration _timeout = Duration(seconds: 45);

  /// Analyze a user photo for body shape, size estimation, and skin tone.
  ///
  /// [imageUrl] — URL of the user's profile photo (from Supabase Storage)
  /// [profile] — Optional user profile for measurement-enhanced accuracy
  /// [detailed] — also run the face mesh and HRNet (face shape, shoulders,
  /// both skeletons) for the scan view
  Future<CvAnalysisResult> analyzeBody({
    String? imageUrl,
    String? imageBase64,
    String? gender,
    double? heightCm,
    double? weightKg,
    UserProfileModel? profile,
    bool detailed = false,
  }) async {
    final body = <String, dynamic>{
      if (detailed) 'detailed': true,
      if (imageUrl != null) 'image_url': imageUrl,
      if (imageBase64 != null) 'image_base64': imageBase64,
      if (gender != null) 'gender': gender,
      if (heightCm != null) 'height_cm': heightCm,
      if (weightKg != null) 'weight_kg': weightKg,
    };

    // Pass profile measurements if available — improves size accuracy and
    // enables the full body-shape classification.
    if (profile != null) {
      if (profile.gender != null) body['gender'] = profile.gender;
      if (profile.heightCm != null) body['height_cm'] = profile.heightCm;
      if (profile.weightKg != null) body['weight_kg'] = profile.weightKg;
      if (profile.chestCm != null) body['chest_cm'] = profile.chestCm;
      if (profile.waistCm != null) body['waist_cm'] = profile.waistCm;
      if (profile.hipCm != null) body['hip_cm'] = profile.hipCm;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.cvAnalyzePath,
        data: body,
        options: Options(receiveTimeout: _timeout),
      );
      final result = CvAnalysisResult.fromJson(response.data ?? const {});
      debugPrint(
        '[CvAnalysis] shape=${result.bodyShape}, size=${result.estimatedSize}, '
        'skin=${result.skinTone?.toneLabel}, '
        'confidence=${(result.poseConfidence * 100).toStringAsFixed(1)}%',
      );
      return result;
    } on DioException catch (e) {
      final failure = Failure.fromDio(e);
      debugPrint('[CvAnalysis] ${failure.runtimeType}: ${failure.message}');
      return CvAnalysisResult(
        success: false,
        error: failure is NetworkFailure
            ? 'Could not reach the analysis server. Make sure the SmartFit API is running.'
            : failure.message,
      );
    }
  }
}
