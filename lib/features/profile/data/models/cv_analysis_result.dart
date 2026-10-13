/// Dart mirror of backend `CvAnalysisResponse` from models/cv_schemas.py.
///
/// Represents the full output of the body detection & pose estimation pipeline:
/// body shape, clothing size, pose landmarks, skin tone, and body proportions.
class CvAnalysisResult {
  final bool success;
  final String? error;

  // ── Body shape ──
  final String? bodyShape; // Apple / Pear / Rectangle / Hourglass / Inverted Triangle
  final double bodyShapeConfidence;

  // ── Size estimation ──
  final String? estimatedSize; // XS / S / M / L / XL / XXL
  final String estimatedSizeSource; // pose_landmarks / profile_measurements / bmi_fallback

  // ── Estimated measurements (cm) ──
  final double? estimatedChestCm;
  final double? estimatedWaistCm;
  final double? estimatedHipCm;
  final double? estimatedShoulderWidthCm;

  // ── Body proportions ──
  final BodyProportions? proportions;

  // ── Pose landmarks ──
  final List<PoseLandmark> poseLandmarks;
  final double poseConfidence;

  // ── Skin tone ──
  final SkinToneResult? skinTone;

  // ── Image metadata ──
  final int imageWidth;
  final int imageHeight;

  final String? estimatedGender;
  final double? genderConfidence;

  const CvAnalysisResult({
    required this.success,
    this.error,
    this.bodyShape,
    this.bodyShapeConfidence = 0.0,
    this.estimatedSize,
    this.estimatedSizeSource = '',
    this.estimatedChestCm,
    this.estimatedWaistCm,
    this.estimatedHipCm,
    this.estimatedShoulderWidthCm,
    this.proportions,
    this.poseLandmarks = const [],
    this.poseConfidence = 0.0,
    this.skinTone,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.estimatedGender,
    this.genderConfidence,
  });

  factory CvAnalysisResult.fromJson(Map<String, dynamic> json) {
    return CvAnalysisResult(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
      bodyShape: json['body_shape'] as String?,
      bodyShapeConfidence:
          (json['body_shape_confidence'] as num?)?.toDouble() ?? 0.0,
      estimatedSize: json['estimated_size'] as String?,
      estimatedSizeSource: json['estimated_size_source'] as String? ?? '',
      estimatedChestCm:
          (json['estimated_chest_cm'] as num?)?.toDouble(),
      estimatedWaistCm:
          (json['estimated_waist_cm'] as num?)?.toDouble(),
      estimatedHipCm: (json['estimated_hip_cm'] as num?)?.toDouble(),
      estimatedShoulderWidthCm:
          (json['estimated_shoulder_width_cm'] as num?)?.toDouble(),
      proportions: json['proportions'] != null
          ? BodyProportions.fromJson(
              json['proportions'] as Map<String, dynamic>)
          : null,
      poseLandmarks: (json['pose_landmarks'] as List<dynamic>?)
              ?.map((e) =>
                  PoseLandmark.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      poseConfidence:
          (json['pose_confidence'] as num?)?.toDouble() ?? 0.0,
      skinTone: json['skin_tone'] != null
          ? SkinToneResult.fromJson(
              json['skin_tone'] as Map<String, dynamic>)
          : null,
      imageWidth: json['image_width'] as int? ?? 0,
      imageHeight: json['image_height'] as int? ?? 0,
      estimatedGender: json['estimated_gender'] as String?,
      genderConfidence: (json['gender_confidence'] as num?)?.toDouble(),
    );
  }

  /// Human-readable body shape summary for the UI.
  String get shapeSummary {
    if (bodyShape == null) return 'Not analyzed';
    final pct = (bodyShapeConfidence * 100).toStringAsFixed(0);
    return '$bodyShape ($pct% confidence)';
  }

  /// Human-readable size summary.
  String get sizeSummary {
    if (estimatedSize == null) return 'Not estimated';
    return 'Size $estimatedSize';
  }
}

/// Body proportions derived from pose landmarks.
class BodyProportions {
  final double? shoulderWidthRatio;
  final double? torsoLengthRatio;
  final double? legLengthRatio;
  final double? waistHipRatio;
  final double? shoulderHipDiff;

  const BodyProportions({
    this.shoulderWidthRatio,
    this.torsoLengthRatio,
    this.legLengthRatio,
    this.waistHipRatio,
    this.shoulderHipDiff,
  });

  factory BodyProportions.fromJson(Map<String, dynamic> json) {
    return BodyProportions(
      shoulderWidthRatio:
          (json['shoulder_width_ratio'] as num?)?.toDouble(),
      torsoLengthRatio:
          (json['torso_length_ratio'] as num?)?.toDouble(),
      legLengthRatio: (json['leg_length_ratio'] as num?)?.toDouble(),
      waistHipRatio: (json['waist_hip_ratio'] as num?)?.toDouble(),
      shoulderHipDiff:
          (json['shoulder_hip_diff'] as num?)?.toDouble(),
    );
  }
}

/// A single body landmark from MediaPipe Pose.
class PoseLandmark {
  final String name;
  final double x;
  final double y;
  final double z;
  final double visibility;

  const PoseLandmark({
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      name: json['name'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      z: (json['z'] as num?)?.toDouble() ?? 0.0,
      visibility: (json['visibility'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Skin tone analysis result.
class SkinToneResult {
  final String dominantHex;
  final String fitzpatrickType;
  final String toneLabel;
  final double? hsvHue;
  final double? hsvSaturation;
  final double? hsvValue;

  const SkinToneResult({
    this.dominantHex = '',
    this.fitzpatrickType = '',
    this.toneLabel = '',
    this.hsvHue,
    this.hsvSaturation,
    this.hsvValue,
  });

  factory SkinToneResult.fromJson(Map<String, dynamic> json) {
    return SkinToneResult(
      dominantHex: json['dominant_hex'] as String? ?? '',
      fitzpatrickType: json['fitzpatrick_type'] as String? ?? '',
      toneLabel: json['tone_label'] as String? ?? '',
      hsvHue: (json['hsv_hue'] as num?)?.toDouble(),
      hsvSaturation: (json['hsv_saturation'] as num?)?.toDouble(),
      hsvValue: (json['hsv_value'] as num?)?.toDouble(),
    );
  }
}
