import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// "Love Fit" feedback for the signed-in user (SFR-034 preference signals).
/// Rebuilt when the user changes so accounts never share loved fits.
final lovedFitsProvider = StateNotifierProvider<LovedFitsNotifier, Set<String>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  return LovedFitsNotifier(client, userId);
});

/// Builds the learned-preferences text sent to the AI stylist.
@visibleForTesting
String learnedPreferencesText(Map<String, dynamic> signals) {
  if (signals.isEmpty) return '';
  String? joined(String key) {
    final values = (signals[key] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    return values == null || values.isEmpty ? null : values.join(', ');
  }

  final categories = joined('favorite_categories');
  final brands = joined('favorite_brands');
  final colors = joined('favorite_colors');
  final titles = joined('recent_loved_titles');

  final buffer = StringBuffer()..writeln('User Learned Fashion Feedback (from Loved Fits):');
  if (categories != null) buffer.writeln('- Preferred Garment Types: $categories');
  if (brands != null) buffer.writeln('- Preferred Brands: $brands');
  if (colors != null) buffer.writeln('- Preferred Colors: $colors');
  if (titles != null) buffer.writeln('- Specific Items User Loved: "$titles"');
  buffer.writeln('Prioritize recommendations matching these styles and aesthetics when suitable.');
  return buffer.toString().trim();
}

/// Manages fits the user loved in AI stylist recommendations: Hive cache +
/// Supabase `user_feedback`, and the learned style signals derived from them.
class LovedFitsNotifier extends StateNotifier<Set<String>> {
  LovedFitsNotifier(this._client, this._userId) : super(const {}) {
    if (_userId != null) _init();
  }

  final SupabaseClient _client;

  /// Null when signed out.
  final String? _userId;
  Box<String>? _box;
  final Map<String, ProductRecommendation> _lovedProductsMap = {};

  static const String _legacySharedBoxName = 'smartfit_loved_fits_box';
  static const String _feedbackType = 'loved_fit';

  String get _boxName => 'smartfit_loved_fits_$_userId';

  void _setState(Set<String> keys) {
    if (mounted) state = keys;
  }

  Future<void> _init() async {
    try {
      _box = Hive.isBoxOpen(_boxName) ? Hive.box<String>(_boxName) : await Hive.openBox<String>(_boxName);
      await _adoptLegacySharedBox();
      for (final key in _box!.keys.cast<String>()) {
        final raw = _box!.get(key);
        if (raw == null) continue;
        try {
          _lovedProductsMap[key] = ProductRecommendation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          // Skip unreadable cache entries.
        }
      }
      _setState({..._lovedProductsMap.keys});
    } catch (e) {
      debugPrint('[LovedFits] Init error: $e');
    }
    await _syncFromSupabase();
  }

  /// Older versions kept one shared box for every account on the device and
  /// never reached the server (the user_feedback table was missing). Move
  /// those loves to the first account that signs in after the update, upload
  /// them, then delete the shared box.
  Future<void> _adoptLegacySharedBox() async {
    if (!await Hive.boxExists(_legacySharedBoxName)) return;
    try {
      final legacy = await Hive.openBox<String>(_legacySharedBoxName);
      for (final key in legacy.keys.cast<String>()) {
        final raw = legacy.get(key);
        if (raw == null || _box!.containsKey(key)) continue;
        await _box!.put(key, raw);
        try {
          await _upsertRemote(key, jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
      await legacy.deleteFromDisk();
    } catch (e) {
      debugPrint('[LovedFits] Legacy cache migration failed: $e');
    }
  }

  Future<void> _upsertRemote(String key, Map<String, dynamic> productJson, {String source = 'app'}) {
    return _client.from(ApiEndpoints.userFeedbackTable).upsert({
      'user_id': _userId,
      'product_id': key,
      'feedback_type': _feedbackType,
      'feedback_data': {...productJson, 'source': source},
    }, onConflict: 'user_id,product_id,feedback_type');
  }

  Future<void> _syncFromSupabase() async {
    try {
      final rows = await _client
          .from(ApiEndpoints.userFeedbackTable)
          .select('product_id, feedback_data')
          .eq('user_id', _userId!)
          .eq('feedback_type', _feedbackType);

      final remoteKeys = <String>{};
      for (final row in rows) {
        final key = row['product_id'] as String?;
        if (key == null || key.isEmpty) continue;
        remoteKeys.add(key);
        final data = row['feedback_data'];
        if (data is Map && !_lovedProductsMap.containsKey(key)) {
          try {
            final json = Map<String, dynamic>.from(data);
            _lovedProductsMap[key] = ProductRecommendation.fromJson(json);
            await _box?.put(key, jsonEncode(json));
          } catch (_) {}
        }
      }
      _setState({...state, ...remoteKeys});
    } catch (e) {
      // Offline, or the user_feedback migration isn't applied yet.
      debugPrint('[LovedFits] Supabase sync error: $e');
    }
  }

  bool isLoved(ProductRecommendation product) => state.contains(product.key);

  /// Loved products (for the taste profile, spec §23.15).
  List<ProductRecommendation> get lovedProducts => _lovedProductsMap.values.toList();

  /// Toggle Love Fit for a product. Returns true if it is now loved.
  Future<bool> toggleLoveFit(ProductRecommendation product) async {
    final loved = !state.contains(product.key);
    await setLoved(product, loved);
    return loved;
  }

  /// Love (or un-love) a product; [source] is 'app' or 'notification'.
  Future<void> setLoved(ProductRecommendation product, bool loved, {String source = 'app'}) async {
    final key = product.key;
    if (loved == state.contains(key)) return;
    if (!loved) {
      _setState(state.where((k) => k != key).toSet());
      _lovedProductsMap.remove(key);
      await _box?.delete(key);
      if (_userId != null) {
        try {
          await _client
              .from(ApiEndpoints.userFeedbackTable)
              .delete()
              .eq('user_id', _userId)
              .eq('product_id', key)
              .eq('feedback_type', _feedbackType);
        } catch (e) {
          debugPrint('[LovedFits] Remote delete failed: $e');
        }
      }
      return;
    }

    _setState({...state, key});
    _lovedProductsMap[key] = product;
    await _box?.put(key, jsonEncode(product.toJson()));
    if (_userId != null) {
      try {
        await _upsertRemote(key, product.toJson(), source: source);
      } catch (e) {
        debugPrint('[LovedFits] Remote save failed: $e');
      }
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

  /// Natural-language summary of learned preferences for the AI stylist.
  String getLearnedPreferencesContext() => learnedPreferencesText(getLearnedFeedbackSignals());
}
