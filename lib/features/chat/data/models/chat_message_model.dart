import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';

class ChatMessageModel {
  final String id;
  final String sessionId;
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final List<String> imageUrls;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final List<ProductRecommendation> products;

  const ChatMessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.imageUrls = const [],
    this.metadata,
    required this.createdAt,
    this.products = const [],
  });

  /// Whether this message contains scraped product recommendations.
  bool get hasProducts => products.isNotEmpty;

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>?;
    final metadataProducts = metadata?['products'];
    return ChatMessageModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      imageUrls: (json['image_urls'] as List<dynamic>?)?.cast<String>() ?? [],
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at'] as String),
      products: metadataProducts is List
          ? metadataProducts
                .whereType<Map<String, dynamic>>()
                .map(ProductRecommendation.fromJson)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'image_urls': imageUrls,
    'metadata': metadata,
    'created_at': createdAt.toIso8601String(),
  };

  Map<String, dynamic> toLegacyJson() => {
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'image_urls': imageUrls,
    'created_at': createdAt.toIso8601String(),
  };

  /// Create a copy with products attached.
  ChatMessageModel copyWithProducts(List<ProductRecommendation> products) {
    return ChatMessageModel(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content,
      imageUrls: imageUrls,
      metadata: metadata,
      createdAt: createdAt,
      products: products,
    );
  }
}

class ChatSessionModel {
  final String id;
  final String userId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatSessionModel({
    required this.id,
    required this.userId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) =>
      ChatSessionModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
