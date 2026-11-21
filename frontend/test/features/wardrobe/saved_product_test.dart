import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/wardrobe/data/models/saved_product.dart';

ProductRecommendation _p(String id, {String url = ''}) => ProductRecommendation(
      id: id,
      brand: 'Brand',
      title: 'Item $id',
      productUrl: url.isEmpty ? 'https://shop.pk/$id' : url,
    );

void main() {
  group('ProductRecommendation.key', () {
    test('uses the id, or the URL when the id is empty (wardrobe bug)', () {
      expect(_p('42').key, '42');
      expect(_p('', url: 'https://shop.pk/x').key, 'https://shop.pk/x');
    });
  });

  group('groupByRecency (SFR-036)', () {
    final now = DateTime(2026, 10, 18, 15);
    SavedProduct at(String id, DateTime t) => SavedProduct(product: _p(id), savedAt: t);

    test('Today / This week (previous 6 days) / Earlier, newest first', () {
      final groups = groupByRecency([
        at('old', DateTime(2026, 10, 1)),
        at('today-early', DateTime(2026, 10, 18, 0, 5)),
        at('six-days', DateTime(2026, 10, 12, 23)),
        at('seven-days', DateTime(2026, 10, 11, 23)),
        at('today-late', DateTime(2026, 10, 18, 14)),
      ], now);

      expect(groups.keys, [WardrobeSection.today, WardrobeSection.thisWeek, WardrobeSection.earlier]);
      expect(groups[WardrobeSection.today]!.map((e) => e.key), ['today-late', 'today-early']);
      expect(groups[WardrobeSection.thisWeek]!.map((e) => e.key), ['six-days']);
      expect(groups[WardrobeSection.earlier]!.map((e) => e.key), ['seven-days', 'old']);
    });

    test('empty sections are omitted', () {
      expect(groupByRecency([at('a', DateTime(2026, 10, 18, 9))], now).keys, [WardrobeSection.today]);
      expect(groupByRecency([], now), isEmpty);
    });
  });

  group('SavedProduct cache', () {
    test('round-trips with its saved date', () {
      final item = SavedProduct(product: _p('1'), savedAt: DateTime.utc(2026, 10, 1, 8));
      final back = SavedProduct.fromCacheJson(item.toCacheJson());
      expect(back.key, '1');
      expect(back.savedAt, DateTime.utc(2026, 10, 1, 8));
    });

    test('reads old cache entries (bare product, no date) as Earlier', () {
      final legacy = SavedProduct.fromCacheJson(_p('7').toJson());
      expect(legacy.key, '7');
      expect(groupByRecency([legacy], DateTime(2026, 10, 18)).keys, [WardrobeSection.earlier]);
    });
  });

  group('learnedPreferencesText (lost interpolation bug)', () {
    test('includes the actual values', () {
      final text = learnedPreferencesText({
        'favorite_categories': ['kurta', 'waistcoat'],
        'favorite_brands': ['Edenrobe'],
        'favorite_colors': <String>[],
        'recent_loved_titles': ['Black Kurta'],
      });
      expect(text, contains('- Preferred Garment Types: kurta, waistcoat'));
      expect(text, contains('- Preferred Brands: Edenrobe'));
      expect(text, isNot(contains('Preferred Colors')));
      expect(text, contains('- Specific Items User Loved: "Black Kurta"'));
    });

    test('empty signals give empty text', () {
      expect(learnedPreferencesText({}), '');
    });
  });
}
