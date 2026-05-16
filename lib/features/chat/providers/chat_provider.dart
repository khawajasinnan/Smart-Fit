import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/chat/data/models/chat_message_model.dart';
import 'package:smartfit/features/chat/data/repositories/chat_repository.dart';
import 'package:smartfit/features/chat/data/services/gemini_service.dart'
    show ChatImageInput, GeminiService;
import 'package:uuid/uuid.dart';

class PendingChatImage {
  final Uint8List bytes;
  final String extension;
  final String mimeType;

  const PendingChatImage({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });
}

/// Single GeminiService instance shared across the app
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(geminiServiceProvider),
  );
});

class ChatNotifier extends StateNotifier<List<ChatMessageModel>> {
  final ChatRepository _repo;
  final String _userId;
  String? _sessionId;
  bool _isTyping = false;
  bool _isLoadingSessions = false;
  List<ChatSessionModel> _sessions = [];

  ChatNotifier(this._repo, this._userId) : super([]);

  bool get isTyping => _isTyping;
  bool get isLoadingSessions => _isLoadingSessions;
  String? get sessionId => _sessionId;
  List<ChatSessionModel> get sessions => _sessions;

  Future<void> startSession({bool fresh = false}) async {
    if (_sessionId != null && !fresh) return;
    // Try to create DB session, but don't crash if it fails
    try {
      _sessionId = await _repo.createSession(_userId);
    } catch (e) {
      debugPrint('Failed to create chat session in DB: $e');
      _sessionId = const Uuid().v4(); // fallback local session
    }
    // Reset Gemini chat for fresh session
    _repo.resetAiChat();
    // Welcome message
    final welcome = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content:
          "Fit check desk is open. Send me a picture or tell me the occasion, and I’ll style you properly. If the outfit is confused, I’ll be kind... mostly.",
      createdAt: DateTime.now(),
    );
    state = [welcome];
    await loadSessions();
  }

  Future<void> loadSessions() async {
    _isLoadingSessions = true;
    state = [...state];
    try {
      _sessions = await _repo.getSessions(_userId);
    } catch (e) {
      debugPrint('Failed to load chat sessions: $e');
    } finally {
      _isLoadingSessions = false;
      state = [...state];
    }
  }

  Future<void> loadSession(String sessionId) async {
    _sessionId = sessionId;
    _repo.resetAiChat();
    try {
      state = await _repo.getMessages(sessionId);
    } catch (e) {
      debugPrint('Failed to load chat messages: $e');
    }
  }

  Future<void> sendMessage(
    String content, {
    List<PendingChatImage> images = const [],
  }) async {
    if (_sessionId == null) await startSession();
    final messageText = content.trim().isEmpty && images.isNotEmpty
        ? 'Analyze this outfit photo for fit, color harmony, silhouette, skin-tone match, body-shape styling, and Pakistan-ready product ideas.'
        : content.trim();

    final uploadedUrls = <String>[];
    for (final image in images) {
      try {
        final url = await _repo.uploadChatImage(
          userId: _userId,
          sessionId: _sessionId!,
          bytes: image.bytes,
          extension: image.extension,
        );
        uploadedUrls.add(url);
      } catch (e) {
        debugPrint('Failed to upload chat image: $e');
      }
    }

    final userMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'user',
      content: messageText,
      imageUrls: uploadedUrls,
      metadata: images.isNotEmpty
          ? {'cv_requested': true, 'image_count': images.length}
          : null,
      createdAt: DateTime.now(),
    );
    state = [...state, userMsg];

    // Save to DB (don't crash if it fails)
    try {
      await _repo.sendMessage(userMsg);
      if (state.length <= 2) {
        await _repo.updateSessionTitle(
          _sessionId!,
          messageText.length > 34
              ? '${messageText.substring(0, 34)}...'
              : messageText,
        );
      }
    } catch (_) {}

    // Get Gemini AI response
    _isTyping = true;
    state = [...state]; // trigger rebuild for typing indicator

    final aiText = await _repo.getAiResponse(
      _userId,
      messageText,
      images: images
          .map(
            (image) =>
                ChatImageInput(bytes: image.bytes, mimeType: image.mimeType),
          )
          .toList(),
    );
    _isTyping = false;

    final aiMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content: aiText,
      createdAt: DateTime.now(),
    );
    state = [...state, aiMsg];
    try {
      await _repo.sendMessage(aiMsg);
    } catch (_) {}
    await loadSessions();
  }
}

final chatNotifierProvider =
    StateNotifierProvider.family<ChatNotifier, List<ChatMessageModel>, String>((
      ref,
      userId,
    ) {
      return ChatNotifier(ref.watch(chatRepositoryProvider), userId);
    });
