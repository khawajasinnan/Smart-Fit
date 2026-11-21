import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

final scraperApiServiceProvider = Provider<ScraperApiService>(
  (ref) => ScraperApiService(ref.watch(apiDioProvider)),
);

/// Service that calls the FastAPI backend to scrape Pakistani retailers
/// and return ranked product recommendations based on user profile + chat context.
class ScraperApiService {
  ScraperApiService(this._dio);

  final Dio _dio;

  // Live scraping of many retailers can take a while (SRDS §4.1: <= 15 s
  // target, generous ceiling for slow networks).
  static const Duration _timeout = Duration(seconds: 90);

  /// Search for product recommendations based on user profile and chat context.
  ///
  /// [profile] — The user's static profile (measurements, skin tone, gender, etc.)
  /// [userMessage] — The latest user message in the chat
  /// [assistantMessage] — The AI's latest response (for context extraction)
  /// [chatContext] — Additional context from the chat history
  /// [dynamicPrefs] — Dynamic preferences extracted by AI (occasion, colors, etc.)
  /// [taste] — what the user's feedback taught us (loves, "not for me",
  ///   quiz answers; spec §23.15). Soft re-ranking on the backend, except
  ///   rejected products, which are never shown again.
  /// [maxProducts] — Maximum number of products to return
  Future<ScrapeRecommendResponse> searchProducts({
    required UserProfileModel profile,
    String userMessage = '',
    String assistantMessage = '',
    String chatContext = '',
    Map<String, dynamic>? dynamicPrefs,
    Map<String, dynamic>? taste,
    int maxProducts = 12,
  }) async {
    final budgetMin = _positiveBudgetOrNull(dynamicPrefs?['budget_min']);
    final budgetMax = _positiveBudgetOrNull(dynamicPrefs?['budget_max']);
    if (dynamicPrefs?['budget_min'] != null && budgetMin == null ||
        dynamicPrefs?['budget_max'] != null && budgetMax == null) {
      return const ScrapeRecommendResponse(
        products: [],
        searchQuery: '',
        brandsSearched: [],
        message:
            'Budget cannot be a negative amount. Please enter a positive PKR budget, for example 5000 PKR.',
      );
    }

    // Build the profile input matching backend's UserProfileInput schema
    final profilePayload = {
      'gender': profile.gender,
      'height_cm': profile.heightCm,
      'weight_kg': profile.weightKg,
      'chest_cm': profile.chestCm,
      'waist_cm': profile.waistCm,
      'hip_cm': profile.hipCm,
      'body_type': profile.bodyType,
      'skin_tone': profile.skinTone,
      'style_preferences': profile.stylePreferences,
      'preferred_colors': [
        ...profile.preferredColors,
        // Merge dynamic color preferences from AI
        ...?dynamicPrefs?['colors']?.cast<String>(),
      ],
      'budget_min': budgetMin ?? profile.budgetMin,
      'budget_max': budgetMax ?? profile.budgetMax,
      'occasions': [
        ...profile.occasions,
        if (dynamicPrefs?['occasion'] != null)
          dynamicPrefs!['occasion'] as String,
      ],
      'ethnicity': profile.ethnicity,
      'skin_undertone': profile.skinUndertone,
      'usual_size': profile.usualSize,
    };

    // Combine the user message with what the AI picked up. Learned taste goes
    // in `taste`, never in the text: brand names here would be read as a
    // request for ONLY those brands.
    final enrichedMessage = [
      userMessage,
      if (dynamicPrefs?['garment'] != null)
        'Looking for: ${dynamicPrefs!['garment']}',
      if (dynamicPrefs?['colors'] != null &&
          (dynamicPrefs!['colors'] as List).isNotEmpty)
        'Requested colors: ${(dynamicPrefs['colors'] as List).join(", ")}',
      if (dynamicPrefs?['size'] != null)
        'Requested size: ${dynamicPrefs!['size']}',
      if (dynamicPrefs?['style_notes'] != null)
        dynamicPrefs!['style_notes'] as String,
      if (profile.ethnicity != null && profile.ethnicity!.isNotEmpty)
        'Cultural style: ${profile.ethnicity}',
    ].where((s) => s.isNotEmpty).join('. ');

    final body = {
      'profile': profilePayload,
      'user_message': enrichedMessage,
      'assistant_message': assistantMessage,
      'chat_context': chatContext,
      'dynamic_prefs': dynamicPrefs ?? {},
      'max_products': maxProducts,
      'taste': ?taste,
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.scrapeRecommendPath,
        data: body,
        options: Options(receiveTimeout: _timeout),
      );
      final result = ScrapeRecommendResponse.fromJson(response.data ?? const {});
      debugPrint(
        '[ScraperAPI] ${result.products.length} products from ${result.brandsSearched.join(", ")}',
      );
      return result;
    } on DioException catch (e) {
      final failure = Failure.fromDio(e);
      debugPrint('[ScraperAPI] ${failure.runtimeType}: ${failure.message}');
      return ScrapeRecommendResponse(
        products: const [],
        searchQuery: '',
        brandsSearched: const [],
        message: switch (failure) {
          NetworkFailure() => 'Backend is not reachable. Make sure the SmartFit API is running.',
          RateLimitedFailure() || UnauthorizedFailure() => failure.message,
          _ => 'Could not fetch recommendations right now. Please try again.',
        },
      );
    }
  }

  int? _positiveBudgetOrNull(dynamic value) {
    if (value == null) return null;
    final parsed = value is int
        ? value
        : int.tryParse(value.toString().replaceAll(',', '').trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
}
