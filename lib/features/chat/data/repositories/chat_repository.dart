import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/chat/data/models/chat_message_model.dart';
import 'package:smartfit/features/chat/data/services/gemini_service.dart'
    show ChatImageInput, GeminiService;
import 'package:uuid/uuid.dart';

class ChatRepository {
  final SupabaseClient _client;
  final GeminiService _gemini;

  ChatRepository(this._client, this._gemini);

  Future<String> createSession(
    String userId, {
    String title = 'Style Session',
  }) async {
    final id = const Uuid().v4();
    await _client.from(ApiEndpoints.chatSessionsTable).insert({
      'id': id,
      'user_id': userId,
      'title': title,
    });
    return id;
  }

  Future<void> sendMessage(ChatMessageModel message) async {
    try {
      await _client
          .from(ApiEndpoints.chatMessagesTable)
          .insert(message.toJson());
    } on PostgrestException catch (e) {
      if (!_isSchemaMismatch(e)) rethrow;
      await _client
          .from(ApiEndpoints.chatMessagesTable)
          .insert(message.toLegacyJson());
    }
  }

  Future<List<ChatMessageModel>> getMessages(String sessionId) async {
    final data = await _client
        .from(ApiEndpoints.chatMessagesTable)
        .select()
        .eq('session_id', sessionId)
        .order('created_at');
    return data.map((j) => ChatMessageModel.fromJson(j)).toList();
  }

  Future<List<ChatSessionModel>> getSessions(String userId) async {
    final data = await _client
        .from(ApiEndpoints.chatSessionsTable)
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(30);
    return data.map((j) => ChatSessionModel.fromJson(j)).toList();
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    await _client
        .from(ApiEndpoints.chatSessionsTable)
        .update({
          'title': title,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  Future<String> uploadChatImage({
    required String userId,
    required String sessionId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final safeExt = extension.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final path = '$userId/$sessionId/${const Uuid().v4()}.$ext';
    await _client.storage
        .from(ApiEndpoints.chatImagesBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForExtension(ext),
          ),
        );
    return _client.storage
        .from(ApiEndpoints.chatImagesBucket)
        .getPublicUrl(path);
  }

  /// Get AI response from Gemini — real AI, not mock!
  Future<String> getAiResponse(
    String userId,
    String userMessage, {
    List<ChatImageInput> images = const [],
  }) async {
    final profileContext = await _loadProfileContext(userId);
    return await _gemini.sendMessage(
      userMessage,
      images: images,
      profileContext: profileContext,
    );
  }

  /// Reset the AI chat session (start fresh)
  void resetAiChat() {
    _gemini.resetChat();
  }

  Future<String?> _loadProfileContext(String userId) async {
    try {
      final profile = await _client
          .from(ApiEndpoints.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (profile == null) return null;
      return profile.entries
          .where(
            (entry) => entry.value != null && entry.value.toString().isNotEmpty,
          )
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    } catch (_) {
      return null;
    }
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  bool _isSchemaMismatch(PostgrestException e) {
    final message = e.message.toLowerCase();
    return message.contains('column') ||
        message.contains('schema cache') ||
        message.contains('could not find');
  }
}
