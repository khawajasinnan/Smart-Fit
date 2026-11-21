import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/recommendation/data/services/scraper_api_service.dart';
import 'package:smartfit/features/recommendation/widgets/product_card_widget.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';

/// One look of a culture's guide (backend shared/culture_styles.py).
class CultureOutfit {
  const CultureOutfit({required this.name, required this.pieces, required this.when, required this.search});

  final String name;
  final List<String> pieces;
  final String when;
  final String search;

  factory CultureOutfit.fromJson(Map<String, dynamic> j) => CultureOutfit(
    name: j['name'] as String,
    pieces: [for (final p in (j['pieces'] as List? ?? const [])) p as String],
    when: j['when'] as String? ?? '',
    search: j['search'] as String? ?? '',
  );
}

class CultureGuide {
  const CultureGuide({required this.label, required this.intro, required this.colours, required this.outfits});

  final String label;
  final String intro;
  final List<String> colours;
  final List<CultureOutfit> outfits;

  factory CultureGuide.fromJson(Map<String, dynamic> j) => CultureGuide(
    label: j['label'] as String,
    intro: j['intro'] as String? ?? '',
    colours: [for (final c in (j['colours'] as List? ?? const [])) c as String],
    outfits: [for (final o in (j['outfits'] as List? ?? const [])) CultureOutfit.fromJson(o as Map<String, dynamic>)],
  );
}

/// The signed-in user's culture guide (their own gender's looks); null when the profile has no
/// culture the guide knows, or the service can't be reached (the card then doesn't show).
final cultureGuideProvider = FutureProvider.autoDispose<CultureGuide?>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  final profile = ref.watch(profileNotifierProvider(userId)).valueOrNull;
  final culture = profile?.ethnicity;
  if (culture == null || culture.trim().isEmpty) return null;
  try {
    final res = await ref
        .read(apiDioProvider)
        .get<Map<String, dynamic>>(
          ApiEndpoints.cultureGuidePath,
          queryParameters: {'culture': culture, 'gender': profile?.gender ?? ''},
        );
    final guide = res.data?['guide'];
    ref.keepAlive();
    return guide is Map<String, dynamic> ? CultureGuide.fromJson(guide) : null;
  } on DioException {
    return null;
  }
});

/// "Your Punjabi style" on Home (21 Nov 2026, the user's request: a profile's culture shows
/// that culture's outfits, e.g. Punjabi kurta, tehmat/dhoti and turban). Our stores rarely sell
/// the regional pieces, so each look is a styling idea with "Find on stores" for what they do
/// sell (kurtas, waistcoats, ajrak, rilli ...).
class CultureStyleCard extends ConsumerWidget {
  const CultureStyleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(cultureGuideProvider).valueOrNull;
    if (guide == null || guide.outfits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: SFGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: context.sf.accentText, size: 20),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Your ${guide.label} style', style: context.tt.titleMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(guide.intro, style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
            const SizedBox(height: AppSpace.sm),
            for (final outfit in guide.outfits) _OutfitTile(outfit: outfit, culture: guide.label),
          ],
        ),
      ),
    );
  }
}

class _OutfitTile extends ConsumerWidget {
  const _OutfitTile({required this.outfit, required this.culture});

  final CultureOutfit outfit;
  final String culture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(outfit.name, style: context.tt.labelLarge),
          Text(outfit.pieces.join(' · '), style: context.tt.bodyMedium),
          if (outfit.when.isNotEmpty)
            Text(outfit.when, style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              onPressed: () => _showProducts(context, ref),
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: Text('Find on stores: ${outfit.name}'),
            ),
          ),
        ],
      ),
    );
  }

  void _showProducts(BuildContext context, WidgetRef ref) {
    final userId = ref.read(currentUserProvider)?.id;
    final profile = userId == null ? null : ref.read(profileNotifierProvider(userId)).valueOrNull;
    if (profile == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _OutfitProducts(profile: profile, outfit: outfit, culture: culture),
      ),
    );
  }
}

/// Real products for one look: the catalog search, no Gemini call.
class _OutfitProducts extends ConsumerWidget {
  const _OutfitProducts({required this.profile, required this.outfit, required this.culture});

  final UserProfileModel profile;
  final CultureOutfit outfit;
  final String culture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .read(scraperApiServiceProvider)
          .searchProducts(profile: profile, userMessage: '${outfit.search}. $culture style', maxProducts: 10),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: SFLoader(label: 'Finding pieces in your size…'));
        }
        final products = snap.data?.products ?? const [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
          children: [
            Text('${outfit.name}: in the stores', style: context.tt.titleMedium),
            const SizedBox(height: AppSpace.xxs),
            Text(
              'Some pieces of this look are rarely sold online, so here is what the stores have that fits it.',
              style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
            ),
            const SizedBox(height: AppSpace.md),
            if (products.isEmpty)
              Text(snap.data?.message ?? 'Nothing for this look right now.', style: context.tt.bodyMedium)
            else
              ProductCarousel(products: products, title: '${products.length} pieces for this look'),
          ],
        );
      },
    );
  }
}
