import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/chatbot/data/models/chat_message_model.dart';
import 'package:smartfit/features/chatbot/providers/chat_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// What the product search hears from the chat (18 Nov 2026: a budget given one
/// message before the search was lost and a PKR 232,000 sharara was shown).
void main() {
  var n = 0;
  ChatMessageModel msg(String role, String text, {bool withProducts = false}) => ChatMessageModel(
        id: '${n++}',
        sessionId: 's',
        role: role,
        content: text,
        createdAt: DateTime(2026, 11, 18),
        products: withProducts
            ? const [ProductRecommendation(id: 'p', brand: 'B', title: 'T', productUrl: 'https://b.pk/products/t')]
            : const [],
      );

  test("only the user's messages since the last results, never the stylist's", () {
    final chat = [
      msg('user', 'show me kurtas under 3000'),
      msg('assistant', 'Here are kurtas', withProducts: true),
      msg('user', 'now sharara please'),
      msg('assistant', 'Budget kitna hai? Most shararas are PKR 232,000'),
      msg('user', '10000'),
    ];
    expect(userTurnsSinceLastResults(chat), 'User: now sharara please\nUser: 10000');
  });

  test('a brand-new chat sends every user message so far', () {
    final chat = [msg('assistant', 'Hello!'), msg('user', 'sharara'), msg('user', 'budget 10k')];
    expect(userTurnsSinceLastResults(chat), 'User: sharara\nUser: budget 10k');
  });

  test('right after results there is nothing old to carry over', () {
    final chat = [msg('user', 'kurta under 3000'), msg('assistant', 'Here', withProducts: true)];
    expect(userTurnsSinceLastResults(chat), '');
  });

  group('SFR-016 / SFR-020: the chat body scan sets the size to search', () {
    const scan = ScanSummary(size: 'L');
    test('no size asked: the scan size is used', () {
      expect(withScanSize({'garment': 'kurta'}, scan), {'garment': 'kurta', 'size': 'L', 'size_source': 'body_scan'});
      expect(withScanSize({'garment': 'kurta', 'size': null}, scan)['size'], 'L');
      expect(withScanSize({'garment': 'kurta', 'size': 'null'}, scan)['size'], 'L');
    });
    test('a size the user asked for wins', () {
      expect(withScanSize({'size': 'M'}, scan), {'size': 'M'});
    });
    test('no scan (or no size in it): nothing changes', () {
      expect(withScanSize({'garment': 'kurta'}, null), {'garment': 'kurta'});
      expect(withScanSize({'garment': 'kurta'}, const ScanSummary()), {'garment': 'kurta'});
    });
  });
}
