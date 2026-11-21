import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/features/chatbot/data/models/app_screen_link.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_mood.dart';
import 'package:smartfit/features/chatbot/data/models/chat_message_model.dart';
import 'package:smartfit/features/chatbot/data/repositories/chat_repository.dart';
import 'package:smartfit/features/chatbot/data/services/chatbot_api_service.dart';
import 'package:smartfit/features/recommendation/data/services/scraper_api_service.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/recommendation/providers/taste_feedback_provider.dart';
import 'package:smartfit/features/recommendation/taste_profile.dart';
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

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(chatbotApiServiceProvider),
    ref.watch(scraperApiServiceProvider),
  );
});

// ── Safety net: the backend already strips the [SMARTFIT_SEARCH: …] trigger
// from the reply. If any fragment ever slips through, hide it from the user.
// (The previous pattern used `[^]]`, which in Dart means "any character" and
// leaked truncated triggers.)
final _searchCleanupRegex = RegExp(r'\[SMARTFIT_SEARCH.*$', dotAll: true);

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

/// The search preferences with this chat's body-scan size (SFR-016 / SFR-020) when
/// the user didn't name a size: the session's own analysis comes before the profile.
Map<String, dynamic> withScanSize(Map<String, dynamic> prefs, ScanSummary? scan) {
  final asked = '${prefs['size'] ?? ''}'.trim();
  final scanned = scan?.size?.trim() ?? '';
  if ((asked.isNotEmpty && asked.toLowerCase() != 'null') || scanned.isEmpty) return prefs;
  return {...prefs, 'size': scanned, 'size_source': 'body_scan'};
}

/// The user's own messages since the last product results, as "User: ..."
/// lines: the details of the current request (a budget answered one message
/// earlier must not be lost; an old request's budget must not leak in, and the
/// stylist's replies, which quote prices, are never included).
String userTurnsSinceLastResults(List<ChatMessageModel> messages) {
  final lastResults = messages.lastIndexWhere((m) => m.role == 'assistant' && m.products.isNotEmpty);
  return messages
      .skip(lastResults + 1)
      .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
      .map((m) => 'User: ${m.content.trim()}')
      .join('\n');
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
  String? _scanContext; // latest body & face scan in this chat, briefed to the stylist
  List<ChatSessionModel> _sessions = [];

  ChatNotifier(this._repo, this._userId, this._ref) : super([]);

  bool get isTyping => _isTyping;
  bool get isSearching => _isSearching;
  bool get isLoadingSessions => _isLoadingSessions;
  String? get sessionId => _sessionId;
  List<ChatSessionModel> get sessions => _sessions;

  /// [announce] false: the screen greets the user itself (by name, aloud).
  Future<void> startSession({bool fresh = false, bool announce = true}) async {
    if (_sessionId != null && !fresh) return;
    _culturalOnlyPreference = null;
    _pendingCultureConfirmation = null;
    _pendingSearchConfirmation = null;
    _scanContext = null;
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
          "Hello! Main hoon Zayn, aapka SmartFit AI Stylist. Aap mujhse kisi bhi outfit, styling tips, ya shopping ke baare mein pooch sakte hain. Apni photo bheinjen fit check ke liye, ya bataen aaj aapko kis type ka look chahiye!",
      createdAt: DateTime.now(),
    );
    state = [welcome];
    if (announce) _zayn(ZaynMood.hello);
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
        _scanContext = _latestScan(messages)?.stylistContext;
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

  /// Zayn, the mascot, reacts to what just happened in the chat (spec §23.14).
  /// The learned taste profile (spec §23.15); never breaks the chat.
  Map<String, dynamic>? _taste() {
    try {
      return _ref.read(feedbackActionsProvider).tasteProfile();
    } catch (e) {
      debugPrint('[Chat] taste profile unavailable: $e');
      return null;
    }
  }

  String _tasteText() => tasteProfileText(_taste());

  void _zayn(ZaynMood mood, {String? quip, Duration? hold = ZaynController.defaultHold}) {
    try {
      _ref.read(zaynProvider.notifier).react(mood, quip: quip, hold: hold);
    } catch (_) {
      // the mascot must never break the chat
    }
  }

  static ScanSummary? _latestScan(List<ChatMessageModel> messages) {
    for (final m in messages.reversed) {
      if (m.metadata?['type'] == ScanSummary.metadataType) return ScanSummary.fromMap(m.metadata!);
    }
    return null;
  }

  /// Adds the body & face scan results as a chat card and briefs the stylist
  /// with them for the rest of this chat.
  Future<void> addBodyScan(ScanSummary scan) async {
    if (_sessionId == null) await startSession();
    final msg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content: ['Body & face scan', ...scan.lines].join('\n'),
      metadata: scan.toMap(),
      createdAt: DateTime.now(),
    );
    _scanContext = scan.stylistContext;
    state = [...state, msg];
    _zayn(ZaynMood.proud);
    try {
      await _repo.sendMessage(msg);
    } catch (e) {
      debugPrint('Failed to save body scan message: $e');
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
            ? 'Theek hai! Main sirf ${pending.ethnicity} cultural aur traditional outfits par focus kar raha hoon.'
            : 'Theek hai! Main overall trendy outfits search kar raha hoon.';

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
              'Theek hai, main size $confirmedSize ke mutabiq search karta hoon.',
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
    _zayn(ZaynMood.thinking, hold: null);

    final lovedNotifier = _ref.read(lovedFitsProvider.notifier);
    final learnedContext = [
      lovedNotifier.getLearnedPreferencesContext(),
      _tasteText(),
      ?_scanContext,
    ].where((c) => c.trim().isNotEmpty).join('\n\n');

    final reply = await _repo.getAiResponse(
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
    if (reply.isError) {
      _zayn(ZaynMood.confused, quip: 'Hmm, connection mein masla hai. Phir try karein?');
    } else {
      // A product search (if any) switches Zayn to "thinking" next; if the
      // search asks a question first, the reply's mood stays and times out.
      _zayn(ZaynMood.fromName(reply.mood) ?? ZaynMood.happy);
    }

    // The backend returns the search trigger separately from the display text.
    final searchJson = reply.searchRaw;
    final displayText = reply.text.replaceAll(_searchCleanupRegex, '').trim();

    // An app-help answer ("where is the try-on?") can carry a button to that
    // screen; a product answer never does (its products are the answer).
    final openScreen = searchJson == null ? reply.openScreen : null;
    final aiMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _sessionId!,
      role: 'assistant',
      content: displayText,
      metadata: openScreen == null ? null : {AppScreenLink.metadataKey: openScreen.key},
      createdAt: DateTime.now(),
    );
    state = [...state, aiMsg];
    try {
      await _repo.sendMessage(aiMsg);
    } catch (_) {}

    // ── If search was triggered, call the scraper backend ──
    if (searchJson != null) {
      await _performProductSearch(
        searchJson,
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

    // SFR-016 / SFR-020: this chat's body scan (camera, gallery or profile photo) sets the size
    // to search when the user hasn't named one.
    dynamicPrefs = withScanSize(dynamicPrefs, _latestScan(state));

    _isSearching = true;
    state = [...state]; // trigger rebuild for searching indicator
    _zayn(ZaynMood.thinking, quip: 'Pakistani stores check kar raha hoon...', hold: null);

    try {
      final response = await _repo.searchProducts(
        userId: _userId,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        // what the user said for THIS request (e.g. "10000" answering "Budget kitna hai?")
        chatContext: userTurnsSinceLastResults(state),
        dynamicPrefs: dynamicPrefs,
        taste: _taste(),
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
        _zayn(ZaynMood.excited);
        try {
          // remembered for Zayn's "did you like it?" notifications
          await _ref.read(tasteFeedbackProvider.notifier).recordShown(finalResponse.products);
        } catch (_) {}
        try {
          await _repo.sendMessage(productMsg);
        } catch (_) {}
        final count = finalResponse.products.length;
        _ref.read(notificationNotifierProvider.notifier).notify(
              NotificationKind.recommendationsReady,
              title: 'Your outfits are ready 👗',
              body: '$count ${count == 1 ? 'pick' : 'picks'} matched your profile. Tap to see them.',
              route: '/chat',
            );
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
        _zayn(ZaynMood.sad);
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
      _zayn(ZaynMood.confused, quip: 'Stores tak nahi pohnch saki. Thori der baad try karein?');
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
