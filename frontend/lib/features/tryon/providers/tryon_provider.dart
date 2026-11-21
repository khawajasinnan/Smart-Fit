import 'package:smartfit/core/providers/supabase_provider.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

enum TryOnPhase {
  /// Choosing the product and taking the photos.
  setup,

  /// The GPU is dressing the photos; the screen polls.
  running,

  /// At least one side finished: show the 2D / 360° result.
  result,

  /// SFR-027: this item can't be tried on (fabric, size). Show alternatives.
  unavailable,

  /// Something failed; [TryOnState.failure] says what and whether to retry.
  error,
}

/// The kind of garment in the user's own clothes photo (the try-on model needs it).
enum GarmentType {
  upper('upper', 'Top', 'Shirt, kurta, tee, jacket', needsChest: true, needsWaist: false),
  lower('lower', 'Bottom', 'Trousers, jeans, shalwar, skirt', needsChest: false, needsWaist: true),
  dress('dress', 'Full outfit', 'Dress, frock, suit, jumpsuit', needsChest: true, needsWaist: true);

  const GarmentType(this.id, this.label, this.examples, {required this.needsChest, required this.needsWaist});
  final String id;
  final String label;
  final String examples;

  /// Tape measurements needed to check the fit (the server's rule, shared/size_fit.py).
  final bool needsChest;
  final bool needsWaist;
}

/// Flat widths of a garment are accepted between these (cm); outside is a typo.
const kMinFlatWidthCm = 15.0;
const kMaxFlatWidthCm = 120.0;

/// A photo of the user's own clothes, tried on instead of a catalog product.
@immutable
class OwnGarment {
  const OwnGarment({required this.bytes, required this.type, this.name, this.chestWidthCm, this.waistWidthCm});

  final Uint8List bytes;
  final GarmentType type;

  /// Optional words that help the AI ("denim jacket").
  final String? name;

  /// Tape measurements of the garment laid flat, straight across (cm).
  final double? chestWidthCm;
  final double? waistWidthCm;

  String get title => (name == null || name!.trim().isEmpty) ? 'My ${type.label.toLowerCase()}' : name!.trim();
}

@immutable
class TryOnState {
  const TryOnState({
    this.product,
    this.ownGarment,
    this.spin360 = false,
    this.photos = const {},
    this.phase = TryOnPhase.setup,
    this.job,
    this.failure,
    this.savedToWardrobe = false,
  });

  /// A catalog product to try on, or null when [ownGarment] is used (never both).
  final ProductRecommendation? product;
  final OwnGarment? ownGarment;

  /// true: four photos (front, right, back, left) for the 360° view;
  /// false: front photo only.
  final bool spin360;
  final Map<TryOnAngle, Uint8List> photos;
  final TryOnPhase phase;
  final TryOnJob? job;
  final Failure? failure;
  final bool savedToWardrobe;

  List<TryOnAngle> get requiredAngles => spin360 ? TryOnAngle.values : const [TryOnAngle.front];

  /// Something to try on has been chosen (step 1 done).
  bool get hasGarment => product != null || ownGarment != null;

  /// Photos still needed before the try-on can start.
  int get missingPhotos => requiredAngles.where((a) => !photos.containsKey(a)).length;

  bool get readyToStart => hasGarment && missingPhotos == 0;

  /// 1 = choose clothes, 2 = add photos, 3 = creating / result.
  int get step => switch (phase) {
    TryOnPhase.setup => hasGarment ? 2 : 1,
    _ => 3,
  };

  TryOnState copyWith({
    ProductRecommendation? product,
    bool? spin360,
    Map<TryOnAngle, Uint8List>? photos,
    TryOnPhase? phase,
    TryOnJob? job,
    Failure? failure,
    bool clearFailure = false,
    bool clearJob = false,
    bool? savedToWardrobe,
  }) {
    return TryOnState(
      product: product ?? this.product,
      ownGarment: ownGarment,
      spin360: spin360 ?? this.spin360,
      photos: photos ?? this.photos,
      phase: phase ?? this.phase,
      job: clearJob ? null : (job ?? this.job),
      failure: clearFailure ? null : (failure ?? this.failure),
      savedToWardrobe: savedToWardrobe ?? this.savedToWardrobe,
    );
  }
}

/// Virtual try-on flow (SFR-026..028). Kept alive across tab switches so a
/// running job keeps polling while the user looks around the app.
class TryOnController extends StateNotifier<TryOnState> {
  TryOnController(this._api, {this.pollEvery = const Duration(seconds: 3)}) : super(const TryOnState());

  final TryOnApiService _api;
  final Duration pollEvery;
  Timer? _timer;
  int _pollErrors = 0;
  bool _polling = false;

  static const _maxPollErrors = 5; // ~15 s of lost connection before giving up

  void selectProduct(ProductRecommendation product) {
    _stopPolling();
    // Keep the photos: trying another item on the same photos is the common case.
    state = TryOnState(product: product, spin360: state.spin360, photos: state.photos);
  }

  /// Try on a photo of the user's own clothes instead of a catalog product.
  void selectOwnGarment(Uint8List bytes, GarmentType type, {String? name, double? chestWidthCm, double? waistWidthCm}) {
    _stopPolling();
    final cleanName = name?.trim();
    state = TryOnState(
      ownGarment: OwnGarment(
        bytes: bytes,
        type: type,
        name: (cleanName == null || cleanName.isEmpty) ? null : cleanName,
        chestWidthCm: type.needsChest ? chestWidthCm : null,
        waistWidthCm: type.needsWaist ? waistWidthCm : null,
      ),
      spin360: state.spin360,
      photos: state.photos,
    );
  }

  /// Back to step 1 (choose clothes). The user's photos are kept.
  void clearProduct() {
    _stopPolling();
    state = TryOnState(spin360: state.spin360, photos: state.photos);
  }

  void setSpin360(bool value) => state = state.copyWith(spin360: value);

  void setPhoto(TryOnAngle angle, Uint8List bytes) =>
      state = state.copyWith(photos: {...state.photos, angle: bytes}, clearFailure: true);

  void removePhoto(TryOnAngle angle) => state = state.copyWith(photos: {...state.photos}..remove(angle));

  /// Back to the photo step for the same product (after a result or an error).
  void backToSetup() {
    _stopPolling();
    state = state.copyWith(phase: TryOnPhase.setup, clearJob: true, clearFailure: true, savedToWardrobe: false);
  }

  void markSaved() => state = state.copyWith(savedToWardrobe: true);

  Future<void> start() async {
    final product = state.product;
    final own = state.ownGarment;
    if (!state.readyToStart || state.phase == TryOnPhase.running) return;
    final photos = {for (final a in state.requiredAngles) a: state.photos[a]!};
    state = state.copyWith(phase: TryOnPhase.running, clearJob: true, clearFailure: true, savedToWardrobe: false);
    try {
      final job = product != null
          ? await _api.start(productId: product.key, photos: photos)
          : await _api.start(
              garmentImage: own!.bytes,
              garmentCategory: own.type.id,
              garmentName: own.name,
              garmentChestWidthCm: own.chestWidthCm,
              garmentWaistWidthCm: own.waistWidthCm,
              photos: photos,
            );
      if (!mounted) return;
      _apply(job);
      if (job.isRunning) _startPolling(job.jobId);
    } on TryOnUnavailableFailure catch (f) {
      if (mounted) state = state.copyWith(phase: TryOnPhase.unavailable, failure: f);
    } on TryOnPhotoFailure catch (f) {
      if (!mounted) return;
      if (f.angle == 'garment') {
        // The clothes photo was rejected: back to step 1 with the reason shown.
        state = TryOnState(spin360: state.spin360, photos: state.photos, failure: f);
      } else {
        // Back to the photos, with the rejected side highlighted.
        state = state.copyWith(phase: TryOnPhase.setup, failure: f);
      }
    } on Failure catch (f) {
      if (mounted) state = state.copyWith(phase: TryOnPhase.error, failure: f);
    } catch (e) {
      debugPrint('[TryOn] start failed: $e');
      if (mounted) state = state.copyWith(phase: TryOnPhase.error, failure: const UnknownFailure());
    }
  }

  void _apply(TryOnJob job) {
    if (job.isRunning) {
      state = state.copyWith(phase: TryOnPhase.running, job: job);
      return;
    }
    _stopPolling();
    if (job.finishedViews.isNotEmpty) {
      state = state.copyWith(phase: TryOnPhase.result, job: job);
      return;
    }
    final firstError = job.views.where((v) => v.message != null).map((v) => v.message!).firstOrNull;
    state = state.copyWith(
      phase: TryOnPhase.error,
      job: job,
      failure: ServerFailure(firstError ?? "We couldn't make your try-on this time. Please try again."),
    );
  }

  void _startPolling(String jobId) {
    _stopPolling();
    _pollErrors = 0;
    _timer = Timer.periodic(pollEvery, (_) => _pollOnce(jobId));
  }

  Future<void> _pollOnce(String jobId) async {
    if (_polling) return; // a slow poll must not overlap the next one
    _polling = true;
    try {
      final job = await _api.poll(jobId);
      _pollErrors = 0;
      if (mounted && state.phase == TryOnPhase.running) _apply(job);
    } on Failure catch (f) {
      _pollErrors++;
      final expired = f.statusCode == 404;
      if (mounted && (expired || _pollErrors >= _maxPollErrors)) {
        _stopPolling();
        state = state.copyWith(phase: TryOnPhase.error, failure: f);
      }
    } finally {
      _polling = false;
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final tryOnControllerProvider = StateNotifierProvider<TryOnController, TryOnState>((ref) {
  // Body photos and results belong to one account: a different sign-in (or a
  // sign-out) starts from scratch, never with the previous user's photos.
  ref.watch(currentUserProvider.select((u) => u?.id));
  return TryOnController(ref.watch(tryOnApiServiceProvider));
});
