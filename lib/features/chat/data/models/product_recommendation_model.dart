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
  });

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
    );
  }

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
  };

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
