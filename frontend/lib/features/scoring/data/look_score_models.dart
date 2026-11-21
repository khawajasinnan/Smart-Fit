import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

/// The hairstyle the user last chose on the Hairstyles screen, kept for the
/// look score (SFR-032 scores the outfit *and* hairstyle combination).
class ChosenHairstyle {
  const ChosenHairstyle({
    required this.id,
    required this.name,
    required this.score,
    required this.faceShape,
    this.thumbBase64,
  });

  /// From a saved wardrobe item's `hairstyle` (SFR-035).
  static ChosenHairstyle? fromWardrobeJson(Object? json) {
    if (json is! Map) return null;
    final id = json['hairstyle_id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return ChosenHairstyle(
      id: id,
      name: name,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      faceShape: json['face_shape'] as String? ?? '',
      thumbBase64: json['thumb_base64'] as String?,
    );
  }

  final String id;
  final String name;

  /// 0..1 suitability for the user's face shape (from the hairstyle service).
  final double score;
  final String faceShape;

  /// Small JPEG (base64) of the preview, for the wardrobe card.
  final String? thumbBase64;

  /// What the look score needs (no picture).
  Map<String, dynamic> toJson() => {'hairstyle_id': id, 'name': name, 'score': score, 'face_shape': faceShape};

  /// Kept with a wardrobe item (SFR-035): the style and its small picture.
  Map<String, dynamic> toWardrobeJson() => {...toJson(), 'thumb_base64': ?thumbBase64};
}

/// What to score: opened from a finished try-on (product + fit) or a product card.
class LookScoreArgs {
  const LookScoreArgs({required this.product, this.fit});

  final ProductRecommendation product;
  final TryOnFit? fit;

  // a provider key: the same look must find the same controller
  @override
  bool operator ==(Object other) =>
      other is LookScoreArgs &&
      other.product.key == product.key &&
      other.fit?.status == fit?.status &&
      other.fit?.size == fit?.size;

  @override
  int get hashCode => Object.hash(product.key, fit?.status, fit?.size);
}

class LookComponent {
  const LookComponent({
    required this.key,
    required this.label,
    required this.score,
    required this.weight,
    required this.known,
    required this.note,
    this.effect,
  });

  final String key;
  final String label;
  final int score;
  final double weight;

  /// False: not enough information, a neutral score was used.
  final bool known;
  final String note;

  /// Points this part added (+) or removed (-) in the Random Forest's view.
  final double? effect;

  factory LookComponent.fromJson(Map<String, dynamic> json) => LookComponent(
    key: json['key']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    score: (json['score'] as num?)?.round() ?? 0,
    weight: (json['weight'] as num?)?.toDouble() ?? 0,
    known: json['known'] as bool? ?? true,
    note: json['note']?.toString() ?? '',
    effect: (json['effect'] as num?)?.toDouble(),
  );
}

class LookValidation {
  const LookValidation({required this.predictedScore, required this.agrees, required this.note});

  final int predictedScore;
  final bool agrees;
  final String note;

  static LookValidation? fromJson(Object? json) {
    if (json is! Map) return null;
    return LookValidation(
      predictedScore: (json['predicted_score'] as num?)?.round() ?? 0,
      agrees: json['agrees'] as bool? ?? false,
      note: json['note']?.toString() ?? '',
    );
  }
}

class LookScoreResult {
  const LookScoreResult({
    required this.score,
    required this.verdict,
    required this.components,
    required this.comments,
    required this.hints,
    required this.modelFeatures,
    this.validation,
  });

  final int score;
  final String verdict;
  final List<LookComponent> components;
  final List<String> comments;
  final List<String> hints;
  final LookValidation? validation;

  /// Sent back with a rating, so feedback learning sees what the user saw.
  final List<double> modelFeatures;

  factory LookScoreResult.fromJson(Map<String, dynamic> json) => LookScoreResult(
    score: (json['score'] as num?)?.round() ?? 0,
    verdict: json['verdict']?.toString() ?? '',
    components: [
      for (final c in (json['components'] as List<dynamic>? ?? const []))
        if (c is Map<String, dynamic>) LookComponent.fromJson(c),
    ],
    comments: [for (final c in (json['comments'] as List<dynamic>? ?? const [])) c.toString()],
    hints: [for (final h in (json['hints'] as List<dynamic>? ?? const [])) h.toString()],
    validation: LookValidation.fromJson(json['validation']),
    modelFeatures: [for (final v in (json['model_features'] as List<dynamic>? ?? const [])) (v as num).toDouble()],
  );
}
