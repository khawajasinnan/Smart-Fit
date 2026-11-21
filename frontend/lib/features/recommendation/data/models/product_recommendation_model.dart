/// Dart mirror of backend `ProductRecommendation` from models/schemas.py.
class ProductRecommendation {
  final String id;
  final String brand;
  final String title;
  final String? category;
  final int? pricePkr;
  final String currency;
  final String? imageUrl;
  final String productUrl;
  final List<String> sizes;
  final List<String> colors;
  final List<String> tags;
  final int matchScore;
  final List<String> matchReasons;
  final bool inStock;
  final String? recommendedSize;
  final String? sizeGuidance;

  /// When the store itself confirmed price and stock, just before this was
  /// shown (null: not re-checked, the price is the catalog's).
  final DateTime? priceCheckedAt;

  /// When the catalog last read this product from the store.
  final DateTime? catalogUpdatedAt;

  /// Saved virtual try-on images for this product, by side ("front", "right",
  /// "back", "left") -> path in the private `tryon-results` bucket (SFR-035:
  /// an outfit is saved with its try-on). Paths, not URLs: signed URLs expire,
  /// so the app asks for fresh ones when it shows them.
  final Map<String, String> tryOnPaths;

  /// The hairstyle saved with this item, if any (SFR-035/036): id, name, face shape,
  /// suitability and a small picture (`ChosenHairstyle.fromWardrobeJson`).
  final Map<String, dynamic>? hairstyle;

  /// "lightgbm+random_forest" when the learned models ranked it, "rules" otherwise.
  final String rankingModel;

  /// False when the Random Forest validator disagreed with the ranker (null: not checked).
  final bool? validated;

  /// Why it ranked here, strongest first (empty with rule ranking).
  final List<MatchFactor> explanation;

  /// Suitability 0..100 per aspect (skin_tone, colours, size, body_shape, occasion, budget);
  /// aspects without enough information are left out.
  final Map<String, int> suitability;

  bool get isLearnedRanking => rankingModel != 'rules';

  const ProductRecommendation({
    required this.id,
    required this.brand,
    required this.title,
    this.category,
    this.pricePkr,
    this.currency = 'PKR',
    this.imageUrl,
    required this.productUrl,
    this.sizes = const [],
    this.colors = const [],
    this.tags = const [],
    this.matchScore = 0,
    this.matchReasons = const [],
    this.inStock = true,
    this.recommendedSize,
    this.sizeGuidance,
    this.priceCheckedAt,
    this.catalogUpdatedAt,
    this.tryOnPaths = const {},
    this.hairstyle,
    this.rankingModel = 'rules',
    this.validated,
    this.explanation = const [],
    this.suitability = const {},
  });

  /// Stable identity used by the wardrobe and Love-Fit: the scraped id, or
  /// the product URL when a retailer didn't provide one.
  String get key => id.isNotEmpty ? id : productUrl;

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      id: json['id'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String?,
      pricePkr: json['price_pkr'] as int?,
      currency: json['currency'] as String? ?? 'PKR',
      imageUrl: json['image_url'] as String?,
      productUrl: json['product_url'] as String? ?? '',
      sizes: (json['sizes'] as List<dynamic>?)?.cast<String>() ?? [],
      colors: (json['colors'] as List<dynamic>?)?.cast<String>() ?? [],
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      matchScore: json['match_score'] as int? ?? 0,
      matchReasons:
          (json['match_reasons'] as List<dynamic>?)?.cast<String>() ?? [],
      inStock: json['in_stock'] as bool? ?? true,
      recommendedSize: json['recommended_size'] as String?,
      sizeGuidance: json['size_guidance'] as String?,
      priceCheckedAt: DateTime.tryParse(json['price_checked_at'] as String? ?? ''),
      catalogUpdatedAt: DateTime.tryParse(json['catalog_updated_at'] as String? ?? ''),
      tryOnPaths: {
        for (final e in ((json['tryon_paths'] as Map?) ?? const {}).entries)
          if (e.value is String) e.key.toString(): e.value as String,
      },
      hairstyle: json['hairstyle'] is Map ? Map<String, dynamic>.from(json['hairstyle'] as Map) : null,
      rankingModel: json['ranking_model'] as String? ?? 'rules',
      validated: json['validated'] as bool?,
      explanation: [
        for (final f in (json['explanation'] as List<dynamic>? ?? const []))
          if (MatchFactor.fromJson(f) case final factor?) factor,
      ],
      suitability: {
        for (final e in ((json['suitability'] as Map?) ?? const {}).entries)
          if (e.value is num) e.key.toString(): (e.value as num).round(),
      },
    );
  }

  /// This product with a try-on attached (for saving to the wardrobe).
  ProductRecommendation withTryOn(Map<String, String> paths) =>
      ProductRecommendation.fromJson({...toJson(), 'tryon_paths': paths});

  /// This product with a hairstyle that goes with it (SFR-035): `ChosenHairstyle.toWardrobeJson()`.
  ProductRecommendation withHairstyle(Map<String, dynamic> hairstyle) =>
      ProductRecommendation.fromJson({...toJson(), 'hairstyle': hairstyle});

  bool get hasHairstyle => hairstyle != null;

  bool get hasTryOn => tryOnPaths.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'brand': brand,
    'title': title,
    'category': category,
    'price_pkr': pricePkr,
    'currency': currency,
    'image_url': imageUrl,
    'product_url': productUrl,
    'sizes': sizes,
    'colors': colors,
    'tags': tags,
    'match_score': matchScore,
    'match_reasons': matchReasons,
    'in_stock': inStock,
    'recommended_size': recommendedSize,
    'size_guidance': sizeGuidance,
    if (priceCheckedAt != null) 'price_checked_at': priceCheckedAt!.toIso8601String(),
    if (catalogUpdatedAt != null) 'catalog_updated_at': catalogUpdatedAt!.toIso8601String(),
    if (tryOnPaths.isNotEmpty) 'tryon_paths': tryOnPaths,
    'hairstyle': ?hairstyle,
    'ranking_model': rankingModel,
    'validated': ?validated,
    if (explanation.isNotEmpty) 'explanation': [for (final f in explanation) f.toJson()],
    if (suitability.isNotEmpty) 'suitability': suitability,
  };

  /// How current the price and stock are, for the card:
  /// "Price & stock checked just now" / "Store price from 3 h ago" / null.
  String? freshnessLabel([DateTime? now]) {
    now ??= DateTime.now();
    final checked = priceCheckedAt;
    if (checked != null) {
      return 'Price & stock checked ${_ago(now.difference(checked.toLocal()))}';
    }
    final updated = catalogUpdatedAt;
    if (updated != null) return 'Store price from ${_ago(now.difference(updated.toLocal()))}';
    return null;
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 2) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }

  /// Human-readable price string (e.g. "Rs. 4,500")
  String get formattedPrice {
    if (pricePkr == null) return 'Price N/A';
    final formatted = pricePkr.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return 'Rs. $formatted';
  }
}

/// One reason a product ranked where it did (spec §23.25): a model feature
/// and how far it pushed the score up (positive) or down (negative).
class MatchFactor {
  const MatchFactor({required this.feature, required this.text, required this.impact});

  final String feature;
  final String text;
  final double impact;

  bool get helps => impact > 0;

  static MatchFactor? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text']?.toString() ?? '';
    if (text.isEmpty) return null;
    return MatchFactor(
      feature: json['feature']?.toString() ?? '',
      text: text,
      impact: (json['impact'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'feature': feature, 'text': text, 'impact': impact};
}

/// Response wrapper from the scrape/recommend endpoint.
class ScrapeRecommendResponse {
  final List<ProductRecommendation> products;
  final String searchQuery;
  final List<String> brandsSearched;
  final String message;

  const ScrapeRecommendResponse({
    required this.products,
    required this.searchQuery,
    required this.brandsSearched,
    this.message = '',
  });

  factory ScrapeRecommendResponse.fromJson(Map<String, dynamic> json) {
    return ScrapeRecommendResponse(
      products:
          (json['products'] as List<dynamic>?)
              ?.map(
                (e) =>
                    ProductRecommendation.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      searchQuery: json['search_query'] as String? ?? '',
      brandsSearched:
          (json['brands_searched'] as List<dynamic>?)?.cast<String>() ?? [],
      message: json['message'] as String? ?? '',
    );
  }

  ScrapeRecommendResponse copyWith({
    List<ProductRecommendation>? products,
    String? searchQuery,
    List<String>? brandsSearched,
    String? message,
  }) {
    return ScrapeRecommendResponse(
      products: products ?? this.products,
      searchQuery: searchQuery ?? this.searchQuery,
      brandsSearched: brandsSearched ?? this.brandsSearched,
      message: message ?? this.message,
    );
  }
}
