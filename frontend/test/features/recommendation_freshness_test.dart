import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// The card says how current a product's price and stock are (spec §23.12).
void main() {
  final now = DateTime.utc(2026, 11, 8, 12);

  ProductRecommendation product(Map<String, dynamic> extra) => ProductRecommendation.fromJson({
        'id': 'zara-shahjahan:shab',
        'brand': 'Zara Shahjahan',
        'title': 'Shab',
        'price_pkr': 18990,
        'product_url': 'https://zarashahjahan.com/products/shab',
        ...extra,
      });

  test('a store-confirmed price says so', () {
    final p = product({'price_checked_at': '2026-11-08T11:59:30Z', 'catalog_updated_at': '2026-11-08T06:00:00Z'});
    expect(p.freshnessLabel(now), 'Price & stock checked just now');
  });

  test('otherwise the catalog copy and its age', () {
    expect(product({'catalog_updated_at': '2026-11-08T09:00:00Z'}).freshnessLabel(now), 'Store price from 3 h ago');
    expect(product({'catalog_updated_at': '2026-11-08T11:40:00Z'}).freshnessLabel(now), 'Store price from 20 min ago');
  });

  test('older apps and saved items without the fields show nothing', () {
    expect(product({}).freshnessLabel(now), isNull);
  });

  test('round-trips through the saved wardrobe JSON', () {
    final p = product({'price_checked_at': '2026-11-08T11:59:30Z'});
    expect(ProductRecommendation.fromJson(p.toJson()).priceCheckedAt, p.priceCheckedAt);
  });
}
