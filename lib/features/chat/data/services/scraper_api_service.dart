import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

/// Service that calls the FastAPI backend to scrape Pakistani retailers
/// and return ranked product recommendations based on user profile + chat context.
class ScraperApiService {
  static const Duration _timeout = Duration(seconds: 60);

  /// Search for product recommendations based on user profile and chat context.
  ///
  /// [profile] — The user's static profile (measurements, skin tone, gender, etc.)
  /// [userMessage] — The latest user message in the chat
  /// [assistantMessage] — The AI's latest response (for context extraction)
  /// [chatContext] — Additional context from the chat history
  /// [dynamicPrefs] — Dynamic preferences extracted by AI (occasion, colors, etc.)
  /// [maxProducts] — Maximum number of products to return
  Future<ScrapeRecommendResponse> searchProducts({
    required UserProfileModel profile,
    String userMessage = '',
    String assistantMessage = '',
    String chatContext = '',
    Map<String, dynamic>? dynamicPrefs,
    Map<String, dynamic>? learnedFeedback,
    int maxProducts = 12,
  }) async {
    final url = Uri.parse(ApiEndpoints.scrapeRecommendEndpoint);
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

    // Extract learned feedback from Loved Fits
    final lovedCategories = (learnedFeedback?['favorite_categories'] as List<dynamic>?)?.cast<String>() ?? [];
    final lovedBrands = (learnedFeedback?['favorite_brands'] as List<dynamic>?)?.cast<String>() ?? [];
    final lovedColors = (learnedFeedback?['favorite_colors'] as List<dynamic>?)?.cast<String>() ?? [];

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
      'style_preferences': [
        ...profile.stylePreferences,
        ...lovedCategories,
      ],
      'preferred_colors': [
        ...profile.preferredColors,
        // Merge dynamic color preferences from AI
        ...?dynamicPrefs?['colors']?.cast<String>(),
        ...lovedColors,
      ],
      'budget_min': budgetMin ?? profile.budgetMin,
      'budget_max': budgetMax ?? profile.budgetMax,
      'occasions': [
        ...profile.occasions,
        if (dynamicPrefs?['occasion'] != null)
          dynamicPrefs!['occasion'] as String,
      ],
      'ethnicity': profile.ethnicity,
    };

    // Combine user message with any dynamic context from AI analysis and loved fits feedback
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
      if (lovedBrands.isNotEmpty)
        'User loved brands: ${lovedBrands.join(", ")}',
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
    };

    debugPrint('[ScraperAPI] POST $url');
    debugPrint('[ScraperAPI] Body: ${jsonEncode(body).substring(0, 200)}...');

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
        final result = ScrapeRecommendResponse.fromJson(data);
        debugPrint(
          '[ScraperAPI] Success: ${result.products.length} products from ${result.brandsSearched.join(", ")}',
        );
        return result;
      } else {
        debugPrint(
          '[ScraperAPI] Error ${response.statusCode}: ${response.body}',
        );
        return ScrapeRecommendResponse(
          products: [],
          searchQuery: '',
          brandsSearched: [],
          message:
              'Could not fetch recommendations right now. Please try again.',
        );
      }
    } catch (e) {
      debugPrint('[ScraperAPI] Network error: $e');
      return ScrapeRecommendResponse(
        products: [],
        searchQuery: '',
        brandsSearched: [],
        message:
            'Backend is not reachable. Make sure the SmartFit API is running.',
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
