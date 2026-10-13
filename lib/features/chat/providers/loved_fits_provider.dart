import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';

/// Provider for user loved fits feedback learning system.
final lovedFitsProvider =
    StateNotifierProvider<LovedFitsNotifier, Set<String>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  return LovedFitsNotifier(client, user?.id ?? 'guest')..init();
});

/// Manages fits loved by the user from AI chat product recommendations,
/// persisting to Hive & Supabase, and extracting learned feedback signals.
class LovedFitsNotifier extends StateNotifier<Set<String>> {
  final SupabaseClient _client;
  final String _userId;
  Box<String>? _box;
  final Map<String, ProductRecommendation> _lovedProductsMap = {};

  LovedFitsNotifier(this._client, this._userId) : super({});

  static const String _boxName = 'smartfit_loved_fits_box';

  Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox<String>(_boxName);
      } else {
        _box = Hive.box<String>(_boxName);
      }

      final localKeys = _box?.keys.cast<String>().toSet() ?? {};
      for (final key in localKeys) {
        final raw = _box?.get(key);
        if (raw != null) {
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            _lovedProductsMap[key] = ProductRecommendation.fromJson(json);
          } catch (_) {}
        }
      }

      state = {...localKeys};

      // Also sync from Supabase if logged in
      if (_userId != 'guest') {
        _syncFromSupabase();
      }
    } catch (e) {
      debugPrint('[LovedFits] Init error: ');
    }
  }

  Future<void> _syncFromSupabase() async {
    try {
      final rows = await _client
          .from(ApiEndpoints.userFeedbackTable)
          .select('product_id, feedback_data')
          .eq('user_id', _userId)
          .eq('feedback_type', 'loved_fit');

      final remoteKeys = <String>{};
      for (final row in rows) {
        final pId = row['product_id'] as String?;
        if (pId != null && pId.isNotEmpty) {
          remoteKeys.add(pId);
          if (row['feedback_data'] != null && !_lovedProductsMap.containsKey(pId)) {
            try {
              final json = row['feedback_data'] as Map<String, dynamic>;
              _lovedProductsMap[pId] = ProductRecommendation.fromJson(json);
              await _box?.put(pId, jsonEncode(json));
            } catch (_) {}
          }
        }
      }

      state = {...state, ...remoteKeys};
    } catch (e) {
      debugPrint('[LovedFits] Supabase sync error: ');
    }
  }

  bool isLoved(String productId, [String? productUrl]) {
    final key = productId.isNotEmpty ? productId : (productUrl ?? '');
    return state.contains(key);
  }

  /// Toggle Love Fit status for a product recommendation.
  Future<bool> toggleLoveFit(ProductRecommendation product) async {
    final key = product.id.isNotEmpty ? product.id : product.productUrl;
    final currentlyLoved = state.contains(key);

    if (currentlyLoved) {
      // Remove
      state = state.where((k) => k != key).toSet();
      _lovedProductsMap.remove(key);
      await _box?.delete(key);

      if (_userId != 'guest') {
        try {
          await _client
              .from(ApiEndpoints.userFeedbackTable)
              .delete()
              .eq('user_id', _userId)
              .eq('product_id', key)
              .eq('feedback_type', 'loved_fit');
        } catch (_) {}
      }
      return false;
    } else {
      // Add
      state = {...state, key};
      _lovedProductsMap[key] = product;
      await _box?.put(key, jsonEncode(product.toJson()));

      if (_userId != 'guest') {
        try {
          await _client.from(ApiEndpoints.userFeedbackTable).upsert({
            'user_id': _userId,
            'product_id': key,
            'feedback_type': 'loved_fit',
            'feedback_data': product.toJson(),
            'created_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id, product_id');
        } catch (_) {}
      }
      return true;
    }
  }

  /// Extracts learned style preferences based on all loved fits.
  /// Used to enrich the recommendation system and AI Stylist prompts.
  Map<String, dynamic> getLearnedFeedbackSignals() {
    final loved = _lovedProductsMap.values.toList();
    if (loved.isEmpty) return {};

    final categoryFreq = <String, int>{};
    final brandFreq = <String, int>{};
    final colorFreq = <String, int>{};
    final tagFreq = <String, int>{};
    final prices = <int>[];

    for (final p in loved) {
      if (p.category != null && p.category!.isNotEmpty) {
        categoryFreq[p.category!] = (categoryFreq[p.category!] ?? 0) + 1;
      }
      if (p.brand.isNotEmpty) {
        brandFreq[p.brand] = (brandFreq[p.brand] ?? 0) + 1;
      }
      for (final c in p.colors) {
        if (c.trim().isNotEmpty) {
          colorFreq[c.trim()] = (colorFreq[c.trim()] ?? 0) + 1;
        }
      }
      for (final t in p.tags) {
        if (t.trim().isNotEmpty) {
          tagFreq[t.trim()] = (tagFreq[t.trim()] ?? 0) + 1;
        }
      }
      if (p.pricePkr != null && p.pricePkr! > 0) {
        prices.add(p.pricePkr!);
      }
    }

    // Sort by frequency
    final topCategories = categoryFreq.keys.toList()
      ..sort((a, b) => categoryFreq[b]!.compareTo(categoryFreq[a]!));
    final topBrands = brandFreq.keys.toList()
      ..sort((a, b) => brandFreq[b]!.compareTo(brandFreq[a]!));
    final topColors = colorFreq.keys.toList()
      ..sort((a, b) => colorFreq[b]!.compareTo(colorFreq[a]!));
    final topTags = tagFreq.keys.toList()
      ..sort((a, b) => tagFreq[b]!.compareTo(tagFreq[a]!));

    int? avgPrice;
    if (prices.isNotEmpty) {
      avgPrice = (prices.reduce((a, b) => a + b) / prices.length).round();
    }

    return {
      'loved_count': loved.length,
      'favorite_categories': topCategories.take(4).toList(),
      'favorite_brands': topBrands.take(4).toList(),
      'favorite_colors': topColors.take(4).toList(),
      'favorite_styles': topTags.take(6).toList(),
      if (avgPrice != null) 'preferred_price_point': avgPrice,
      'recent_loved_titles': loved.take(3).map((p) => p.title).toList(),
    };
  }

  /// Generates a natural language string to inform Gemini of the user's learned preferences.
  String getLearnedPreferencesContext() {
    final signals = getLearnedFeedbackSignals();
    if (signals.isEmpty) return '';

    final brands = (signals['favorite_brands'] as List<String>?)?.join(', ');
    final categories = (signals['favorite_categories'] as List<String>?)?.join(', ');
    final colors = (signals['favorite_colors'] as List<String>?)?.join(', ');
    final titles = (signals['recent_loved_titles'] as List<String>?)?.join(', ');

    final buffer = StringBuffer();
    buffer.writeln('User Learned Fashion Feedback (from Loved Fits):');
    if (categories != null && categories.isNotEmpty) {
      buffer.writeln('- Preferred Garment Types: ');
    }
    if (brands != null && brands.isNotEmpty) {
      buffer.writeln('- Preferred Brands: ');
    }
    if (colors != null && colors.isNotEmpty) {
      buffer.writeln('- Preferred Colors: ');
    }
    if (titles != null && titles.isNotEmpty) {
      buffer.writeln('- Specific Items User Loved: "');
 }
 buffer.writeln('Prioritize recommendations matching these styles and aesthetics when suitable.');

 return buffer.toString().trim();
 }
}
