import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

/// Service that calls the FastAPI backend to analyze a user's photo
/// for body detection, pose estimation, body shape, size, and skin tone.
///
/// SRDS refs: SFR-019 (body shape), SFR-020 (size estimation)
class CvAnalysisApiService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Analyze a user photo for body shape, size estimation, and skin tone.
  ///
  /// [imageUrl] — URL of the user's profile photo (from Supabase Storage)
  /// [profile] — Optional user profile for measurement-enhanced accuracy
  Future<CvAnalysisResult> analyzeBody({
    String? imageUrl,
    String? imageBase64,
    String? gender,
    double? heightCm,
    double? weightKg,
    UserProfileModel? profile,
  }) async {
    final url = Uri.parse(ApiEndpoints.cvAnalyzeEndpoint);

    final body = <String, dynamic>{
      if (imageUrl != null) 'image_url': imageUrl,
      if (imageBase64 != null) 'image_base64': imageBase64,
      if (gender != null) 'gender': gender,
      if (heightCm != null) 'height_cm': heightCm,
      if (weightKg != null) 'weight_kg': weightKg,
    };

    // Pass profile measurements if available — improves size accuracy
    if (profile != null) {
      if (profile.gender != null) body['gender'] = profile.gender;
      if (profile.heightCm != null) body['height_cm'] = profile.heightCm;
      if (profile.weightKg != null) body['weight_kg'] = profile.weightKg;
      if (profile.chestCm != null) body['chest_cm'] = profile.chestCm;
      if (profile.waistCm != null) body['waist_cm'] = profile.waistCm;
      if (profile.hipCm != null) body['hip_cm'] = profile.hipCm;
    }

    debugPrint('[CvAnalysis] POST $url');
    debugPrint('[CvAnalysis] Body: ${jsonEncode(body)}');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final result = CvAnalysisResult.fromJson(data);
        debugPrint(
          '[CvAnalysis] Success: shape=${result.bodyShape}, '
          'size=${result.estimatedSize}, '
          'skin=${result.skinTone?.toneLabel}, '
          'confidence=${(result.poseConfidence * 100).toStringAsFixed(1)}%',
        );
        return result;
      } else {
        debugPrint(
          '[CvAnalysis] Error ${response.statusCode}: ${response.body}',
        );
        return CvAnalysisResult(
          success: false,
          error:
              'Body analysis failed (${response.statusCode}). Please try again.',
        );
      }
    } catch (e) {
      debugPrint('[CvAnalysis] Network error: $e');
      return CvAnalysisResult(
        success: false,
        error:
            'Could not reach the analysis server. Make sure the SmartFit API is running.',
      );
    }
  }
}
