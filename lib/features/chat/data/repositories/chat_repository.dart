import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/chat/data/models/chat_message_model.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/chat/data/services/gemini_service.dart'
    show ChatImageInput, GeminiService;
import 'package:smartfit/features/chat/data/services/scraper_api_service.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:uuid/uuid.dart';

class ChatRepository {
  final SupabaseClient _client;
  final GeminiService _gemini;
  final ScraperApiService _scraper = ScraperApiService();

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
    await touchSession(message.sessionId);
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

  Future<void> touchSession(String sessionId) async {
    await _client
        .from(ApiEndpoints.chatSessionsTable)
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', sessionId);
  }

  Future<void> deleteSession(String sessionId) async {
    // Delete messages first, then the session
    await _client
        .from(ApiEndpoints.chatMessagesTable)
        .delete()
        .eq('session_id', sessionId);
    await _client
        .from(ApiEndpoints.chatSessionsTable)
        .delete()
        .eq('id', sessionId);
  }

  Future<void> deleteAllSessions(String userId) async {
    // Get all session IDs
    final sessions = await getSessions(userId);
    for (final session in sessions) {
      try {
        await deleteSession(session.id);
      } catch (_) {}
    }
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
    try {
      final signedUrl = await _client.storage
          .from(ApiEndpoints.chatImagesBucket)
          .createSignedUrl(
            path,
            60 * 60 * 24 * 365 * 10,
          ); // 10 years expiration
      return signedUrl;
    } catch (e) {
      debugPrint(
        '[ChatRepository] Signed URL creation failed, falling back to public URL: $e',
      );
      return _client.storage
          .from(ApiEndpoints.chatImagesBucket)
          .getPublicUrl(path);
    }
  }

  /// Get AI response from Gemini — real AI, not mock!
  Future<String> getAiResponse(
    String userId,
    String userMessage, {
    List<ChatImageInput> images = const [],
    String? chatContext,
    String? learnedPreferencesContext,
  }) async {
    final profileContext = await _loadProfileContext(userId);
    final combinedProfileContext = [
      if (profileContext != null) profileContext,
      if (learnedPreferencesContext != null &&
          learnedPreferencesContext.trim().isNotEmpty)
        learnedPreferencesContext,
    ].join('\n\n');

    return await _gemini.sendMessage(
      userMessage,
      images: images,
      profileContext: combinedProfileContext.isNotEmpty ? combinedProfileContext : null,
      chatContext: chatContext,
    );
  }

  /// Search Pakistani retailers for product recommendations.
  Future<ScrapeRecommendResponse> searchProducts({
    required String userId,
    required String userMessage,
    String assistantMessage = '',
    Map<String, dynamic>? dynamicPrefs,
    Map<String, dynamic>? learnedFeedback,
  }) async {
    final profile = await _loadFullProfile(userId);
    if (profile == null) {
      return ScrapeRecommendResponse(
        products: [],
        searchQuery: '',
        brandsSearched: [],
        message:
            'Complete your profile first for personalized recommendations.',
      );
    }
    return _scraper.searchProducts(
      profile: profile,
      userMessage: userMessage,
      assistantMessage: assistantMessage,
      dynamicPrefs: dynamicPrefs,
      learnedFeedback: learnedFeedback,
    );
  }

  Future<String?> inferProfileSize(String userId) async {
    final profile = await _loadFullProfile(userId);
    if (profile == null) return null;
    final chest = profile.chestCm;
    final waist = profile.waistCm;
    final height = profile.heightCm;
    final weight = profile.weightKg;
    if (chest != null && chest > 0) {
      final inches = chest / 2.54;
      if (inches <= 35) return 'S';
      if (inches <= 37) return 'M';
      if (inches <= 39) return 'L';
      if (inches <= 41) return 'XL';
      if (inches <= 43) return 'XXL';
      if (inches <= 45) return 'XXXL';
      return '4XL';
    }
    if (waist != null && waist > 0) {
      if (waist < 70) return 'S';
      if (waist < 78) return 'M';
      if (waist < 86) return 'L';
      return 'XL';
    }
    if (height != null && weight != null && height > 0 && weight > 0) {
      final bmi = weight / ((height / 100) * (height / 100));
      if (bmi < 20) return 'S';
      if (bmi < 25) return 'M';
      if (bmi < 30) return 'L';
      return 'XL';
    }
    return null;
  }

  /// Reset the AI chat session (start fresh)
  void resetAiChat() {
    _gemini.resetChat();
  }

  Future<String?> getUserEthnicity(String userId) async {
    final profile = await _loadFullProfile(userId);
    return profile?.ethnicity;
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

  Future<UserProfileModel?> _loadFullProfile(String userId) async {
    try {
      final data = await _client
          .from(ApiEndpoints.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return UserProfileModel.fromJson(data);
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
