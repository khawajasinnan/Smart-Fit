import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/wardrobe/data/models/wardrobe_category.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/features/wardrobe/screens/wardrobe_screen.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

import '../../helpers/fake_wardrobe.dart';

/// The wardrobe (SFR-035/036/037, spec §23.19).
void main() {
  Future<FakeWardrobe> pump(WidgetTester tester, FakeWardrobe wardrobe) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SafeNetworkImage.debugImageProviderOverride = (_) => MemoryImage(Uint8List(0));
    addTearDown(() => SafeNetworkImage.debugImageProviderOverride = null);
    await tester.pumpWidget(ProviderScope(
      overrides: [wardrobeNotifierProvider.overrideWith((ref) => wardrobe)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const WardrobeScreen(),
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    return wardrobe;
  }

  testWidgets('stats, date sections and category chips', (tester) async {
    await pump(tester, FakeWardrobe(sampleWardrobe(DateTime.now())));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.bySemanticsLabel('All, 6'), findsOneWidget);
    expect(find.bySemanticsLabel('Eastern, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Outerwear, 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Eastern, 1'));
    await tester.pumpAndSettle();
    expect(find.text('Embroidered Lawn Kurta'), findsOneWidget);
    expect(find.text('Jacquard Jacket'), findsNothing);
  });

  testWidgets('tap flips a card to its details; remove offers undo', (tester) async {
    final wardrobe = await pump(tester, FakeWardrobe(sampleWardrobe(DateTime.now())));
    await tester.tap(find.text('Jacquard Jacket'));
    await tester.pumpAndSettle();
    expect(find.text('View on store'), findsOneWidget);
    expect(find.text('Saved just now'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(wardrobe.removed, ['j1']);
    expect(find.text('Jacquard Jacket'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Jacquard Jacket'), findsOneWidget);
  });

  testWidgets('swipe left removes a piece', (tester) async {
    final wardrobe = await pump(tester, FakeWardrobe(sampleWardrobe(DateTime.now())));
    final card = find.text('Baggy Fit Cargo Trouser');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.drag(card, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(wardrobe.removed, ['c1']);
  });

  testWidgets('empty wardrobe invites the user to Zayn', (tester) async {
    await pump(tester, FakeWardrobe(const []));
    expect(find.text('Your wardrobe is empty'), findsOneWidget);
    expect(find.text('Find looks with Zayn'), findsOneWidget);
  });

  test('categories: Eastern wins, then dresses, outerwear, bottoms, tops', () {
    WardrobeCategory c(String title, [String? category]) => WardrobeCategory.of(
        ProductRecommendation(id: 'x', brand: 'b', title: title, category: category, productUrl: 'u'));
    expect(c('Embroidered Lawn Shirt'), WardrobeCategory.eastern);
    expect(c('3 Piece Unstitched Suit'), WardrobeCategory.eastern);
    expect(c('Floral Maxi Dress'), WardrobeCategory.dresses);
    expect(c('Graphic Hoodie'), WardrobeCategory.outerwear);
    expect(c('Baggy Cargo Trouser'), WardrobeCategory.bottoms);
    expect(c('Oxford Striped Shirt'), WardrobeCategory.tops);
    expect(c('Leather Belt'), WardrobeCategory.other);
  });
}
