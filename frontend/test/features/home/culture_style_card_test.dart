import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/home/widgets/culture_style_card.dart';

/// The Home card for the profile's culture (21 Nov 2026).
void main() {
  Future<void> pump(WidgetTester tester, CultureGuide? guide) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [cultureGuideProvider.overrideWith((ref) async => guide)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SingleChildScrollView(child: CultureStyleCard())),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("shows the culture's looks for the user, each with a store search", (tester) async {
    final guide = CultureGuide.fromJson({
      'label': 'Punjabi',
      'intro': 'Bright, festive and proud.',
      'colours': ['white', 'mustard'],
      'outfits': [
        {'name': 'Mela look', 'pieces': ['Kurta', 'Tehmat (lacha / dhoti wrap)', 'Pagg (turban)', 'Khussa'],
         'when': 'Melas, Basant', 'search': 'white cotton kurta'},
        {'name': 'Everyday Punjabi suit', 'pieces': ['Kurta shalwar', 'Waistcoat'], 'when': 'Daily wear',
         'search': 'kurta shalwar'},
      ],
    });
    await pump(tester, guide);
    expect(find.text('Your Punjabi style'), findsOneWidget);
    expect(find.text('Kurta · Tehmat (lacha / dhoti wrap) · Pagg (turban) · Khussa'), findsOneWidget);
    expect(find.text('Find on stores: Mela look'), findsOneWidget);
    expect(find.text('Find on stores: Everyday Punjabi suit'), findsOneWidget);
  });

  testWidgets('without a culture the card is not there', (tester) async {
    await pump(tester, null);
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('style'), findsNothing);
  });
}
