import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/utils/hive_boxes.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/wardrobe/data/models/saved_product.dart';

/// Per-user local cache. The old shared box mixed accounts on one device.
String _boxNameFor(String userId) => 'smartfit_wardrobe_$userId';
const _legacySharedBoxName = 'smartfit_wardrobe';

/// Wardrobe state: saved products (newest first) for the signed-in user,
/// backed by Supabase (source of truth) with a Hive cache for instant loading.
/// SFR-035 (save), SFR-036 (browse by date), SFR-037 (retailer redirect).
class WardrobeNotifier extends StateNotifier<List<SavedProduct>> {
  WardrobeNotifier(this._client, this._userId) : super(const []) {
    if (_userId != null) _init();
  }

  final SupabaseClient _client;

  /// Null when signed out — then nothing is read or written anywhere.
  final String? _userId;
  Box<String>? _box;

  Future<void> _init() async {
    try {
      final name = _boxNameFor(_userId!);
      _box = Hive.isBoxOpen(name) ? Hive.box<String>(name) : await Hive.openBox<String>(name);
      _loadFromHive();
      // The old shared cache only mirrored Supabase data; drop it.
      if (await Hive.boxExists(_legacySharedBoxName)) {
        await deleteLocalBox(_legacySharedBoxName); // never blocks the load below (web: see hive_boxes.dart)
      }
    } catch (e) {
      debugPrint('[Wardrobe] Hive init failed: $e');
    }
    await _loadFromSupabase();
  }

  void _setState(List<SavedProduct> items) {
    if (mounted) state = items;
  }

  void _loadFromHive() {
    final box = _box;
    if (box == null) return;
    final items = <SavedProduct>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw != null) items.add(SavedProduct.fromCacheJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[Wardrobe] Skipping unreadable cache item $key: $e');
      }
    }
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    _setState(items);
  }

  Future<void> _loadFromSupabase() async {
    try {
      final rows = await _client
          .from(ApiEndpoints.savedProductsTable)
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);

      final items = <SavedProduct>[];
      for (final row in rows) {
        try {
          final data = row['product_data'];
          final map = data is String ? jsonDecode(data) as Map<String, dynamic> : Map<String, dynamic>.from(data as Map);
          items.add(SavedProduct(
            product: ProductRecommendation.fromJson(map),
            savedAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          ));
        } catch (e) {
          debugPrint('[Wardrobe] Skipping unreadable saved item: $e');
        }
      }
      _setState(items);
      await _syncHiveCache(items);
    } catch (e) {
      // Offline or server error: keep showing the local cache.
      debugPrint('[Wardrobe] Supabase load failed: $e');
    }
  }

  Future<void> _syncHiveCache(List<SavedProduct> items) async {
    final box = _box;
    if (box == null) return;
    try {
      await box.clear();
      for (final item in items) {
        await box.put(item.key, jsonEncode(item.toCacheJson()));
      }
    } catch (e) {
      debugPrint('[Wardrobe] Cache sync failed: $e');
    }
  }

  /// Save a product (optimistic UI, then Hive + Supabase). [savedAt] keeps
  /// the original date when an item is restored with "Undo".
  Future<void> saveProduct(ProductRecommendation product, {DateTime? savedAt}) async {
    if (_userId == null) return;
    final item = SavedProduct(product: product, savedAt: savedAt ?? DateTime.now());
    _setState([item, ...state.where((p) => p.key != item.key)]
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt)));

    try {
      await _box?.put(item.key, jsonEncode(item.toCacheJson()));
    } catch (e) {
      debugPrint('[Wardrobe] Cache save failed: $e');
    }

    try {
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
          if (savedAt != null) 'created_at': savedAt.toUtc().toIso8601String(),
        });
      } else if (product.hasTryOn || product.hasHairstyle) {
        // Already saved: attach the new try-on / hairstyle to the existing row (SFR-035).
        await _client
            .from(ApiEndpoints.savedProductsTable)
            .update({'product_data': product.toJson()})
            .eq('id', existing['id'] as Object);
      }
    } catch (e) {
      debugPrint('[Wardrobe] Supabase save failed: $e');
    }
  }

  /// Remove a product by its [ProductRecommendation.key].
  Future<void> removeProduct(String key) async {
    if (_userId == null) return;
    final removed = state.where((p) => p.key == key).firstOrNull;
    _setState(state.where((p) => p.key != key).toList());

    try {
      await _box?.delete(key);
    } catch (e) {
      debugPrint('[Wardrobe] Cache remove failed: $e');
    }

    final productUrl = removed?.product.productUrl;
    if (productUrl == null || productUrl.isEmpty) return;
    try {
      await _client
          .from(ApiEndpoints.savedProductsTable)
          .delete()
          .eq('user_id', _userId)
          .eq('product_data->>product_url', productUrl);
    } catch (e) {
      debugPrint('[Wardrobe] Supabase remove failed: $e');
    }
  }

  /// Put back an item that was just removed (snackbar "Undo").
  Future<void> restore(SavedProduct item) => saveProduct(item.product, savedAt: item.savedAt);

  bool isProductSaved(String key) => state.any((p) => p.key == key);

  /// Keep [hairstyle] (`ChosenHairstyle.toWardrobeJson()`) with the saved item [key]
  /// (SFR-035), keeping its try-on and place in the list. False if it isn't saved.
  Future<bool> attachHairstyle(String key, Map<String, dynamic> hairstyle) async {
    final item = state.where((p) => p.key == key).firstOrNull;
    if (item == null) return false;
    await saveProduct(item.product.withHairstyle(hairstyle), savedAt: item.savedAt);
    return true;
  }

  /// Clear all saved products (Supabase + cache).
  Future<void> clearAll() async {
    if (_userId == null) return;
    _setState(const []);
    try {
      await _box?.clear();
    } catch (e) {
      debugPrint('[Wardrobe] Cache clear failed: $e');
    }
    try {
      await _client.from(ApiEndpoints.savedProductsTable).delete().eq('user_id', _userId);
    } catch (e) {
      debugPrint('[Wardrobe] Supabase clear failed: $e');
    }
  }
}

/// Rebuilt whenever the signed-in user changes, so one account never sees
/// another account's wardrobe.
final wardrobeNotifierProvider = StateNotifierProvider<WardrobeNotifier, List<SavedProduct>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  return WardrobeNotifier(client, userId);
});
