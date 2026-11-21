import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/scoring/data/look_score_api_service.dart';
import 'package:smartfit/features/scoring/data/look_score_models.dart';

export 'package:smartfit/features/scoring/data/look_score_models.dart';

/// The hairstyle the user last chose (set by the Hairstyles screen). App-wide,
/// so it is still known when they score an outfit later.
final chosenHairstyleProvider = StateProvider<ChosenHairstyle?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id)); // per account: reset on sign-in / sign-out
  return null;
});

class LookScoreState {
  const LookScoreState({
    this.loading = false,
    this.result,
    this.failure,
    this.occasion,
    this.includeHairstyle = true,
    this.rating,
    this.ratingSent = false,
    this.detailsSent = false,
  });

  final bool loading;
  final LookScoreResult? result;
  final Failure? failure;
  final String? occasion;
  final bool includeHairstyle;
  final int? rating;
  final bool ratingSent;

  /// The optional "what's off" + comment (SFR-034) went with the rating.
  final bool detailsSent;

  LookScoreState copyWith({
    bool? loading,
    LookScoreResult? result,
    Failure? failure,
    String? occasion,
    bool clearOccasion = false,
    bool? includeHairstyle,
    int? rating,
    bool? ratingSent,
    bool? detailsSent,
  }) => LookScoreState(
    loading: loading ?? this.loading,
    result: result ?? this.result,
    failure: failure,
    occasion: clearOccasion ? null : (occasion ?? this.occasion),
    includeHairstyle: includeHairstyle ?? this.includeHairstyle,
    rating: rating ?? this.rating,
    ratingSent: ratingSent ?? this.ratingSent,
    detailsSent: detailsSent ?? this.detailsSent,
  );
}

final lookScoreControllerProvider = StateNotifierProvider.autoDispose
    .family<LookScoreController, LookScoreState, LookScoreArgs>((ref, args) => LookScoreController(ref, args));

class LookScoreController extends StateNotifier<LookScoreState> {
  LookScoreController(this._ref, this.args) : super(const LookScoreState()) {
    score();
  }

  final Ref _ref;
  final LookScoreArgs args;
  int _run = 0;

  /// (Re)score the look with the current occasion and hairstyle choice.
  Future<void> score() async {
    final run = ++_run;
    state = state.copyWith(loading: true);
    final uid = _ref.read(currentUserProvider)?.id;
    final profile = uid == null ? null : _ref.read(profileNotifierProvider(uid)).valueOrNull;
    final hairstyle = state.includeHairstyle ? _ref.read(chosenHairstyleProvider) : null;
    try {
      final result = await _ref
          .read(lookScoreApiServiceProvider)
          .score(look: args, profile: profile, hairstyle: hairstyle, occasion: state.occasion);
      if (!mounted || run != _run) return;
      // a new score is a new thing to rate
      state = LookScoreState(result: result, occasion: state.occasion, includeHairstyle: state.includeHairstyle);
    } on Failure catch (f) {
      if (!mounted || run != _run) return;
      state = state.copyWith(loading: false, failure: f);
    } catch (_) {
      if (!mounted || run != _run) return;
      state = state.copyWith(loading: false, failure: const UnknownFailure());
    }
  }

  void setOccasion(String? occasion) {
    if (occasion == state.occasion) return;
    state = occasion == null ? state.copyWith(clearOccasion: true) : state.copyWith(occasion: occasion);
    score();
  }

  void setIncludeHairstyle(bool include) {
    if (include == state.includeHairstyle) return;
    state = state.copyWith(includeHairstyle: include);
    score();
  }

  /// Send the user's 1..5 stars (SFR-034). Returns an error message, or null.
  Future<String?> rate(int stars) async {
    final result = state.result;
    if (result == null) return null;
    state = state.copyWith(rating: stars);
    try {
      await _ref
          .read(lookScoreApiServiceProvider)
          .rate(productId: args.product.key, rating: stars, result: result, occasion: state.occasion);
      if (mounted) state = state.copyWith(ratingSent: true);
      return null;
    } on Failure catch (f) {
      return f.message;
    } catch (_) {
      return 'Could not send your rating. Please try again.';
    }
  }

  /// SFR-034: after the stars, the parts the user says are wrong and their own words,
  /// saved with the same rating (it updates, never duplicates). Returns an error message, or null.
  Future<String?> sendDetails({List<String> corrections = const [], String? comment}) async {
    final result = state.result;
    final stars = state.rating;
    if (result == null || stars == null) return null;
    try {
      await _ref.read(lookScoreApiServiceProvider).rate(
            productId: args.product.key,
            rating: stars,
            result: result,
            occasion: state.occasion,
            corrections: corrections,
            comment: comment,
          );
      if (mounted) state = state.copyWith(detailsSent: true);
      return null;
    } on Failure catch (f) {
      return f.message;
    } catch (_) {
      return 'Could not send your feedback. Please try again.';
    }
  }
}
