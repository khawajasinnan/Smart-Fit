import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/recommendation/taste_profile.dart';

/// A product the AI stylist showed the user (for "did you like it?" notifications).
class ShownProduct {
  const ShownProduct(this.product, this.shownAt);

  final ProductRecommendation product;
  final DateTime shownAt;

  Map<String, dynamic> toJson() => {'product': product.toJson(), 'shown_at': shownAt.toIso8601String()};

  static ShownProduct? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final product = ProductRecommendation.fromJson(Map<String, dynamic>.from(json['product'] as Map));
      final at = DateTime.tryParse('${json['shown_at']}');
      return at == null ? null : ShownProduct(product, at);
    } catch (_) {
      return null;
    }
  }
}

class TasteFeedbackState {
  const TasteFeedbackState({this.disliked = const {}, this.votes = const {}, this.recent = const []});

  /// product key -> product the user said "not for me" to (oldest first)
  final Map<String, ProductRecommendation> disliked;

  /// quiz id -> choice
  final Map<String, String> votes;

  /// newest first, at most [TasteFeedbackNotifier.maxRecent]
  final List<ShownProduct> recent;

  bool isDisliked(ProductRecommendation p) => disliked.containsKey(p.key);

  TasteFeedbackState copyWith({
    Map<String, ProductRecommendation>? disliked,
    Map<String, String>? votes,
    List<ShownProduct>? recent,
  }) => TasteFeedbackState(
    disliked: disliked ?? this.disliked,
    votes: votes ?? this.votes,
    recent: recent ?? this.recent,
  );
}

/// "Not for me" and quiz answers for the signed-in user: Hive cache +
/// Supabase `user_feedback` (types 'disliked' and 'rating'), which the
/// offline dataset export reads (backend/scripts/export_feedback_dataset.py).
class TasteFeedbackNotifier extends StateNotifier<TasteFeedbackState> {
  TasteFeedbackNotifier(this._client, this._userId) : super(const TasteFeedbackState()) {
    if (_userId != null) _init();
  }

  final SupabaseClient? _client;
  final String? _userId;
  Box<String>? _box;

  static const maxRecent = 30;
  static const _dislikedType = 'disliked';
  static const _ratingType = 'rating';
  static const _nope = 'nope:';
  static const _vote = 'vote:';
  static const _recentKey = 'recent';
  static const quizPrefix = 'quiz:';

  String get _boxName => 'smartfit_taste_$_userId';

  Future<void> _init() async {
    try {
      _box = Hive.isBoxOpen(_boxName) ? Hive.box<String>(_boxName) : await Hive.openBox<String>(_boxName);
      final disliked = <String, ProductRecommendation>{};
      final votes = <String, String>{};
      var recent = <ShownProduct>[];
      for (final key in _box!.keys.cast<String>()) {
        final raw = _box!.get(key);
        if (raw == null) continue;
        try {
          if (key.startsWith(_nope)) {
            disliked[key.substring(_nope.length)] =
                ProductRecommendation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          } else if (key.startsWith(_vote)) {
            votes[key.substring(_vote.length)] = raw;
          } else if (key == _recentKey) {
            recent = (jsonDecode(raw) as List).map(ShownProduct.fromJson).whereType<ShownProduct>().toList();
          }
        } catch (_) {
          // skip unreadable cache entries
        }
      }
      if (mounted) state = TasteFeedbackState(disliked: disliked, votes: votes, recent: recent);
    } catch (e) {
      debugPrint('[TasteFeedback] init error: $e');
    }
    await _syncFromSupabase();
  }

  Future<void> _syncFromSupabase() async {
    final client = _client;
    if (client == null || _userId == null) return;
    try {
      final rows = await client
          .from(ApiEndpoints.userFeedbackTable)
          .select('product_id, feedback_type, feedback_data')
          .eq('user_id', _userId)
          .inFilter('feedback_type', [_dislikedType, _ratingType]);
      final disliked = {...state.disliked};
      final votes = {...state.votes};
      for (final row in rows) {
        final data = row['feedback_data'];
        if (data is! Map) continue;
        final json = Map<String, dynamic>.from(data);
        if (row['feedback_type'] == _dislikedType) {
          final key = row['product_id'] as String?;
          if (key == null || disliked.containsKey(key)) continue;
          try {
            disliked[key] = ProductRecommendation.fromJson(json);
            await _box?.put('$_nope$key', jsonEncode(disliked[key]!.toJson()));
          } catch (_) {}
        } else if (json['quiz'] is String && json['choice'] is String && !votes.containsKey(json['quiz'])) {
          votes[json['quiz'] as String] = json['choice'] as String;
          await _box?.put('$_vote${json['quiz']}', json['choice'] as String);
        }
      }
      if (mounted) state = state.copyWith(disliked: disliked, votes: votes);
    } catch (e) {
      // offline, or not signed in to Supabase in tests
      debugPrint('[TasteFeedback] sync error: $e');
    }
  }

  /// "Not for me" on (or undo). [source] is 'app' or 'notification'.
  Future<void> setDisliked(ProductRecommendation product, bool disliked, {String source = 'app'}) async {
    final key = product.key;
    if (disliked == state.disliked.containsKey(key)) return;
    final next = {...state.disliked};
    if (disliked) {
      next[key] = product;
    } else {
      next.remove(key);
    }
    if (mounted) state = state.copyWith(disliked: next);
    try {
      disliked ? await _box?.put('$_nope$key', jsonEncode(product.toJson())) : await _box?.delete('$_nope$key');
    } catch (_) {}
    final client = _client;
    if (client == null || _userId == null) return;
    try {
      final table = client.from(ApiEndpoints.userFeedbackTable);
      if (disliked) {
        await table.upsert({
          'user_id': _userId,
          'product_id': key,
          'feedback_type': _dislikedType,
          'feedback_data': {...product.toJson(), 'source': source},
        }, onConflict: 'user_id,product_id,feedback_type');
      } else {
        await table.delete().eq('user_id', _userId).eq('product_id', key).eq('feedback_type', _dislikedType);
      }
    } catch (e) {
      debugPrint('[TasteFeedback] remote "not for me" failed: $e');
    }
  }

  /// A style-quiz answer (from the app or a notification button).
  Future<void> vote(String quizId, String choice, {String source = 'app'}) async {
    if (quizById(quizId) == null) return;
    if (mounted) state = state.copyWith(votes: {...state.votes, quizId: choice});
    try {
      await _box?.put('$_vote$quizId', choice);
    } catch (_) {}
    final client = _client;
    if (client == null || _userId == null) return;
    try {
      await client.from(ApiEndpoints.userFeedbackTable).upsert({
        'user_id': _userId,
        'product_id': '$quizPrefix$quizId',
        'feedback_type': _ratingType,
        'feedback_data': {'quiz': quizId, 'choice': choice, 'source': source},
      }, onConflict: 'user_id,product_id,feedback_type');
    } catch (e) {
      debugPrint('[TasteFeedback] remote vote failed: $e');
    }
  }

  /// Remember products the stylist just showed (newest first, deduplicated).
  Future<void> recordShown(List<ProductRecommendation> products, {DateTime? at}) async {
    if (products.isEmpty) return;
    final when = at ?? DateTime.now();
    final keys = products.map((p) => p.key).toSet();
    final recent = [
      for (final p in products) ShownProduct(p, when),
      ...state.recent.where((s) => !keys.contains(s.product.key)),
    ].take(maxRecent).toList();
    if (mounted) state = state.copyWith(recent: recent);
    try {
      await _box?.put(_recentKey, jsonEncode(recent.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }
}

final tasteFeedbackProvider = StateNotifierProvider<TasteFeedbackNotifier, TasteFeedbackState>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  SupabaseClient? client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    client = null; // Supabase not initialised (tests)
  }
  return TasteFeedbackNotifier(client, userId);
});

/// One place for every kind of feedback, so love and "not for me" stay
/// mutually exclusive and everything feeds the same taste profile.
class FeedbackActions {
  FeedbackActions(this._ref);

  final Ref _ref;

  LovedFitsNotifier get _loved => _ref.read(lovedFitsProvider.notifier);
  TasteFeedbackNotifier get _taste => _ref.read(tasteFeedbackProvider.notifier);

  /// Toggle Love Fit; returns true if the product is now loved.
  Future<bool> toggleLove(ProductRecommendation product, {String source = 'app'}) async {
    final loved = !_loved.isLoved(product);
    await setLoved(product, loved, source: source);
    return loved;
  }

  Future<void> setLoved(ProductRecommendation product, bool loved, {String source = 'app'}) async {
    if (loved) await _taste.setDisliked(product, false);
    await _loved.setLoved(product, loved, source: source);
  }

  Future<void> notForMe(ProductRecommendation product, {String source = 'app'}) async {
    await _loved.setLoved(product, false);
    await _taste.setDisliked(product, true, source: source);
  }

  Future<void> undoNotForMe(ProductRecommendation product) => _taste.setDisliked(product, false);

  Future<void> vote(String quizId, String choice, {String source = 'app'}) =>
      _taste.vote(quizId, choice, source: source);

  /// The `taste` sent with every recommendation request.
  Map<String, dynamic>? tasteProfile() {
    final taste = _ref.read(tasteFeedbackProvider);
    return buildTasteProfile(
      loved: _loved.lovedProducts,
      disliked: taste.disliked.values.toList(),
      votes: taste.votes,
    );
  }
}

final feedbackActionsProvider = Provider<FeedbackActions>(FeedbackActions.new);
