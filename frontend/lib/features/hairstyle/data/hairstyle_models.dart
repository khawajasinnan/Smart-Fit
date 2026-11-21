import 'dart:convert';
import 'dart:typed_data';

/// The circle drawn over the camera preview (and sent with each frame): centre
/// as fractions of the frame width/height, radius as a fraction of the width.
class GuideCircle {
  const GuideCircle({required this.cx, required this.cy, required this.r});

  /// The standard circle for a frame of [width] x [height]: centred a little
  /// above the middle, sized to 30 % of the frame's shorter side, so it fits
  /// a portrait phone and a landscape webcam alike.
  factory GuideCircle.forFrame(double width, double height) {
    final shorter = width < height ? width : height;
    return GuideCircle(cx: 0.5, cy: 0.45, r: 0.30 * shorter / width);
  }

  final double cx;
  final double cy;
  final double r;

  Map<String, dynamic> toJson() => {'cx': cx, 'cy': cy, 'r': r};

  @override
  bool operator ==(Object other) => other is GuideCircle && other.cx == cx && other.cy == cy && other.r == r;

  @override
  int get hashCode => Object.hash(cx, cy, r);
}

/// One camera frame checked by the server (MediaPipe + dlib).
class FaceCheck {
  const FaceCheck({required this.ready, required this.message, this.code});

  factory FaceCheck.fromJson(Map<String, dynamic> json) => FaceCheck(
        ready: json['ready'] == true,
        code: json['code'] as String?,
        message: json['message'] as String? ?? '',
      );

  final bool ready;
  final String? code;
  final String message;
}

/// A hairstyle rendered on the user's face.
class HairstylePreview {
  const HairstylePreview({
    required this.id,
    required this.name,
    required this.colour,
    required this.reason,
    required this.score,
    required this.image,
    this.isAi = false,
    this.thumbBase64,
  });

  factory HairstylePreview.fromJson(Map<String, dynamic> json) => HairstylePreview(
        id: json['hairstyle_id'] as String? ?? '',
        name: json['name'] as String? ?? 'Hairstyle',
        colour: json['colour'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0,
        image: base64Decode(json['preview_base64'] as String? ?? ''),
        isAi: json['renderer'] == 'ai',
        thumbBase64: json['thumb_base64'] as String?,
      );

  final String id;
  final String name;
  final String colour;
  final String reason;
  final double score;
  final Uint8List image;

  /// Made by the AI hair transfer (the user's own hair replaced), not the 2D overlay.
  final bool isAi;

  /// A small JPEG of the preview (base64), kept with a wardrobe item (SFR-035/036).
  final String? thumbBase64;
}

/// The face shape and the suggested hairstyles (SFR-029..031).
class HairstyleResult {
  const HairstyleResult({
    required this.faceShape,
    required this.faceShapeNote,
    required this.styles,
    required this.original,
    this.skippedShorter = 0,
    this.hairLength,
    this.hairTexture,
    this.hairTextureSource = 'unknown',
    this.isAi = false,
    this.note = '',
  });

  factory HairstyleResult.fromJson(Map<String, dynamic> json) {
    final first = json['default'];
    final rest = (json['alternatives'] as List<dynamic>? ?? const []);
    return HairstyleResult(
      faceShape: json['face_shape'] as String? ?? '',
      faceShapeNote: json['face_shape_note'] as String? ?? '',
      styles: [
        if (first is Map<String, dynamic>) HairstylePreview.fromJson(first),
        for (final a in rest)
          if (a is Map<String, dynamic>) HairstylePreview.fromJson(a),
      ],
      original: base64Decode(json['original_base64'] as String? ?? ''),
      skippedShorter: json['skipped_shorter'] as int? ?? 0,
      hairLength: json['hair_length'] as String?,
      hairTexture: json['hair_texture'] as String?,
      hairTextureSource: json['hair_texture_source'] as String? ?? 'unknown',
      isAi: json['renderer'] == 'ai',
      note: json['note'] as String? ?? '',
    );
  }

  final String faceShape;
  final String faceShapeNote;

  /// The best match first (the "default"), then the alternatives.
  final List<HairstylePreview> styles;

  /// The same head crop without a new hairstyle (before / after).
  final Uint8List original;

  /// Styles left out because too much of the user's own hair would show
  /// (older servers only; nobody is refused for long hair any more).
  final int skippedShorter;

  /// The user's own hair: "short" / "medium" / "long" (measured), null if none seen.
  final String? hairLength;

  /// "straight" / "wavy" as the user said, or estimated when confident; null = not sure.
  final String? hairTexture;

  /// "user", "estimated" or "unknown".
  final String hairTextureSource;

  /// The previews are AI hair transfer (true) or the quick 2D overlay.
  final bool isAi;

  /// E.g. why the quick preview was used.
  final String note;

  /// "Long · wavy (our guess)" for the result screen.
  String get hairSummary {
    final parts = <String>[
      if (hairLength != null) hairLength![0].toUpperCase() + hairLength!.substring(1),
      if (hairTexture != null) hairTextureSource == 'estimated' ? '$hairTexture (our guess)' : hairTexture!,
    ];
    return parts.isEmpty ? "We couldn't see much hair" : parts.join(' · ');
  }
}

/// What each face shape means, in a sentence.
const kFaceShapeMeaning = {
  'Oval': 'Balanced proportions: slightly longer than wide, with a gently rounded jaw.',
  'Round': 'About as wide as long, with full cheeks and a soft jaw.',
  'Square': 'A strong, wide jaw with a forehead of similar width.',
  'Heart': 'A wider forehead and cheekbones, narrowing to the chin.',
  'Oblong': 'Noticeably longer than wide, with straight sides.',
  'Diamond': 'Wide cheekbones with a narrower forehead and chin.',
};
