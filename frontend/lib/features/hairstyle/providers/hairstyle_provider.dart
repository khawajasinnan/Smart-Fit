import 'package:smartfit/core/providers/supabase_provider.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_api_service.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';

enum HairstylePhase { intro, analysing, result, error }

class HairstyleState {
  const HairstyleState({
    this.phase = HairstylePhase.intro,
    this.photo,
    this.result,
    this.selected = 0,
    this.showOriginal = false,
    this.failure,
    this.occasion,
    this.hairTexture,
  });

  final HairstylePhase phase;
  final Uint8List? photo;
  final HairstyleResult? result;

  /// Index into result.styles (0 = the best match).
  final int selected;

  /// Before / after: show the photo without the new hairstyle.
  final bool showOriginal;
  final Failure? failure;

  /// Optional: favours styles that suit it (e.g. "mehndi", "office").
  final String? occasion;

  /// The user's own hair as they describe it: "straight" / "wavy"; null = let SmartFit estimate.
  final String? hairTexture;

  HairstylePreview? get current {
    final styles = result?.styles ?? const [];
    return selected < styles.length ? styles[selected] : null;
  }

  /// The server refused the photo itself (face check): retake it, don't retry it.
  bool get photoProblem => failure is ValidationFailure;

  HairstyleState copyWith({
    HairstylePhase? phase,
    Uint8List? photo,
    HairstyleResult? result,
    int? selected,
    bool? showOriginal,
    Failure? failure,
    String? occasion,
    bool clearOccasion = false,
    String? hairTexture,
    bool clearHairTexture = false,
  }) => HairstyleState(
    phase: phase ?? this.phase,
    photo: photo ?? this.photo,
    result: result ?? this.result,
    selected: selected ?? this.selected,
    showOriginal: showOriginal ?? this.showOriginal,
    failure: failure,
    occasion: clearOccasion ? null : (occasion ?? this.occasion),
    hairTexture: clearHairTexture ? null : (hairTexture ?? this.hairTexture),
  );
}

/// The outfit the hairstyles should go with (SFR-029): set by the try-on's
/// "Find a matching hairstyle", cleared from the Hair tab. Per account.
final hairstyleOutfitProvider = StateProvider<ProductRecommendation?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return null;
});

final hairstyleControllerProvider = StateNotifierProvider.autoDispose<HairstyleController, HairstyleState>((ref) {
  // the face photo belongs to one account; the Hair tab stays alive, so reset on a new sign-in
  ref.watch(currentUserProvider.select((u) => u?.id));
  return HairstyleController(
    ref.watch(hairstyleApiServiceProvider),
    // remember the style on show for the look score (SFR-032), which outlives this screen
    onChoice: (choice) => ref.read(chosenHairstyleProvider.notifier).state = choice,
    outfitText: () {
      final outfit = ref.read(hairstyleOutfitProvider);
      return outfit == null ? null : [outfit.title, ?outfit.category].join(', ');
    },
  );
});

class HairstyleController extends StateNotifier<HairstyleState> {
  HairstyleController(this._api, {this.onChoice, this.outfitText}) : super(const HairstyleState());

  /// The chosen outfit's name and type, if the user came from a try-on (SFR-029).
  final String? Function()? outfitText;

  final HairstyleApiService _api;

  /// Told about the hairstyle currently chosen, whenever it changes.
  final void Function(ChosenHairstyle choice)? onChoice;

  void _reportChoice() {
    final style = state.current;
    final result = state.result;
    if (style == null || result == null) return;
    onChoice?.call(ChosenHairstyle(
      id: style.id,
      name: style.name,
      score: style.score,
      faceShape: result.faceShape,
      thumbBase64: style.thumbBase64,
    ));
  }

  int _run = 0;

  /// Face shape + hairstyle previews for [photo] (from the camera or the gallery).
  Future<void> analyse(Uint8List photo, {String? gender}) async {
    final run = ++_run;
    _gender = gender;
    state = HairstyleState(
      phase: HairstylePhase.analysing,
      photo: photo,
      occasion: state.occasion,
      hairTexture: state.hairTexture,
    );
    try {
      final result = await _api.suggest(
        photo,
        gender: gender,
        occasion: state.occasion,
        hairTexture: state.hairTexture,
        outfit: outfitText?.call(),
      );
      if (!mounted || run != _run) return;
      if (result.styles.isEmpty) {
        state = state.copyWith(
          phase: HairstylePhase.error,
          failure: const UnknownFailure('No hairstyles came back. Please try again.'),
        );
        return;
      }
      state = HairstyleState(
        phase: HairstylePhase.result,
        photo: photo,
        result: result,
        occasion: state.occasion,
        hairTexture: state.hairTexture,
      );
      _reportChoice();
    } on Failure catch (f) {
      if (!mounted || run != _run) return;
      state = state.copyWith(phase: HairstylePhase.error, failure: f);
    } catch (_) {
      if (!mounted || run != _run) return;
      state = state.copyWith(phase: HairstylePhase.error, failure: const UnknownFailure());
    }
  }

  void select(int index) {
    final n = state.result?.styles.length ?? 0;
    if (index < 0 || index >= n) return;
    state = state.copyWith(selected: index, showOriginal: false);
    _reportChoice();
  }

  void toggleOriginal(bool show) => state = state.copyWith(showOriginal: show);

  String? _gender;

  /// Choose an occasion (null = none); re-runs the suggestions if there is a photo already.
  Future<void> setOccasion(String? occasion) async {
    if (occasion == state.occasion) return;
    state = occasion == null ? state.copyWith(clearOccasion: true) : state.copyWith(occasion: occasion);
    await _rerun();
  }

  /// The user's own hair texture ("straight" / "wavy"; null = let SmartFit guess).
  Future<void> setHairTexture(String? texture) async {
    if (texture == state.hairTexture) return;
    state = texture == null ? state.copyWith(clearHairTexture: true) : state.copyWith(hairTexture: texture);
    await _rerun();
  }

  Future<void> _rerun() async {
    final photo = state.photo;
    if (photo != null && state.phase == HairstylePhase.result) await analyse(photo, gender: _gender);
  }

  void reset() {
    _run++;
    // keep the choices the user made; drop the photo and results
    state = HairstyleState(occasion: state.occasion, hairTexture: state.hairTexture);
  }
}
