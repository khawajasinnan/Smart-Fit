import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/widgets/match_explanation.dart';
import 'package:smartfit/features/scoring/data/look_score_api_service.dart';
import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/features/scoring/screens/look_score_screen.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

import '../helpers/screenshot_harness.dart';

/// Visual review of the Look Score screen and the "Why this pick?" sheet.
/// Skipped unless SF_SCREENSHOT_DIR is set. The numbers are a real
/// response from the scoring service (maroon embroidered kurta, mehndi, size small).

final _response = {
  'score': 77,
  'verdict': 'A strong look — a couple of small tweaks would perfect it.',
  'components': [
    {'key': 'style', 'label': 'Style match', 'score': 85, 'weight': 0.2, 'known': true,
     'note': 'It matches your ethnic style.', 'effect': 0.4},
    {'key': 'colour', 'label': 'Colour harmony', 'score': 87, 'weight': 0.2, 'known': true,
     'note': 'Maroon flatters your Medium skin tone; a single-colour maroon look is easy to wear.', 'effect': 0.0},
    {'key': 'fit', 'label': 'Size & fit', 'score': 35, 'weight': 0.2, 'known': true,
     'note': 'Size L is small for you.', 'effect': -11.8},
    {'key': 'occasion', 'label': 'Occasion', 'score': 95, 'weight': 0.2, 'known': true,
     'note': 'Right for mehndi.', 'effect': 9.5},
    {'key': 'hairstyle', 'label': 'Hairstyle', 'score': 82, 'weight': 0.2, 'known': true,
     'note': 'Side-swept quiff suits your oval face.', 'effect': 1.6},
  ],
  'comments': <String>[],
  'hints': [
    "Go one size up — a garment that's tight pulls at the seams and spoils the drape.",
    'Pair the maroon with navy or white accents — shoes, a waistcoat or a watch strap.',
    'Layering — a waistcoat or an open jacket — adds shape to a straight frame.',
  ],
  'validation': {'model': 'random_forest', 'predicted_score': 55, 'agrees': false, 'baseline': 61,
                 'note': 'A second AI model rates it lower (55), mainly because of size & fit.'},
  'model_features': [85.0, 87.0, 35.0, 95.0, 82.0, 1.0, 1.0, 1.0, 1.0, 1.0],
};

class _Api extends LookScoreApiService {
  _Api() : super(Dio());

  @override
  Future<LookScoreResult> score({required LookScoreArgs look, UserProfileModel? profile, ChosenHairstyle? hairstyle,
      String? occasion}) async => LookScoreResult.fromJson(_response);
}

const _product = ProductRecommendation(
  id: 'charcoal:1',
  brand: 'Charcoal',
  title: 'Maroon Embroidered Kurta',
  productUrl: 'https://charcoal.com.pk/products/kurta',
  colors: ['maroon'],
);

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('look score (${mode.name})', (tester) async {
      await pumpScreen(
        tester,
        const LookScoreScreen(
          args: LookScoreArgs(product: _product, fit: TryOnFit(status: TryOnFitStatus.small, note: '', size: 'L')),
        ),
        mode: mode,
        overrides: [
          lookScoreApiServiceProvider.overrideWithValue(_Api()),
          currentUserProvider.overrideWithValue(null),
          chosenHairstyleProvider.overrideWith(
            (ref) => const ChosenHairstyle(id: 'q', name: 'Side-swept quiff', score: 0.82, faceShape: 'Oval'),
          ),
        ],
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'look_score_1_top_${mode.name}');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'look_score_2_scrolled_${mode.name}');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'look_score_3_hints_${mode.name}');
    }, skip: !screenshotsEnabled);

    testWidgets('why this pick (${mode.name})', (tester) async {
      final p = ProductRecommendation.fromJson({
        'id': 'a', 'brand': 'Almirah', 'title': 'White Cotton Kurta - AL-K-1300', 'match_score': 97,
        'product_url': 'https://almirah.com.pk/products/k', 'ranking_model': 'lightgbm+random_forest',
        'validated': true,
        'explanation': [
          {'feature': 'skin_harmony', 'text': 'white flatters your Olive skin tone', 'impact': 1.2},
          {'feature': 'budget_fit', 'text': 'within your budget', 'impact': 0.6},
          {'feature': 'size_available', 'text': 'size XL in stock', 'impact': 0.4},
          {'feature': 'style_match', 'text': 'matches your ethnic style', 'impact': 0.2},
          {'feature': 'taste_brand', 'text': 'you passed on Almirah before', 'impact': -0.3},
        ],
        'suitability': {'skin_tone': 94, 'colours': 75, 'size': 100, 'occasion': 100, 'budget': 100},
      });
      await pumpScreen(tester, Center(child: MatchBadge(product: p)), mode: mode, wrapInScaffold: true);
      await tester.tap(find.byType(MatchBadge));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'look_score_4_why_this_pick_${mode.name}');
    }, skip: !screenshotsEnabled);
  }
}
