import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/widgets/product_card_widget.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_wardrobe.dart';

/// The product card must never overflow (the "RenderFlex overflowed by 11
/// pixels" seen on the home carousel), even with every optional line shown.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final fullCard = ProductRecommendation(
    id: 'x:1',
    brand: 'Bonanza Satrangi Premium Collection',
    title: 'Embroidered Three Piece Lawn Suit With Printed Chiffon Dupatta And Trousers',
    pricePkr: 12990,
    productUrl: 'https://example.pk/products/1',
    sizes: const ['XS', 'S', 'M', 'L', 'XL'],
    recommendedSize: 'M (from the size chart)',
    priceCheckedAt: DateTime.now(),
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('a card with every line fits (text x$scale)', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(SupabaseClient('http://localhost:1', 'anon',
              authOptions: const AuthClientOptions(autoRefreshToken: false))),
          currentUserProvider.overrideWithValue(null),
          wardrobeNotifierProvider.overrideWith((ref) => FakeWardrobe(sampleWardrobe(DateTime.now()))),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ProductCarousel(products: [fullCard, fullCard]),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('View on Store'), findsWidgets);
      expect(find.text('Try on'), findsWidgets);
    });
  }
}
