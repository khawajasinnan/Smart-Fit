import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';

final skinToneApiServiceProvider = Provider<SkinToneApiService>((ref) => SkinToneApiService(ref.watch(apiDioProvider)));

/// One named colour of the advice.
class SkinColour {
  const SkinColour(this.name, this.hex);

  final String name;
  final String hex;

  factory SkinColour.fromJson(Map<String, dynamic> j) => SkinColour(j['name'] as String, j['hex'] as String);
}

/// Clothing advice for a skin tone + undertone (backend shared/skin_palette.py).
class SkinPalette {
  const SkinPalette({
    required this.skinTone,
    required this.undertone,
    required this.summary,
    required this.best,
    required this.avoid,
    required this.white,
    required this.metal,
    required this.outfits,
    required this.avoidTip,
  });

  final String skinTone;
  final String? undertone;
  final String summary;
  final List<SkinColour> best;
  final List<SkinColour> avoid;
  final String white;
  final String metal;
  final List<String> outfits;
  final String avoidTip;

  factory SkinPalette.fromJson(Map<String, dynamic> j) => SkinPalette(
    skinTone: j['skin_tone'] as String,
    undertone: j['undertone'] as String?,
    summary: j['summary'] as String,
    best: [for (final c in (j['best'] as List? ?? const [])) SkinColour.fromJson(c as Map<String, dynamic>)],
    avoid: [for (final c in (j['avoid'] as List? ?? const [])) SkinColour.fromJson(c as Map<String, dynamic>)],
    white: j['white'] as String? ?? '',
    metal: j['metal'] as String? ?? '',
    outfits: [for (final o in (j['outfits'] as List? ?? const [])) o as String],
    avoidTip: j['avoid_tip'] as String? ?? '',
  );
}

/// What the analyzer measured in a photo (backend POST /skin-tone/analyze).
class SkinAnalysis {
  const SkinAnalysis({
    required this.skinTone,
    required this.monkLevel,
    required this.monkHex,
    required this.measuredHex,
    required this.undertone,
    required this.undertoneSure,
    required this.whiteBalanced,
    required this.note,
    required this.palette,
  });

  /// One of the app's swatches: Fair, Light, Medium, Olive, Brown, Dark.
  final String skinTone;

  /// 1 (lightest) .. 10 (deepest) on the Monk Skin Tone scale.
  final int monkLevel;
  final String monkHex;
  final String measuredHex;
  final String undertone; // warm | cool | neutral
  final bool undertoneSure;
  final bool whiteBalanced;
  final String note;
  final SkinPalette palette;

  factory SkinAnalysis.fromJson(Map<String, dynamic> j) => SkinAnalysis(
    skinTone: j['skin_tone'] as String,
    monkLevel: (j['monk_level'] as num).toInt(),
    monkHex: j['monk_hex'] as String,
    measuredHex: j['measured_hex'] as String,
    undertone: j['undertone'] as String,
    undertoneSure: j['undertone_confidence'] == 'high',
    whiteBalanced: j['white_balanced'] as bool? ?? false,
    note: j['note'] as String? ?? '',
    palette: SkinPalette.fromJson(j['palette'] as Map<String, dynamic>),
  );
}

/// The Monk Skin Tone scale's reference swatches (Ellis Monk with Google), lightest first.
const monkScaleHex = [
  '#F6EDE4', '#F3E7DB', '#F7EAD0', '#EADABA', '#D7BD96', //
  '#A07E56', '#825C43', '#604134', '#3A312A', '#292420',
];

/// The final undertone from the photo and the two standard questions (vein colour, metal).
/// Each answer is a vote (warm +1, cool -1, neutral 0); the photo counts 1 when the
/// analyzer was sure, 0.5 when not. Null = nothing to go on yet.
String? combineUndertone({String? photo, bool photoSure = false, String? veins, String? metal}) {
  double vote(String? v) => v == 'warm' ? 1 : (v == 'cool' ? -1 : 0);
  final answers = [veins, metal].whereType<String>().toList();
  if (photo == null && answers.isEmpty) return null;
  final total = vote(photo) * (photoSure ? 1 : 0.5) + answers.fold<double>(0, (s, a) => s + vote(a));
  if (total >= 0.75) return 'warm';
  if (total <= -0.75) return 'cool';
  return 'neutral';
}

class SkinToneApiService {
  SkinToneApiService(this._dio);

  final Dio _dio;

  /// From a photo the user takes or picks ([imageBase64]) or their profile photo ([imageUrl]).
  Future<SkinAnalysis> analyze({String? imageBase64, String? imageUrl}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.skinToneAnalyzePath,
        data: {'image_base64': ?imageBase64, 'image_url': ?imageUrl},
        options: Options(receiveTimeout: const Duration(seconds: 50)),
      );
      return SkinAnalysis.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  Future<SkinPalette> palette(String skinTone, String? undertone) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.skinTonePalettePath,
        queryParameters: {'skin_tone': skinTone, 'undertone': ?undertone},
      );
      return SkinPalette.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}
