import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/scoring/data/look_score_models.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

final lookScoreApiServiceProvider = Provider<LookScoreApiService>(
  (ref) => LookScoreApiService(ref.watch(apiDioProvider)),
);

/// The gateway's look score routes (SFR-032..034): POST /score and POST /feedback.
class LookScoreApiService {
  LookScoreApiService(this._dio);

  final Dio _dio;

  Future<LookScoreResult> score({
    required LookScoreArgs look,
    UserProfileModel? profile,
    ChosenHairstyle? hairstyle,
    String? occasion,
  }) async {
    final p = look.product;
    final fit = look.fit;
    final body = {
      'product': {
        'id': p.key,
        'title': p.title,
        'brand': p.brand,
        'category': ?p.category,
        'colors': p.colors,
        'tags': p.tags,
        'price_pkr': ?p.pricePkr,
      },
      'profile': {
        'gender': ?profile?.gender,
        'skin_tone': ?profile?.skinTone,
        'skin_undertone': ?profile?.skinUndertone,
        'body_type': ?profile?.bodyType,
        'style_preferences': profile?.stylePreferences ?? const <String>[],
        'preferred_colors': profile?.preferredColors ?? const <String>[],
      },
      'occasion': ?occasion,
      'fit_status': switch (fit?.status) {
        TryOnFitStatus.fits => 'fits',
        TryOnFitStatus.small => 'small',
        TryOnFitStatus.big => 'big',
        _ => 'unknown',
      },
      'fit_size': ?fit?.size,
      'hairstyle': ?hairstyle?.toJson(),
    };
    try {
      final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.lookScorePath, data: body);
      return LookScoreResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// The user's 1..5 rating of a scored look (SFR-034), with what they were shown.
  Future<void> rate({
    required String productId,
    required int rating,
    required LookScoreResult result,
    String? occasion,
    List<String> corrections = const [],
    String? comment,
  }) async {
    final note = comment?.trim();
    try {
      await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.lookFeedbackPath,
        data: {
          'product_id': productId,
          'rating': rating,
          'score': result.score,
          'model_features': result.modelFeatures,
          'occasion': ?occasion,
          // SFR-034: what the user says is off, and their own words
          if (corrections.isNotEmpty) 'corrections': corrections,
          if (note != null && note.isNotEmpty) 'comment': note,
        },
      );
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}
