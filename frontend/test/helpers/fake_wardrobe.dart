import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/wardrobe/data/models/saved_product.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory wardrobe for widget tests (no Hive, no Supabase).
class FakeWardrobe extends WardrobeNotifier {
  FakeWardrobe(List<SavedProduct> items) : super(SupabaseClient('http://localhost:1', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false)), null) {
    state = items;
  }

  final removed = <String>[];

  @override
  Future<void> removeProduct(String key) async {
    removed.add(key);
    state = state.where((p) => p.key != key).toList();
  }

  @override
  Future<void> restore(SavedProduct item) async {
    state = [item, ...state]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  @override
  Future<void> clearAll() async => state = const [];
}

/// Saved items for wardrobe tests / screenshots. Photo URLs carry
/// Unsplash-style ids so the screenshot harness can map them to local files.
List<SavedProduct> sampleWardrobe(DateTime now) {
  ProductRecommendation p(String id, String brand, String title, String category, int price, int photo) =>
      ProductRecommendation(
        id: id,
        brand: brand,
        title: title,
        category: category,
        pricePkr: price,
        imageUrl: 'https://cdn.shopify.com/s/files/photo-${1000 + photo}-${2000 + photo}.jpg',
        productUrl: 'https://store.pk/products/$id',
        sizes: const ['S', 'M', 'L'],
      );
  return [
    SavedProduct(product: p('j1', 'Breakout', 'Jacquard Jacket', 'jackets', 4749, 0), savedAt: now),
    SavedProduct(
        product: p('c1', 'Breakout', 'Baggy Fit Cargo Trouser', 'cargo-pants', 2999, 1),
        savedAt: now.subtract(const Duration(hours: 3))),
    SavedProduct(
        product: p('s1', 'Outfitters', 'Embroidered Sweatshirt', 'sweatshirts', 2999, 2),
        savedAt: now.subtract(const Duration(days: 2))),
    SavedProduct(
        product: p('h1', 'Outfitters', 'Graphic Hoodie', 'hoodies', 3249, 3),
        savedAt: now.subtract(const Duration(days: 3))),
    SavedProduct(
        product: p('o1', 'Breakout', 'Oxford Striped Shirt', 'shirts', 4199, 4),
        savedAt: now.subtract(const Duration(days: 12))),
    SavedProduct(
        product: p('k1', 'Saya', 'Embroidered Lawn Kurta', 'kurta', 5490, 5),
        savedAt: now.subtract(const Duration(days: 20))),
  ];
}
