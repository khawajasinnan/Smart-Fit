import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';

/// Hive box name for the wardrobe (local cache)
const _wardrobeBoxName = 'smartfit_wardrobe';

/// Wardrobe state: list of saved products backed by Supabase + Hive cache.
///
/// Supabase is the source of truth — products persist across restarts,
/// browsers, and devices. Hive provides instant local loading while the
/// remote fetch completes in the background.
class WardrobeNotifier extends StateNotifier<List<ProductRecommendation>> {
  Box<String>? _box;
  final SupabaseClient _client;
  final String _userId;

  WardrobeNotifier(this._client, this._userId) : super([]) {
    _init();
  }

  Future<void> _init() async {
    // 1. Open Hive box and load local cache instantly
    try {
      if (!Hive.isBoxOpen(_wardrobeBoxName)) {
        _box = await Hive.openBox<String>(_wardrobeBoxName);
      } else {
        _box = Hive.box<String>(_wardrobeBoxName);
      }
      _loadFromHive();
    } catch (e) {
      debugPrint('[Wardrobe] Failed to init Hive: $e');
    }

    // 2. Then load from Supabase (source of truth) and reconcile
    await _loadFromSupabase();
  }

  /// Load products from local Hive cache (instant, offline-capable).
  void _loadFromHive() {
    if (_box == null) return;
    try {
      final items = <ProductRecommendation>[];
      for (final key in _box!.keys) {
        try {
          final json = _box!.get(key);
          if (json != null) {
            final map = jsonDecode(json) as Map<String, dynamic>;
            items.add(ProductRecommendation.fromJson(map));
          }
        } catch (e) {
          debugPrint('[Wardrobe] Failed to parse item $key: $e');
        }
      }
      // Newest first
      state = items.reversed.toList();
    } catch (e) {
      debugPrint('[Wardrobe] Failed to load from Hive: $e');
    }
  }

  /// Load products from Supabase (persistent source of truth).
  Future<void> _loadFromSupabase() async {
    try {
      final data = await _client
          .from(ApiEndpoints.savedProductsTable)
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      final items = <ProductRecommendation>[];
      for (final row in data) {
        try {
          final productData = row['product_data'];
          final map = productData is String
              ? jsonDecode(productData) as Map<String, dynamic>
              : productData as Map<String, dynamic>;
          items.add(ProductRecommendation.fromJson(map));
        } catch (e) {
          debugPrint('[Wardrobe] Failed to parse remote item: $e');
        }
      }

      // Update state with Supabase data (authoritative)
      state = items;

      // Sync Hive cache to match Supabase
      await _syncHiveCache(items);
    } catch (e) {
      debugPrint('[Wardrobe] Failed to load from Supabase: $e');
      // Keep Hive data as fallback — user still sees their local cache
    }
  }

  /// Sync Hive cache to match the Supabase data.
  Future<void> _syncHiveCache(List<ProductRecommendation> items) async {
    if (_box == null) return;
    try {
      await _box!.clear();
      for (final product in items) {
        final key = product.id.isNotEmpty ? product.id : product.productUrl;
        await _box!.put(key, jsonEncode(product.toJson()));
      }
    } catch (e) {
      debugPrint('[Wardrobe] Failed to sync Hive cache: $e');
    }
  }

  /// Save a product to the wardrobe (both Supabase + Hive).
  Future<void> saveProduct(ProductRecommendation product) async {
    final key = product.id.isNotEmpty ? product.id : product.productUrl;

    // Optimistically update UI
    state = [product, ...state.where((p) => _productKey(p) != key)];

    // Save to Hive cache
    try {
      await _box?.put(key, jsonEncode(product.toJson()));
    } catch (e) {
      debugPrint('[Wardrobe] Failed to save to Hive: $e');
    }

    // Save to Supabase (persistent)
    try {
      // Check if already exists to avoid duplicates
      final existing = await _client
          .from(ApiEndpoints.savedProductsTable)
          .select('id')
          .eq('user_id', _userId)
          .eq('product_data->>product_url', product.productUrl)
          .maybeSingle();

      if (existing == null) {
        await _client.from(ApiEndpoints.savedProductsTable).insert({
          'user_id': _userId,
          'product_data': product.toJson(),
        });
      }
    } catch (e) {
      debugPrint('[Wardrobe] Failed to save to Supabase: $e');
    }
  }

  /// Remove a product from the wardrobe (both Supabase + Hive).
  Future<void> removeProduct(String productId) async {
    // Find the product before removing (need productUrl for Supabase lookup)
    final product = state.where((p) => _productKey(p) == productId).firstOrNull;
    final productUrl = product?.productUrl;

    // Optimistically update UI
    state = state.where((p) => _productKey(p) != productId).toList();

    // Remove from Hive
    try {
      await _box?.delete(productId);
    } catch (e) {
      debugPrint('[Wardrobe] Failed to remove from Hive: $e');
    }

    // Remove from Supabase
    try {
      if (productUrl != null && productUrl.isNotEmpty) {
        await _client
            .from(ApiEndpoints.savedProductsTable)
            .delete()
            .eq('user_id', _userId)
            .eq('product_data->>product_url', productUrl);
      }
    } catch (e) {
      debugPrint('[Wardrobe] Failed to remove from Supabase: $e');
    }
  }

  /// Check if a product is saved.
  bool isProductSaved(String productId) {
    return state.any((p) => _productKey(p) == productId);
  }

  /// Clear all saved products (both Supabase + Hive).
  Future<void> clearAll() async {
    state = [];

    try {
      await _box?.clear();
    } catch (e) {
      debugPrint('[Wardrobe] Failed to clear Hive: $e');
    }

    try {
      await _client
          .from(ApiEndpoints.savedProductsTable)
          .delete()
          .eq('user_id', _userId);
    } catch (e) {
      debugPrint('[Wardrobe] Failed to clear Supabase: $e');
    }
  }

  /// Unique key for a product.
  String _productKey(ProductRecommendation p) =>
      p.id.isNotEmpty ? p.id : p.productUrl;
}

/// Riverpod provider for wardrobe — requires authenticated user ID.
final wardrobeNotifierProvider =
    StateNotifierProvider<WardrobeNotifier, List<ProductRecommendation>>(
  (ref) {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? '';
    return WardrobeNotifier(client, userId);
  },
);
