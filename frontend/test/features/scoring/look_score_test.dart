import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/widgets/match_explanation.dart';
import 'package:smartfit/features/scoring/data/look_score_api_service.dart';
import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/features/scoring/screens/look_score_screen.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';

const _product = ProductRecommendation(
  id: 'alpha:1',
  brand: 'Alpha',
  title: 'Emerald Embroidered Kurta',
  productUrl: 'https://alpha.pk/products/kurta',
  colors: ['emerald'],
);

Map<String, dynamic> scoreJson({int score = 82, bool agrees = true}) => {
  'score': score,
  'verdict': 'A strong look — a couple of small tweaks would perfect it.',
  'components': [
    {'key': 'style', 'label': 'Style match', 'score': 100, 'weight': 0.25, 'known': true,
     'note': 'It matches your ethnic style.', 'effect': 6.2},
    {'key': 'fit', 'label': 'Size & fit', 'score': 35, 'weight': 0.25, 'known': true,
     'note': 'Size S is small for you.', 'effect': -14.0},
    {'key': 'occasion', 'label': 'Occasion', 'score': 70, 'weight': 0.25, 'known': false,
     'note': 'No occasion given — scored as everyday wear.'},
  ],
  'comments': ['It matches your ethnic style.'],
  'hints': ['Go one size up — a garment that\'s tight pulls at the seams and spoils the drape.'],
  'validation': {'model': 'random_forest', 'predicted_score': 58, 'agrees': agrees, 'baseline': 61,
                 'note': agrees ? 'A second AI model (Random Forest) independently agrees with this score.'
                     : 'A second AI model rates it lower (58), mainly because of size & fit.'},
  'model_features': [100.0, 70.0, 35.0, 70.0, 50.0, 1.0, 1.0, 1.0, 0.0, 0.0],
};

class FakeLookApi extends LookScoreApiService {
  FakeLookApi() : super(Dio());

  final occasions = <String?>[];
  final hairstyles = <ChosenHairstyle?>[];
  final ratings = <int>[];
  final corrections = <List<String>>[];
  final comments = <String?>[];
  Object? next;

  @override
  Future<LookScoreResult> score({
    required LookScoreArgs look,
    UserProfileModel? profile,
    ChosenHairstyle? hairstyle,
    String? occasion,
  }) async {
    occasions.add(occasion);
    hairstyles.add(hairstyle);
    final n = next;
    if (n is Failure) throw n;
    return LookScoreResult.fromJson(scoreJson());
  }

  @override
  Future<void> rate({required String productId, required int rating, required LookScoreResult result,
      String? occasion, List<String> corrections = const [], String? comment}) async {
    ratings.add(rating);
    this.corrections.add(corrections);
    comments.add(comment);
  }
}

void main() {
  group('models', () {
    test('score result parses components, validation and features', () {
      final r = LookScoreResult.fromJson(scoreJson(agrees: false));
      expect(r.score, 82);
      expect(r.components.map((c) => c.key), ['style', 'fit', 'occasion']);
      expect(r.components[1].effect, -14.0);
      expect(r.components[2].known, isFalse);
      expect(r.validation!.agrees, isFalse);
      expect(r.modelFeatures, hasLength(10));
    });

    test('look args are equal for the same product and fit', () {
      const fit = TryOnFit(status: TryOnFitStatus.small, note: '', size: 'S');
      expect(const LookScoreArgs(product: _product, fit: fit), const LookScoreArgs(product: _product, fit: fit));
      expect(const LookScoreArgs(product: _product, fit: fit) == const LookScoreArgs(product: _product),
          isFalse);
    });

    test('product explanation survives the wardrobe round trip', () {
      final p = ProductRecommendation.fromJson({
        'id': 'a', 'brand': 'A', 'title': 'T', 'product_url': 'https://a.pk/products/t', 'match_score': 91,
        'ranking_model': 'lightgbm+random_forest', 'validated': true,
        'explanation': [
          {'feature': 'skin_harmony', 'text': 'emerald flatters your Olive skin tone', 'impact': 0.8, 'value': 0.9,
           'label': 'x'},
          {'feature': 'budget_fit', 'text': 'above your budget', 'impact': -0.3},
          {'feature': 'bad'}, // no text: dropped
        ],
        'suitability': {'skin_tone': 90, 'size': null, 'budget': 40},
      });
      expect(p.isLearnedRanking, isTrue);
      expect(p.explanation.map((f) => f.helps), [true, false]);
      expect(p.suitability, {'skin_tone': 90, 'budget': 40});
      final again = ProductRecommendation.fromJson(p.toJson());
      expect(again.explanation.map((f) => f.text), p.explanation.map((f) => f.text));
      expect(again.suitability, p.suitability);
      expect(again.validated, isTrue);
    });

    test('older saved products default to rule ranking', () {
      final p = ProductRecommendation.fromJson({'id': 'a', 'brand': 'A', 'title': 'T', 'product_url': 'u'});
      expect(p.isLearnedRanking, isFalse);
      expect(p.explanation, isEmpty);
    });
  });

  group('screen', () {
    late FakeLookApi api;

    Future<void> pump(WidgetTester tester, {LookScoreArgs? args, ChosenHairstyle? hair}) async {
      api = FakeLookApi();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          lookScoreApiServiceProvider.overrideWithValue(api),
          currentUserProvider.overrideWithValue(null),
          chosenHairstyleProvider.overrideWith((ref) => hair),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: LookScoreScreen(args: args)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('without a look it explains how to get a score', (tester) async {
      await pump(tester);
      expect(find.text('Score a look'), findsOneWidget);
      expect(api.occasions, isEmpty);
    });

    testWidgets('shows the score, the reasons, the hints and the second opinion', (tester) async {
      const fit = TryOnFit(status: TryOnFitStatus.small, note: '', size: 'S');
      await pump(tester, args: const LookScoreArgs(product: _product, fit: fit));
      expect(find.text('82'), findsOneWidget);
      expect(find.text('Size S is small for you'), findsOneWidget);
      expect(find.text('Size S is small for you.'), findsOneWidget);
      expect(find.textContaining('independently agrees'), findsOneWidget);
      expect(find.text('−14'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // occasion unknown
      await tester.scrollUntilVisible(find.textContaining('one size up'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('one size up'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing an occasion and turning the hairstyle off re-score', (tester) async {
      const hair = ChosenHairstyle(id: 'q', name: 'Quiff', score: 0.8, faceShape: 'Oval');
      await pump(tester, args: const LookScoreArgs(product: _product), hair: hair);
      expect(api.hairstyles.single?.name, 'Quiff');
      await tester.tap(find.text('Eid'));
      await tester.pumpAndSettle();
      expect(api.occasions.last, 'eid');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(api.hairstyles.last, isNull);
    });

    testWidgets('rating the score sends the stars', (tester) async {
      await pump(tester, args: const LookScoreArgs(product: _product));
      final star = find.byTooltip('4 stars');
      await tester.scrollUntilVisible(star, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(api.ratings, [4]);
      expect(find.textContaining('SmartFit learns from your rating'), findsOneWidget);
    });

    testWidgets('SFR-034: after the stars, corrections and a comment go with the same rating', (tester) async {
      await pump(tester, args: const LookScoreArgs(product: _product));
      final star = find.byTooltip('2 stars');
      await tester.scrollUntilVisible(star, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(find.text("What's off? (optional)"), findsOneWidget);
      // the score parts the user can correct are the ones shown
      for (final label in ['Style match', 'Size & fit']) {
        final chip = find.widgetWithText(FilterChip, label);
        await tester.scrollUntilVisible(chip, 120, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(chip).selected, isTrue, reason: label);
      }
      final field = find.widgetWithText(TextField, 'Comment (optional)');
      await tester.scrollUntilVisible(field, 120, scrollable: find.byType(Scrollable).first);
      await tester.enterText(field, 'too loose for me');
      final send = find.text('Send feedback');
      await tester.scrollUntilVisible(send, 120, scrollable: find.byType(Scrollable).first);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(api.ratings, [2, 2]); // the same rating, sent again with the details
      expect(api.corrections.last, ['fit', 'style']);
      expect(api.comments.last, 'too loose for me');
      expect(find.textContaining('your notes help SmartFit get better'), findsOneWidget);
    });

    testWidgets('a failed re-score keeps the last score and says what went wrong', (tester) async {
      await pump(tester, args: const LookScoreArgs(product: _product));
      api.next = const NetworkFailure();
      await tester.tap(find.text('Party'));
      await tester.pumpAndSettle();
      expect(find.text('82'), findsOneWidget); // the last good score stays
      expect(find.byType(NoticeBanner), findsOneWidget);
      expect(find.text(const NetworkFailure().message), findsOneWidget);
    });
  });

  testWidgets('"Why this pick?" lists reasons and suitability', (tester) async {
    final p = ProductRecommendation.fromJson({
      'id': 'a', 'brand': 'A', 'title': 'Emerald Kurta', 'product_url': 'https://a.pk/products/t', 'match_score': 91,
      'ranking_model': 'lightgbm+random_forest', 'validated': true,
      'explanation': [
        {'feature': 'skin_harmony', 'text': 'emerald flatters your Olive skin tone', 'impact': 0.8},
        {'feature': 'budget_fit', 'text': 'above your budget', 'impact': -0.3},
      ],
      'suitability': {'skin_tone': 90, 'budget': 40},
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Center(child: MatchBadge(product: p))),
    ));
    expect(find.text('91% match'), findsOneWidget);
    await tester.tap(find.text('91% match'));
    await tester.pumpAndSettle();
    expect(find.text('Why this pick?'), findsOneWidget);
    expect(find.text('Emerald flatters your Olive skin tone'), findsOneWidget);
    expect(find.text('Above your budget'), findsOneWidget);
    expect(find.text('Suits your skin tone'), findsOneWidget);
    expect(find.textContaining('confirmed by a second'), findsOneWidget);
  });
}
