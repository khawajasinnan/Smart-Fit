import 'dart:convert';
import 'package:smartfit/features/chatbot/data/models/app_screen_link.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';

/// One shared chatbot client (keeps the running conversation history).
final chatbotApiServiceProvider = Provider<ChatbotApiService>(
  (ref) => ChatbotApiService(ref.watch(apiDioProvider)),
);

class ChatImageInput {
  final Uint8List bytes;
  final String mimeType;

  const ChatImageInput({required this.bytes, required this.mimeType});
}

/// The stylist's answer: text to show, plus the hidden product-search
/// trigger JSON when the stylist decided to search (SFR-022).
class ChatbotReply {
  const ChatbotReply({required this.text, this.searchRaw, this.mood, this.openScreen, this.isError = false});

  final String text;
  final String? searchRaw;

  /// The mascot's mood for this reply (`[MOOD: x]` from the stylist), if any.
  final String? mood;

  /// App-help answers: the screen Zayn offers a button to (`[SMARTFIT_OPEN: x]`).
  final AppScreenLink? openScreen;

  /// True when [text] is a connection / server problem message, not the stylist.
  final bool isError;

  factory ChatbotReply.fromJson(Map<String, dynamic> json) => ChatbotReply(
        text: (json['reply'] as String?) ?? '',
        searchRaw: json['search_raw'] as String?,
        mood: json['mood'] as String?,
        openScreen: AppScreenLink.fromKey(json['open'] as String?),
      );
}

/// AI stylist client (SFR-014..018).
///
/// The Gemini model, system prompt and API key now live in the backend
/// (backend/services/chat_orchestrator), so no AI key ships inside the app.
/// The backend is stateless: this client keeps the recent conversation and
/// sends it with every message.
class ChatbotApiService {
  ChatbotApiService(this._dio);

  final Dio _dio;
  final List<Map<String, String>> _history = [];

  static const int _historyLimit = 16;
  static const Duration _timeout = Duration(seconds: 75);

  Future<ChatbotReply> sendMessage(
    String userMessage, {
    List<ChatImageInput> images = const [],
    String? profileContext,
    String? chatContext,
  }) async {
    final payload = <String, dynamic>{
      'message': userMessage,
      'images': [
        for (final image in images)
          {'mime_type': image.mimeType, 'data_base64': base64Encode(image.bytes)},
      ],
      if (profileContext != null && profileContext.trim().isNotEmpty) 'profile_context': profileContext,
      if (chatContext != null && chatContext.trim().isNotEmpty) 'chat_context': chatContext,
      'history': List<Map<String, String>>.of(_history),
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.chatPath,
        data: payload,
        options: Options(receiveTimeout: _timeout),
      );
      final reply = ChatbotReply.fromJson(response.data ?? const {});
      _remember(userMessage, reply);
      return reply;
    } on DioException catch (e) {
      final failure = Failure.fromDio(e);
      debugPrint('[Chatbot] ${failure.runtimeType}: ${failure.message}');
      return ChatbotReply(text: _friendlyError(failure), isError: true);
    }
  }

  void _remember(String userMessage, ChatbotReply reply) {
    // Keep the model's own view of the turn, including its search trigger, so
    // follow-ups like "aur dikhao" (show more) work exactly as before.
    final modelText = reply.searchRaw == null ? reply.text : '${reply.text}\n[SMARTFIT_SEARCH: ${reply.searchRaw}]';
    _history
      ..add({'role': 'user', 'text': userMessage})
      ..add({'role': 'model', 'text': modelText});
    if (_history.length > _historyLimit) {
      _history.removeRange(0, _history.length - _historyLimit);
    }
  }

  String _friendlyError(Failure failure) => switch (failure) {
        RateLimitedFailure() => "I'm a bit busy right now — please wait about a minute and try again!",
        NetworkFailure() => 'Network error — check your internet connection and make sure the SmartFit API is running.',
        TimeoutFailure() => 'That took too long. Please try again.',
        _ => failure.message,
      };

  /// Reset the conversation (start a fresh chat session).
  void resetChat() => _history.clear();
}
