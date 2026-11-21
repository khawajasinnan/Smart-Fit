/// Dart mirror of the try-on service's job (backend shared/schemas/tryon.py).
///
/// One job = one product on 1-4 photos of the user, one per side. Each side
/// becomes an ordinary 2D try-on image (SRDS SFR-026); together they make the
/// drag-to-spin 360° view.
library;

/// The sides of the 360° turntable, in spin order.
enum TryOnAngle {
  front('front', 'Front', 'Face the camera, arms slightly away from your body.'),
  right('right', 'Right side', 'Turn a quarter to your left so your right side faces the camera.'),
  back('back', 'Back', 'Turn your back to the camera.'),
  left('left', 'Left side', 'Turn a quarter more so your left side faces the camera.');

  const TryOnAngle(this.id, this.label, this.instruction);
  final String id;
  final String label;
  final String instruction;

  static TryOnAngle? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

enum TryOnViewStatus { queued, running, done, failed }

/// The size check the server did before the try-on (SFR-025). A garment known
/// not to fit is never tried on, so a job is either "fits" or "unknown".
/// How the garment sits on the user. The try-on always runs; this is only
/// reported, so they can see it on themselves and decide.
enum TryOnFitStatus { fits, small, big, unknown }

class TryOnFit {
  const TryOnFit({required this.status, required this.note, this.size});

  final TryOnFitStatus status;
  final String note;
  final String? size;

  bool get fits => status == TryOnFitStatus.fits;

  /// The size is known to be off (too small or too big).
  bool get isWrongSize => status == TryOnFitStatus.small || status == TryOnFitStatus.big;

  static TryOnFit? fromJson(Object? json) {
    if (json is! Map) return null;
    return TryOnFit(
      status: switch (json['status']?.toString()) {
        'fits' => TryOnFitStatus.fits,
        'small' => TryOnFitStatus.small,
        'big' => TryOnFitStatus.big,
        _ => TryOnFitStatus.unknown,
      },
      note: json['note']?.toString() ?? '',
      size: json['size']?.toString(),
    );
  }
}

enum TryOnJobStatus { running, done, partial, failed }

class TryOnView {
  const TryOnView({
    required this.angle,
    required this.status,
    this.imageUrl,
    this.storagePath,
    this.errorCode,
    this.message,
    this.cached = false,
    this.fittingUrl,
  });

  final TryOnAngle angle;
  final TryOnViewStatus status;
  final String? imageUrl;
  final String? storagePath;
  final String? errorCode;
  final String? message;
  final bool cached;

  /// The cloth-warping preview: the garment fitted to the body outline (21 Nov 2026), made while
  /// the GPU works; null until ready or when it can't be made.
  final String? fittingUrl;

  bool get isDone => status == TryOnViewStatus.done && imageUrl != null;

  factory TryOnView.fromJson(Map<String, dynamic> json) => TryOnView(
    angle: TryOnAngle.fromId(json['angle'] as String?) ?? TryOnAngle.front,
    status: TryOnViewStatus.values.asNameMap()[json['status']] ?? TryOnViewStatus.failed,
    imageUrl: json['image_url'] as String?,
    storagePath: json['storage_path'] as String?,
    errorCode: json['error_code'] as String?,
    message: json['message'] as String?,
    cached: json['cached'] as bool? ?? false,
    fittingUrl: json['fitting_url'] as String?,
  );
}

class TryOnJob {
  const TryOnJob({
    required this.jobId,
    required this.status,
    required this.productId,
    required this.category,
    required this.views,
    required this.isTestMode,
    required this.modelVersion,
    required this.elapsedSeconds,
    required this.estimatedSeconds,
    this.fit,
  });

  final TryOnFit? fit;
  final String jobId;
  final TryOnJobStatus status;
  final String productId;
  final String category;
  final List<TryOnView> views;

  /// The backend ran in TEST MODE: the images are placeholders, not a real
  /// try-on. The app always says so.
  final bool isTestMode;
  final String modelVersion;
  final double elapsedSeconds;
  final int estimatedSeconds;

  bool get isRunning => status == TryOnJobStatus.running;

  List<TryOnView> get finishedViews => views.where((v) => v.isDone).toList();

  /// side -> storage path, for saving to the wardrobe.
  Map<String, String> get storagePaths => {
    for (final v in views)
      if (v.isDone && v.storagePath != null) v.angle.id: v.storagePath!,
  };

  /// 0..1 for the progress bar: finished views, plus elapsed time against the estimate.
  double get progress {
    if (views.isEmpty) return 0;
    final settled = views.where((v) => v.status == TryOnViewStatus.done || v.status == TryOnViewStatus.failed).length;
    final byViews = settled / views.length;
    final byTime = estimatedSeconds <= 0 ? 0.0 : (elapsedSeconds / estimatedSeconds).clamp(0.0, 0.95);
    return byViews > byTime ? byViews : byTime;
  }

  factory TryOnJob.fromJson(Map<String, dynamic> json) => TryOnJob(
    jobId: json['job_id'] as String? ?? '',
    status: TryOnJobStatus.values.asNameMap()[json['status']] ?? TryOnJobStatus.failed,
    productId: json['product_id'] as String? ?? '',
    category: json['category'] as String? ?? '',
    views: [
      for (final v in (json['views'] as List<dynamic>? ?? const []))
        TryOnView.fromJson(Map<String, dynamic>.from(v as Map)),
    ],
    isTestMode: json['mode'] == 'mock',
    modelVersion: json['model_version'] as String? ?? '',
    elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble() ?? 0,
    estimatedSeconds: (json['estimated_seconds'] as num?)?.toInt() ?? 0,
    fit: TryOnFit.fromJson(json['fit']),
  );
}
