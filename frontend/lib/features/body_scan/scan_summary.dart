import 'dart:typed_data';

import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';

/// What the scan screen hands back to its caller.
class BodyScanOutcome {
  const BodyScanOutcome({required this.bytes, this.analysis}) : retake = false;

  const BodyScanOutcome.retake() : bytes = null, analysis = null, retake = true;

  /// The captured photo (null only for [retake]).
  final Uint8List? bytes;

  /// The backend scan; null if the user attached the photo without one.
  final CvAnalysisResult? analysis;

  /// The user asked to take the photo again.
  final bool retake;
}

/// The scan's headline results, small enough to store in a chat message's
/// metadata (so the card survives reloading the chat) and to brief the stylist.
class ScanSummary {
  const ScanSummary({
    this.bodyShape,
    this.faceShape,
    this.shoulders,
    this.shoulderTiltDeg,
    this.shoulderBuild,
    this.skinTone,
    this.skinHex,
    this.size,
    this.agreement,
    this.note,
    this.models = const [],
  });

  final String? bodyShape;
  final String? faceShape;
  final String? shoulders;
  final double? shoulderTiltDeg;
  final String? shoulderBuild;
  final String? skinTone;
  final String? skinHex;
  final String? size;
  final String? agreement;

  /// Why something couldn't be measured (e.g. hips out of frame).
  final String? note;
  final List<String> models;

  static const metadataType = 'body_scan';

  factory ScanSummary.fromResult(CvAnalysisResult r) {
    final agreement = r.modelAgreement;
    final skin = r.skinTone;
    return ScanSummary(
      bodyShape: r.bodyShape,
      faceShape: r.face?.faceShape,
      shoulders: r.shoulders?.level,
      shoulderTiltDeg: r.shoulders?.tiltDeg,
      shoulderBuild: r.shoulders?.build,
      skinTone: skin == null || skin.toneLabel.isEmpty ? null : skin.toneLabel,
      skinHex: skin == null || skin.dominantHex.isEmpty ? null : skin.dominantHex,
      size: r.estimatedSize,
      agreement: agreement == null
          ? null
          : '${agreement.agreement} (joints ${agreement.meanOffsetPct.toStringAsFixed(0)}% of shoulder width apart)',
      note: r.error,
      models: r.modelsUsed,
    );
  }

  factory ScanSummary.fromMap(Map<String, dynamic> m) => ScanSummary(
        bodyShape: m['body_shape'] as String?,
        faceShape: m['face_shape'] as String?,
        shoulders: m['shoulders'] as String?,
        shoulderTiltDeg: (m['shoulder_tilt_deg'] as num?)?.toDouble(),
        shoulderBuild: m['shoulder_build'] as String?,
        skinTone: m['skin_tone'] as String?,
        skinHex: m['skin_hex'] as String?,
        size: m['size'] as String?,
        agreement: m['agreement'] as String?,
        note: m['note'] as String?,
        models: (m['models'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
      );

  Map<String, dynamic> toMap() => {
        'type': metadataType,
        if (bodyShape != null) 'body_shape': bodyShape,
        if (faceShape != null) 'face_shape': faceShape,
        if (shoulders != null) 'shoulders': shoulders,
        if (shoulderTiltDeg != null) 'shoulder_tilt_deg': shoulderTiltDeg,
        if (shoulderBuild != null) 'shoulder_build': shoulderBuild,
        if (skinTone != null) 'skin_tone': skinTone,
        if (skinHex != null) 'skin_hex': skinHex,
        if (size != null) 'size': size,
        if (agreement != null) 'agreement': agreement,
        if (note != null) 'note': note,
        'models': models,
      };

  String? get shoulderText {
    if (shoulders == null) return null;
    final tilt = shoulderTiltDeg == null || shoulders == 'Level' ? '' : ' (${shoulderTiltDeg!.abs().toStringAsFixed(0)}°)';
    final build = shoulderBuild == null ? '' : ', ${shoulderBuild!.toLowerCase()}';
    return '$shoulders$tilt$build';
  }

  /// One plain-text line per finding: the chat message text and the stylist's briefing.
  List<String> get lines => [
        if (bodyShape != null) 'Body shape: $bodyShape',
        if (shoulderText != null) 'Shoulders: $shoulderText',
        if (faceShape != null) 'Face shape: $faceShape',
        if (skinTone != null) 'Skin tone: $skinTone',
        if (size != null) 'Estimated size: $size',
      ];

  /// Context for the AI stylist (sent with later messages in this chat).
  String get stylistContext => [
        'Live body & face scan of the user (${models.isEmpty ? 'MediaPipe' : models.join(', ')}):',
        ...lines.map((l) => '- $l'),
        if (note != null) '- Not measured: $note',
        'Use these for fit, neckline, collar and hairstyle advice. Face shape and body shape are photo estimates.',
      ].join('\n');
}
