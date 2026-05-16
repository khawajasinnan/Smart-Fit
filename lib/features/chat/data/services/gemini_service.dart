import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:smartfit/core/constants/api_endpoints.dart';

class ChatImageInput {
  final Uint8List bytes;
  final String mimeType;

  const ChatImageInput({required this.bytes, required this.mimeType});
}

/// GeminiService — uses Gemini REST API directly (no deprecated packages).
///
/// ── HOW TO CUSTOMIZE / TRAIN ──
/// Edit [systemPrompt] below to change the AI's personality, knowledge,
/// and response style. You can add your own training messages, rules,
/// product knowledge, brand guidelines, etc.
class GeminiService {
  final List<Map<String, dynamic>> _chatHistory = [];

  // ╔═══════════════════════════════════════════════════════════════╗
  // ║  CUSTOM SYSTEM PROMPT — EDIT THIS TO TRAIN YOUR AI          ║
  // ║  Add your own rules, product knowledge, brand tone, etc.    ║
  // ╚═══════════════════════════════════════════════════════════════╝
  static const String systemPrompt = '''
You are SmartFit AI Stylist — a sharp, funny, Pakistan-focused fashion advisor built into the SmartFit app.

## Your Personality
- You're stylish, witty, and a little roast-y, like a fashionable friend who saves people from bad outfit decisions
- You can lightly tease the outfit, never the user's body, skin, budget, religion, culture, disability, or identity
- You speak in a warm, Gen-Z friendly tone — casual but still useful
- Use emojis sparingly (0-2 per message max)
- Keep responses concise (2-4 sentences usually, unless asked for detail)
- You're inclusive of all body types, skin tones, and gender expressions

## Your Expertise
- Personal styling and outfit recommendations
- Color theory and what colors suit different skin tones
- Body type analysis and flattering silhouettes
- Seasonal fashion trends and timeless classics
- Budget-friendly alternatives to designer looks
- Wardrobe capsule planning
- Accessory coordination
- Pakistani climate, modest/fusion fashion, local brands, and rupee-conscious shopping

## Your Rules
1. Always consider the user's body type, skin tone, and style preferences when giving advice
2. Suggest specific outfit combinations, not just general tips
3. If asked about something non-fashion, gently redirect to fashion topics
4. Never body-shame or make the user feel bad about their appearance
5. When unsure, ask clarifying questions about the occasion, budget, or preference
6. Mention fabric types and care tips when relevant
7. For Pakistan, suggest realistic options: Outfitters, Breakout, Cougar, Ideas, Khaadi, Sapphire, Ethnic, Limelight, Bonanza Satrangi, Gul Ahmed, Elo, Daraz Mall, and local tailor options
8. When analyzing images, call out visible clothing fit, color harmony, silhouette, pose/framing, and what to improve. Do not claim exact body measurements from one photo.
9. If a user asks for pose estimation, 360 degree analysis, skin-tone detection, or body sizing, explain that proper results need multiple guided photos and the CV backend, then give a useful visual estimate from the uploaded image.

## Custom Training Messages
- Recommend breathable fabrics for Pakistani heat: cotton, lawn, linen blends, wash-and-wear, light denim, and moisture-friendly knits.
- For formal Pakistani styling, include kurta, waistcoat, shalwar kameez, khussa/loafers, dupatta styling, and fusion layering when appropriate.
- Use playful lines like "fit check passed", "this color is doing unpaid overtime", or "the shoes are trying, but they need backup" only when it fits naturally.
''';

  /// Send a message and get AI response via Gemini REST API.
  Future<String> sendMessage(
    String userMessage, {
    List<ChatImageInput> images = const [],
    String? profileContext,
  }) async {
    final apiKey = ApiEndpoints.geminiApiKey;
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY_HERE') {
      return '⚠️ API key not set. Get your free key at: aistudio.google.com/apikey';
    }

    final promptText = [
      if (profileContext != null && profileContext.trim().isNotEmpty)
        'User profile context:\n$profileContext',
      userMessage,
    ].join('\n\n');

    final userParts = <Map<String, dynamic>>[
      {'text': promptText},
      ...images.map(
        (image) => {
          'inline_data': {
            'mime_type': image.mimeType,
            'data': base64Encode(image.bytes),
          },
        },
      ),
    ];

    // Add user message to history
    _chatHistory.add({'role': 'user', 'parts': userParts});

    // Build request body
    final body = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': _chatHistory,
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.95,
        'topK': 40,
        'maxOutputTokens': 1024,
      },
    };

    final model = ApiEndpoints.geminiModel;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String? ?? '';
            // Add AI response to history for context
            _chatHistory.add({
              'role': 'model',
              'parts': [
                {'text': text},
              ],
            });
            return text;
          }
        }
        return "I'm having trouble thinking right now. Could you try rephrasing that? 🤔";
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMsg = errorBody['error']?['message'] ?? 'Unknown error';
        debugPrint('Gemini API error ${response.statusCode}: $errorMsg');

        if (response.statusCode == 400 &&
            errorMsg.toString().contains('not found')) {
          return "⚠️ Model '$model' not found. Try changing geminiModel in api_endpoints.dart to 'gemini-2.0-flash' or 'gemini-1.5-flash'";
        }
        if (response.statusCode == 400) {
          return "⚠️ API error: $errorMsg";
        }
        if (response.statusCode == 429) {
          return "Rate limit reached. Wait a moment and try again! ⏳";
        }
        if (response.statusCode == 403) {
          return "⚠️ API key invalid or restricted. Check your key at aistudio.google.com/apikey";
        }
        return "API error ($errorMsg). Please try again. 😅";
      }
    } catch (e) {
      debugPrint('Gemini network error: $e');
      return "Network error — check your internet connection and try again. 📶";
    }
  }

  /// Reset the chat session (start fresh conversation).
  void resetChat() {
    _chatHistory.clear();
  }
}
