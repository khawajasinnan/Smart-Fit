import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// Learning from feedback (spec §23.15). Everything the user tells us,
/// in the app or from a notification, becomes one taste profile:
///   * Love Fit         -> liked brands / colours / types, price point
///   * "Not for me"     -> never show that product again; repeated misses
///                         (2+) on a brand, colour or type push it down
///   * style quiz votes -> Eastern/Western lean, palette, budget
/// The backend uses it to re-rank (TasteProfile in recommendation.py);
/// the AI stylist gets the same facts as text.

class TasteQuiz {
  const TasteQuiz({required this.id, required this.question, required this.a, required this.b});

  final String id;
  final String question;

  /// (stored choice, button label)
  final (String, String) a;
  final (String, String) b;

  String labelFor(String choice) => choice == a.$1 ? a.$2 : (choice == b.$1 ? b.$2 : choice);
}

const tasteQuizzes = <TasteQuiz>[
  TasteQuiz(
    id: 'eastern_western',
    question: 'Quick vibe check, bestie: Eastern or Western? 👀',
    a: ('eastern', 'Eastern ✨'),
    b: ('western', 'Western 😎'),
  ),
  TasteQuiz(
    id: 'palette',
    question: 'Soft pastels or loud and bold colours? Be honest 💅',
    a: ('pastels', 'Pastels 🌸'),
    b: ('bold', 'Bold 🔥'),
  ),
  TasteQuiz(
    id: 'budget',
    question: 'Shopping mood this week: smart saver or full splurge? 💸',
    a: ('under5k', 'Under 5k 🤑'),
    b: ('splurge', 'Splurge 💎'),
  ),
];

TasteQuiz? quizById(String id) {
  for (final q in tasteQuizzes) {
    if (q.id == id) return q;
  }
  return null;
}

const _paletteColors = {
  'pastels': ['pastel', 'pink', 'mint', 'lilac', 'peach', 'sky blue', 'beige'],
  'bold': ['red', 'black', 'maroon', 'royal blue', 'emerald', 'mustard', 'fuchsia'],
};
const _budgetPricePoint = {'under5k': 4000, 'splurge': 12000};

/// Keep at most this many of each list (the backend allows 20).
const _topN = 5;

/// Repeated "not for me" needed before a whole brand/colour/type is pushed
/// down: one miss is about that product, not the brand.
const dislikeThreshold = 2;

List<String> _ranked(Iterable<String> values, {int minCount = 1}) {
  final freq = <String, int>{};
  for (final v in values) {
    final k = v.trim().toLowerCase();
    if (k.isNotEmpty) freq[k] = (freq[k] ?? 0) + 1;
  }
  final keys = freq.keys.where((k) => freq[k]! >= minCount).toList()
    ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
  return keys.take(_topN).toList();
}

/// The `taste` object for POST /recommend/app, or null if we know nothing yet.
Map<String, dynamic>? buildTasteProfile({
  required List<ProductRecommendation> loved,
  required List<ProductRecommendation> disliked,
  required Map<String, String> votes,
}) {
  final likedBrands = _ranked(loved.map((p) => p.brand));
  final likedColors = _ranked(loved.expand((p) => p.colors));
  final likedCategories = _ranked(loved.map((p) => p.category ?? ''));
  for (final c in _paletteColors[votes['palette']] ?? const <String>[]) {
    if (likedColors.length < _topN + 3 && !likedColors.contains(c)) likedColors.add(c);
  }

  final dislikedBrands = _ranked(disliked.map((p) => p.brand), minCount: dislikeThreshold)
      .where((b) => !likedBrands.contains(b))
      .toList();
  final dislikedColors = _ranked(disliked.expand((p) => p.colors), minCount: dislikeThreshold)
      .where((c) => !likedColors.contains(c))
      .toList();
  final dislikedCategories = _ranked(disliked.map((p) => p.category ?? ''), minCount: dislikeThreshold)
      .where((c) => !likedCategories.contains(c))
      .toList();

  final lean = votes['eastern_western'];
  int? pricePoint = _budgetPricePoint[votes['budget']];
  if (pricePoint == null) {
    final prices = loved.map((p) => p.pricePkr).whereType<int>().where((p) => p > 0).toList();
    if (prices.isNotEmpty) pricePoint = (prices.reduce((a, b) => a + b) / prices.length).round();
  }

  // Newest rejections first; the backend accepts up to 500 ids.
  final excluded = <String>{};
  for (final p in disliked.reversed) {
    if (p.id.isNotEmpty) excluded.add(p.id);
    if (p.productUrl.isNotEmpty) excluded.add(p.productUrl);
    if (excluded.length >= 498) break;
  }

  final taste = <String, dynamic>{
    if (likedBrands.isNotEmpty) 'liked_brands': likedBrands,
    if (dislikedBrands.isNotEmpty) 'disliked_brands': dislikedBrands,
    if (likedColors.isNotEmpty) 'liked_colors': likedColors,
    if (dislikedColors.isNotEmpty) 'disliked_colors': dislikedColors,
    if (likedCategories.isNotEmpty) 'liked_categories': likedCategories,
    if (dislikedCategories.isNotEmpty) 'disliked_categories': dislikedCategories,
    if (lean == 'eastern' || lean == 'western') 'style_lean': lean,
    'price_point': ?pricePoint,
    if (excluded.isNotEmpty) 'excluded_product_ids': excluded.toList(),
  };
  return taste.isEmpty ? null : taste;
}

/// The same facts for the AI stylist's prompt.
String tasteProfileText(Map<String, dynamic>? taste) {
  if (taste == null || taste.isEmpty) return '';
  String? joined(String key) {
    final values = (taste[key] as List?)?.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    return values == null || values.isEmpty ? null : values.join(', ');
  }

  final lines = <String>[
    if (joined('liked_brands') case final v?) '- Brands they loved: $v',
    if (joined('liked_colors') case final v?) '- Colours they like: $v',
    if (joined('liked_categories') case final v?) '- Garment types they loved: $v',
    if (joined('disliked_brands') case final v?) '- Brands they keep rejecting: $v',
    if (joined('disliked_colors') case final v?) '- Colours they keep rejecting: $v',
    if (joined('disliked_categories') case final v?) '- Garment types they keep rejecting: $v',
    if (taste['style_lean'] case final String lean) '- Style lean (their quiz answer): $lean',
    if (taste['price_point'] case final int p) '- Comfortable price point: around PKR $p',
    if ((taste['excluded_product_ids'] as List?)?.isNotEmpty ?? false)
      '- They said "not for me" to some products; never suggest those exact items again.',
  ];
  if (lines.isEmpty) return '';
  return ['User taste learned from their feedback:', ...lines,
    'Lean towards what they like, away from what they reject, unless they ask otherwise.'].join('\n');
}
