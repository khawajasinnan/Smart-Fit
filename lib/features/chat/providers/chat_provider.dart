import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/chat/data/models/chat_message_model.dart';
import 'package:smartfit/features/chat/data/repositories/chat_repository.dart';
import 'package:smartfit/features/chat/data/services/gemini_service.dart'
    show ChatImageInput, GeminiService;
import 'package:smartfit/features/chat/providers/loved_fits_provider.dart';
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

class _PendingSearchConfirmation {
  final Map<String, dynamic> dynamicPrefs;
  final String userMessage;
  final String assistantMessage;
  final String profileSize;
  final String requestedSize;

  const _PendingSearchConfirmation({
    required this.dynamicPrefs,
    required this.userMessage,
    required this.assistantMessage,
    required this.profileSize,
    required this.requestedSize,
  });
}

class _PendingCultureConfirmation {
  final String triggerJson;
  final String userMessage;
  final String assistantMessage;
  final String ethnicity;

  const _PendingCultureConfirmation({
    required this.triggerJson,
    required this.userMessage,
    required this.assistantMessage,
    required this.ethnicity,
  });
}

bool _isEthnicGarmentFor(String ethnicity, String title) {
  final t = title.toLowerCase();
  switch (ethnicity.toLowerCase()) {
    case 'punjabi':
      return t.contains('kurta') ||
          t.contains('shalwar') ||
          t.contains('patiala') ||
          t.contains('phulkari') ||
          t.contains('tehmat') ||
          t.contains('lacha') ||
          t.contains('khussa') ||
          t.contains('punjabi');
    case 'sindhi':
      return t.contains('ajrak') ||
          t.contains('sindhi') ||
          t.contains('topi') ||
          t.contains('rilli');
    case 'balochi':
      return t.contains('balochi') ||
          t.contains('ghed') ||
          t.contains('chawat') ||
          t.contains('turban');
    case 'pathan':
    case 'pashtun':
      return t.contains('peshawari') ||
          t.contains('kheri') ||
          t.contains('perahan') ||
          t.contains('tunban') ||
          t.contains('pakol') ||
          t.contains('waskat');
    case 'saraiki':
      return t.contains('saraiki') ||
          t.contains('jhumar') ||
          t.contains('multani') ||
          t.contains('chunri');
    default:
      return t.contains(ethnicity.toLowerCase());
  }
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

// ── Regex to detect [SMARTFIT_SEARCH: {...}] trigger in AI response ──
final _searchTriggerRegex = RegExp(
  r'\[SMARTFIT_SEARCH:\s*(\{.*?\})\]',
  dotAll: true,
);

// ── Cleanup regex: catches incomplete/malformed triggers that leaked into text ──
final _searchCleanupRegex = RegExp(
  r'\[SMARTFIT_SEARCH:?\s*\{?[^]]*$',
  dotAll: true,
);

Map<String, dynamic>? _moderationMetadata(String text) {
  final lower = text.toLowerCase();
  final categories = <String>[];
  final checks = <String, List<String>>{
    'adult_or_18_plus': ['18+', 'nude', 'naked', 'porn', 'sex', 'sexy pic'],
    'self_harm': ['suicide', 'self harm', 'kill myself'],
    'violence': ['kill', 'weapon', 'bomb', 'attack'],
    'abuse_or_hate': ['hate', 'abuse', 'harass', 'blackmail'],
  };
  for (final entry in checks.entries) {
    if (entry.value.any(lower.contains)) categories.add(entry.key);
  }
  if (categories.isEmpty) return null;
  return {
    'moderation': {
      'flagged': true,
      'categories': categories,
      'review_status': 'pending',
    },
  };
}

String? _normalizeRequestedSize(String text) {
  final normalized = text.toLowerCase();
  final patterns = <String, List<String>>{
    'XS': ['extra small', 'x-small', 'xs'],
    'S': ['small', ' size s', ' s size', ' s '],
    'M': ['medium', ' size m', ' m size', ' m '],
    'L': ['large', ' size l', ' l size', ' l '],
    'XL': ['extra large', 'x-large', 'xl'],
    'XXL': ['double xl', '2xl', 'xxl'],
    'XXXL': ['triple xl', '3xl', 'xxxl'],
    '4XL': ['4xl', 'xxxxl'],
  };
  final padded = ' $normalized ';
  for (final entry in patterns.entries) {
    if (entry.value.any((p) => padded.contains(p))) return entry.key;
  }
  return null;
}

bool _isConfirmation(String text) {
  final normalized = text.toLowerCase();
  return [
    'yes',
    'confirm',
    'sure',
    'ok',
    'okay',
    'use chat',
    'large',
    'xl',
    'small',
    'medium',
  ].any(normalized.contains);
}

bool _wantsProfileSize(String text) {
  final normalized = text.toLowerCase();
  return [
    'profile',
    'my size',
    'static',
    'recommended',
    'use profile',
    'profile size',
  ].any(normalized.contains);
}

bool _hasNegativeBudget(String text) {
  return RegExp(
    r'(?<!\d)-\s*\d[\d,]*\s*(?:pkr|rs\.?|rupees?)?\b',
    caseSensitive: false,
  ).hasMatch(text);
}

String _buildChatContext(List<ChatMessageModel> messages) {
  final recent = messages
      .where((m) => m.content.trim().isNotEmpty)
      .toList()
      .reversed
      .take(10)
      .toList()
      .reversed;
  return recent
      .map((m) {
        final role = m.role == 'assistant' ? 'Stylist' : 'User';
        return '$role: ${m.content.trim()}';
      })
      .join('\n');
}

class ChatNotifier extends StateNotifier<List<ChatMessageModel>> {
  final ChatRepository _repo;
  final String _userId;
  final Ref _ref;
  String? _sessionId;
  bool _isTyping = false;
  bool _isSearching = false;
  bool _isLoadingSessions = false;
  _PendingSearchConfirmation? _pendingSearchConfirmation;
  _PendingCultureConfirmation? _pendingCultureConfirmation;
  bool? _culturalOnlyPreference; // null = unasked, true = cultural only, false = overall
  List<ChatSessionModel> _sessions = [];

  ChatNotifier(this._repo, this._userId, this._ref) : super([]);

  bool get isTyping => _isTyping;
  bool get isSearching => _isSearching;
  bool get isLoadingSessions => _isLoadingSessions;
  String? get sessionId => _sessionId;
  List<ChatSessionModel> get sessions => _sessions;

  Future<void> startSession({bool fresh = false}) async {
    if (_sessionId != null && !fresh) return;
    _culturalOnlyPreference = null;
    _pendingCultureConfirmation = null;
    _pendingSearchConfirmation = null;
    // Try to create DB session, but don't crash if it fails
    try {
      _sessionId = await _repo.createSession(_userId);
    } catch (e) {
      debugPrint('Failed to create chat session in DB: $e');
      _sessionId = const Uuid().v4(); // fallback local session
    }
    // Reset Gemini chat for fresh session
    _repo.resetAiChat();
    // Welcome message in clear, friendly English + Roman Urdu
    final welcome = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content:
          "Hello! Main hoon aapki SmartFit AI Stylist. Aap mujhse kisi bhi outfit, styling tips, ya shopping ke baare mein pooch sakte hain. Apni photo bheinjen fit check ke liye, ya bataen aaj aapko kis type ka look chahiye!",
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
      final messages = await _repo.getMessages(sessionId);
      if (messages.isEmpty) {
        // Session exists but has no messages — start fresh
        state = [];
        await startSession(fresh: true);
      } else {
        state = messages;
      }
    } catch (e) {
      debugPrint('Failed to load chat messages: $e');
      // If loading fails, start a fresh session instead of crashing
      await startSession(fresh: true);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _repo.deleteSession(sessionId);
      _sessions = _sessions.where((s) => s.id != sessionId).toList();
      // If we deleted the current session, start fresh
      if (_sessionId == sessionId) {
        await startSession(fresh: true);
      } else {
        state = [...state]; // trigger rebuild
      }
    } catch (e) {
      debugPrint('Failed to delete session: $e');
    }
  }

  Future<void> clearAllSessions() async {
    try {
      await _repo.deleteAllSessions(_userId);
      _sessions = [];
      await startSession(fresh: true);
    } catch (e) {
      debugPrint('Failed to clear sessions: $e');
      // Still clear local state
      _sessions = [];
      await startSession(fresh: true);
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

    final messageMetadata = {
      if (images.isNotEmpty) 'cv_requested': true,
      if (images.isNotEmpty) 'image_count': images.length,
      ...?_moderationMetadata(messageText),
    };
    final userMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'user',
      content: messageText,
      imageUrls: uploadedUrls,
      metadata: messageMetadata.isEmpty ? null : messageMetadata,
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

    if (_hasNegativeBudget(messageText)) {
      final budgetMsg = ChatMessageModel(
        id: const Uuid().v4(),
        sessionId: _sessionId!,
        role: 'assistant',
        content:
            'Budget negative nahi ho sakta. Please positive PKR budget bataen, jaise 5000 PKR.',
        createdAt: DateTime.now(),
      );
      state = [...state, budgetMsg];
      try {
        await _repo.sendMessage(budgetMsg);
      } catch (_) {}
      await loadSessions();
      return;
    }

    if (_pendingCultureConfirmation != null && images.isEmpty) {
      final pending = _pendingCultureConfirmation!;
      final lower = messageText.toLowerCase();
      final wantsCultural = lower.contains(pending.ethnicity.toLowerCase()) ||
          lower.contains('cultur') ||
          lower.contains('traditional') ||
          lower.contains('yes') ||
          lower.contains('haan') ||
          lower.contains('only');
      final wantsOverall = lower.contains('overall') ||
          lower.contains('both') ||
          lower.contains('all') ||
          lower.contains('dono') ||
          lower.contains('general');

      if (wantsCultural || wantsOverall) {
        final culturalChosen = wantsCultural && !wantsOverall;
        _culturalOnlyPreference = culturalChosen;
        _pendingCultureConfirmation = null;

        final answerText = culturalChosen
            ? 'Theek hai! Main sirf ${pending.ethnicity} cultural aur traditional outfits par focus kar rahi hoon.'
            : 'Theek hai! Main overall trendy outfits search kar rahi hoon.';

        final replyMsg = ChatMessageModel(
          id: const Uuid().v4(),
          sessionId: _sessionId!,
          role: 'assistant',
          content: answerText,
          createdAt: DateTime.now(),
        );
        state = [...state, replyMsg];
        try {
          await _repo.sendMessage(replyMsg);
        } catch (_) {}

        var modifiedTrigger = pending.triggerJson;
        if (culturalChosen) {
          try {
            final decoded = jsonDecode(pending.triggerJson) as Map<String, dynamic>;
            decoded['ethnicity'] = pending.ethnicity;
            decoded['cultural_only'] = true;
            if (decoded['garment'] != null) {
              decoded['garment'] = '${pending.ethnicity} ${decoded['garment']}';
            } else {
              decoded['garment'] = '${pending.ethnicity} traditional outfit';
            }
            modifiedTrigger = jsonEncode(decoded);
          } catch (_) {}
        }

        await _performProductSearch(
          modifiedTrigger,
          '${pending.userMessage}. Cultural preference: ${culturalChosen ? "${pending.ethnicity} only" : "overall"}',
          pending.assistantMessage,
          skipValidation: true,
        );
        await loadSessions();
        return;
      }
    }

    if (_pendingSearchConfirmation != null && images.isEmpty) {
      final pending = _pendingSearchConfirmation!;
      final normalizedSize = _normalizeRequestedSize(messageText);
      if (_isConfirmation(messageText) || normalizedSize != null) {
        final confirmedSize =
            normalizedSize ??
            (_wantsProfileSize(messageText)
                ? pending.profileSize
                : pending.requestedSize);
        final prefs = {...pending.dynamicPrefs, 'size': confirmedSize};
        _pendingSearchConfirmation = null;
        final confirmMsg = ChatMessageModel(
          id: const Uuid().v4(),
          sessionId: _sessionId!,
          role: 'assistant',
          content:
              'Theek hai, main size $confirmedSize ke mutabiq search karti hoon.',
          createdAt: DateTime.now(),
        );
        state = [...state, confirmMsg];
        try {
          await _repo.sendMessage(confirmMsg);
        } catch (_) {}
        await _performProductSearch(
          jsonEncode(prefs),
          '${pending.userMessage}. Confirmed size $confirmedSize',
          pending.assistantMessage,
          skipValidation: true,
        );
        await loadSessions();
        return;
      }
    }

    // Get Gemini AI response with learned feedback from Loved Fits
    _isTyping = true;
    state = [...state]; // trigger rebuild for typing indicator

    final lovedNotifier = _ref.read(lovedFitsProvider.notifier);
    final learnedContext = lovedNotifier.getLearnedPreferencesContext();

    final aiText = await _repo.getAiResponse(
      _userId,
      messageText,
      chatContext: _buildChatContext(state),
      learnedPreferencesContext: learnedContext.isNotEmpty ? learnedContext : null,
      images: images
          .map(
            (image) =>
                ChatImageInput(bytes: image.bytes, mimeType: image.mimeType),
          )
          .toList(),
    );
    _isTyping = false;

    // ── Detect [SMARTFIT_SEARCH: {...}] trigger in AI response ──
    final searchMatch = _searchTriggerRegex.firstMatch(aiText);
    // Strip both complete triggers AND incomplete/truncated ones from display
    final displayText = aiText
        .replaceAll(_searchTriggerRegex, '')
        .replaceAll(_searchCleanupRegex, '')
        .trim();

    final aiMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content: displayText,
      createdAt: DateTime.now(),
    );
    state = [...state, aiMsg];
    try {
      await _repo.sendMessage(aiMsg);
    } catch (_) {}

    // ── If search was triggered, call the scraper backend ──
    if (searchMatch != null) {
      await _performProductSearch(
        searchMatch.group(1)!,
        messageText,
        displayText,
      );
    }

    await loadSessions();
  }

  /// Parse the Gemini trigger JSON and call the backend scraper.
  Future<void> _performProductSearch(
    String triggerJson,
    String userMessage,
    String assistantMessage, {
    bool skipValidation = false,
  }) async {
    Map<String, dynamic>? dynamicPrefs;
    try {
      dynamicPrefs = jsonDecode(triggerJson) as Map<String, dynamic>;
      debugPrint('[ChatProvider] Search trigger detected: $dynamicPrefs');
    } catch (e) {
      debugPrint('[ChatProvider] Failed to parse search trigger JSON: $e');
      return;
    }

    if (!skipValidation) {
      if (_culturalOnlyPreference == null) {
        final ethnicity = await _repo.getUserEthnicity(_userId);
        if (ethnicity != null &&
            ethnicity.trim().isNotEmpty &&
            ethnicity.toLowerCase() != 'other') {
          _pendingCultureConfirmation = _PendingCultureConfirmation(
            triggerJson: triggerJson,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            ethnicity: ethnicity,
          );
          final question = ChatMessageModel(
            id: const Uuid().v4(),
            sessionId: _sessionId!,
            role: 'assistant',
            content:
                'Aapne profile mein $ethnicity select kiya hai. Kya aapko $ethnicity traditional cultural outfits dekhne hain, ya overall general styles?',
            createdAt: DateTime.now(),
          );
          state = [...state, question];
          try {
            await _repo.sendMessage(question);
          } catch (_) {}
          return;
        }
      }

      final profileSize = await _repo.inferProfileSize(_userId);
      final requestedSize =
          _normalizeRequestedSize('${dynamicPrefs['size'] ?? ''}') ??
          _normalizeRequestedSize(userMessage);
      if (profileSize != null &&
          requestedSize != null &&
          profileSize != requestedSize) {
        _pendingSearchConfirmation = _PendingSearchConfirmation(
          dynamicPrefs: dynamicPrefs,
          userMessage: userMessage,
          assistantMessage: assistantMessage,
          profileSize: profileSize,
          requestedSize: requestedSize,
        );
        final question = ChatMessageModel(
          id: const Uuid().v4(),
          sessionId: _sessionId!,
          role: 'assistant',
          content:
              'Aapki profile ka size $profileSize hai, lekin chat mein aapne $requestedSize poocha. Kya aap $requestedSize chahte hain ya profile size $profileSize use karein?',
          createdAt: DateTime.now(),
        );
        state = [...state, question];
        try {
          await _repo.sendMessage(question);
        } catch (_) {}
        return;
      }
    }

    _isSearching = true;
    state = [...state]; // trigger rebuild for searching indicator

    try {
      final lovedNotifier = _ref.read(lovedFitsProvider.notifier);
      final learnedFeedback = lovedNotifier.getLearnedFeedbackSignals();

      final response = await _repo.searchProducts(
        userId: _userId,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        dynamicPrefs: dynamicPrefs,
        learnedFeedback: learnedFeedback.isNotEmpty ? learnedFeedback : null,
      );

      _isSearching = false;

      var finalResponse = response;
      if (_culturalOnlyPreference == true) {
        final ethnicity = await _repo.getUserEthnicity(_userId);
        if (ethnicity != null && ethnicity.isNotEmpty) {
          final ethLower = ethnicity.toLowerCase();
          final filtered = response.products.where((p) {
            final titleLower = p.title.toLowerCase();
            final brandLower = p.brand.toLowerCase();
            final categoryLower = (p.category ?? '').toLowerCase();
            final tagsString = p.tags.join(' ').toLowerCase();
            return titleLower.contains(ethLower) ||
                brandLower.contains(ethLower) ||
                categoryLower.contains(ethLower) ||
                tagsString.contains(ethLower) ||
                _isEthnicGarmentFor(ethLower, titleLower);
          }).toList();
          if (filtered.isNotEmpty) {
            finalResponse = response.copyWith(
              products: filtered,
              message: 'Yeh rahe aapke liye best $ethnicity cultural outfits:',
            );
          }
        }
      }

      if (finalResponse.products.isNotEmpty) {
        // Create a product carousel message
        final productMsg = ChatMessageModel(
          id: const Uuid().v4(),
          sessionId: _sessionId!,
          role: 'assistant',
          content: finalResponse.message,
          createdAt: DateTime.now(),
          metadata: {
            'products': finalResponse.products.map((p) => p.toJson()).toList(),
            'brands_searched': finalResponse.brandsSearched,
            'search_query': finalResponse.searchQuery,
            'source_urls': finalResponse.products
                .map((p) => p.productUrl)
                .where((url) => url.trim().isNotEmpty)
                .toList(),
          },
          products: finalResponse.products,
        );
        state = [...state, productMsg];
        try {
          await _repo.sendMessage(productMsg);
        } catch (_) {}
      } else {
        // No products found — show a helpful message
        final noResultMsg = ChatMessageModel(
          id: const Uuid().v4(),
          sessionId: _sessionId!,
          role: 'assistant',
          content: response.message.isNotEmpty
              ? response.message
              : "I searched the top Pakistani stores but couldn't find an exact match right now. Try describing a different style or garment type! 🔄",
          createdAt: DateTime.now(),
        );
        state = [...state, noResultMsg];
        try {
          await _repo.sendMessage(noResultMsg);
        } catch (_) {}
      }
    } catch (e) {
      _isSearching = false;
      debugPrint('[ChatProvider] Product search failed: $e');
      final errorMsg = ChatMessageModel(
        id: const Uuid().v4(),
        sessionId: _sessionId!,
        role: 'assistant',
        content:
            "Hmm, I couldn't reach the stores right now. Make sure the SmartFit backend is running and try again! 🔌",
        createdAt: DateTime.now(),
      );
      state = [...state, errorMsg];
      try {
        await _repo.sendMessage(errorMsg);
      } catch (_) {}
    }
  }
}

final chatNotifierProvider =
    StateNotifierProvider.family<ChatNotifier, List<ChatMessageModel>, String>((
      ref,
      userId,
    ) {
      return ChatNotifier(ref.watch(chatRepositoryProvider), userId, ref);
    });
