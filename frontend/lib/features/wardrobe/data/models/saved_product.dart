import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// A product the user saved to their wardrobe, with when it was saved
/// (SFR-035 save, SFR-036 browse organised by date).
class SavedProduct {
  const SavedProduct({required this.product, required this.savedAt});

  final ProductRecommendation product;
  final DateTime savedAt;

  String get key => product.key;

  Map<String, dynamic> toCacheJson() => {
        'product': product.toJson(),
        'saved_at': savedAt.toIso8601String(),
      };

  /// Reads the local cache. Older cache entries stored the bare product, with
  /// no date — those sort as "Earlier".
  factory SavedProduct.fromCacheJson(Map<String, dynamic> json) {
    if (json['product'] is Map) {
      return SavedProduct(
        product: ProductRecommendation.fromJson(Map<String, dynamic>.from(json['product'] as Map)),
        savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ?? _unknownDate,
      );
    }
    return SavedProduct(product: ProductRecommendation.fromJson(json), savedAt: _unknownDate);
  }

  static final DateTime _unknownDate = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Date sections for the wardrobe (SFR-036).
enum WardrobeSection {
  today('Today'),
  thisWeek('This week'),
  earlier('Earlier');

  const WardrobeSection(this.label);
  final String label;
}

/// Groups items newest-first into Today / This week (previous 6 days) /
/// Earlier, using local calendar days. Empty sections are omitted.
Map<WardrobeSection, List<SavedProduct>> groupByRecency(List<SavedProduct> items, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(const Duration(days: 6));
  final sorted = [...items]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  final groups = <WardrobeSection, List<SavedProduct>>{};
  for (final item in sorted) {
    final local = item.savedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final section = !day.isBefore(today)
        ? WardrobeSection.today
        : !day.isBefore(weekStart)
            ? WardrobeSection.thisWeek
            : WardrobeSection.earlier;
    groups.putIfAbsent(section, () => []).add(item);
  }
  return {
    for (final s in WardrobeSection.values)
      if (groups[s] != null) s: groups[s]!,
  };
}
