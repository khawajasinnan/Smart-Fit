class ChatMessageModel {
  final String id;
  final String sessionId;
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final List<String> imageUrls;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const ChatMessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.imageUrls = const [],
    this.metadata,
    required this.createdAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) =>
      ChatMessageModel(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        imageUrls: (json['image_urls'] as List<dynamic>?)?.cast<String>() ?? [],
        metadata: json['metadata'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

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
    'created_at': createdAt.toIso8601String(),
  };
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
