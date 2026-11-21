import 'package:smartfit/core/utils/store_link.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/recommendation/providers/taste_feedback_provider.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/features/tryon/screens/tryon_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smartfit/features/recommendation/widgets/match_explanation.dart';

/// A horizontal carousel of glassmorphic product cards shown inside the AI Stylist chat.
class ProductCarousel extends StatelessWidget {
  final List<ProductRecommendation> products;
  final String? searchQuery;

  /// Header text; defaults to "Found N items for you" (chat).
  final String? title;

  const ProductCarousel({super.key, required this.products, this.searchQuery, this.title});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shopping_bag_rounded, color: AppColors.secondaryContainer, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  title ?? 'Found ${products.length} items for you',
                  style: AppTextStyles.labelCaps.copyWith(color: context.sf.highlight, fontSize: 11),
                ),
              ],
            ),
          ),

          // Horizontal card list
          SizedBox(
            height: 482,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return ProductCard(product: products[index])
                    .animate()
                    .fadeIn(
                      duration: 500.ms,
                      delay: Duration(milliseconds: 80 * index),
                    )
                    .slideX(
                      begin: 0.15,
                      curve: Curves.easeOutQuad,
                      delay: Duration(milliseconds: 80 * index),
                    );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Glassmorphic product card with save-to-wardrobe functionality.
class ProductCard extends ConsumerWidget {
  final ProductRecommendation product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.read(wardrobeNotifierProvider.notifier);
    // Watch the wardrobe state to get reactive updates on the heart icon
    ref.watch(wardrobeNotifierProvider);
    final isSaved = wardrobe.isProductSaved(product.key);

    // Watch loved fits state for reactive Love Fit checkbox updates
    final lovedFits = ref.watch(lovedFitsProvider);
    final feedback = ref.read(feedbackActionsProvider);
    final isLoved = lovedFits.contains(product.key);
    final isNope = ref.watch(tasteFeedbackProvider.select((t) => t.isDisliked(product)));

    return AnimatedOpacity(
      opacity: isNope ? 0.45 : 1,
      duration: const Duration(milliseconds: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              color: context.cs.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isLoved ? AppColors.hotPink.withValues(alpha: 0.45) : context.sf.glassBorder,
                width: isLoved ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Product Image ──
                Expanded(
                  flex: 7,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                          child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                              ? SafeNetworkImage(
                                  imageUrl: product.imageUrl!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: double.infinity,
                                  color: context.cs.surfaceContainerHigh,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.checkroom_rounded, size: 40, color: context.cs.outlineVariant),
                                      const SizedBox(height: 8),
                                      Text(
                                        'View on store',
                                        style: AppTextStyles.bodySm.copyWith(
                                          color: context.cs.outlineVariant,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      // ── "% match" from the learned ranking (top-left): tap for why ──
                      if (product.isLearnedRanking && product.matchScore > 0)
                        Positioned(top: 10, left: 10, child: MatchBadge(product: product)),
                      // ── Save to Wardrobe heart icon (top-right) ──
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () {
                            if (isSaved) {
                              wardrobe.removeProduct(product.key);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Removed from wardrobe'),
                                  backgroundColor: context.cs.onSurfaceVariant,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 1),
                                  margin: const EdgeInsets.all(20),
                                ),
                              );
                            } else {
                              wardrobe.saveProduct(product);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Saved to wardrobe ✨'),
                                  backgroundColor: context.cs.primary,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 1),
                                  margin: const EdgeInsets.all(20),
                                ),
                              );
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9999),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSaved
                                      ? AppColors.hotPink.withValues(alpha: 0.15)
                                      : context.cs.surface.withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  size: 18,
                                  color: isSaved ? AppColors.hotPink : context.sf.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Product Details ──
                Expanded(
                  flex: 10,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The product facts take the room left above the
                        // buttons; when a product has every optional line (or
                        // the user has large text) the last line is clipped
                        // instead of overflowing the card.
                        Expanded(
                          child: ClipRect(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title
                                  Text(
                                    product.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.titleMd.copyWith(
                                      color: context.cs.onSurface,
                                      fontSize: 14,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  // Brand + Price row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          product.brand,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodySm.copyWith(
                                            color: context.cs.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        product.formattedPrice,
                                        style: AppTextStyles.titleMd.copyWith(
                                          color: context.sf.highlight,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (product.freshnessLabel() case final freshness?) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          product.priceCheckedAt != null
                                              ? Icons.verified_rounded
                                              : Icons.schedule_rounded,
                                          size: 12,
                                          color: product.priceCheckedAt != null
                                              ? AppColors.success
                                              : context.cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            freshness,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.bodySm.copyWith(
                                              color: context.cs.onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (product.sizes.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      'Sizes: ${product.sizes.take(4).join(", ")}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySm.copyWith(
                                        color: context.cs.onSurfaceVariant,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (product.recommendedSize != null) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: context.sf.highlight.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '📐 Your Size: ${product.recommendedSize}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodySm.copyWith(
                                          color: context.sf.highlight,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // ── "Love Fit" + "Not for me": feedback learning (spec §23.15) ──
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  final nowLoved = await feedback.toggleLove(product);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          nowLoved
                                              ? 'Loved! Saved to your feedback learning profile ✨'
                                              : 'Removed from loved fits.',
                                          style: const TextStyle(
                                            fontFamily: 'SpaceGrotesk',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        backgroundColor: nowLoved
                                            ? const Color(0xFF1B1425)
                                            : context.cs.onSurfaceVariant,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        duration: const Duration(seconds: 2),
                                        margin: const EdgeInsets.all(20),
                                      ),
                                    );
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isLoved
                                        ? AppColors.hotPink.withValues(alpha: 0.12)
                                        : context.sf.glassFill,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isLoved ? AppColors.hotPink : context.cs.outlineVariant,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Interactive Checkbox Box
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          color: isLoved ? AppColors.hotPink : context.sf.surfaceElevated,
                                          border: Border.all(
                                            color: isLoved ? Colors.transparent : context.cs.outline,
                                            width: 1.4,
                                          ),
                                          boxShadow: isLoved
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.transparent,
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: isLoved
                                            ? Center(
                                                child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Love Fit',
                                          style: TextStyle(
                                            fontFamily: 'SpaceGrotesk',
                                            fontSize: 11,
                                            fontWeight: isLoved ? FontWeight.w800 : FontWeight.w600,
                                            color: isLoved ? context.sf.accentText : context.cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (isLoved)
                                        const Icon(Icons.favorite_rounded, size: 13, color: AppColors.hotPink),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _NotForMeButton(product: product, active: isNope),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // ── "Try on" (SFR-026): opens the Try-On tab with this product ──
                        GestureDetector(
                          onTap: () => openTryOn(context, ref, product),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            margin: const EdgeInsets.only(bottom: 5),
                            decoration: BoxDecoration(
                              color: context.sf.highlight.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.threesixty_rounded, color: context.sf.highlight, size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Try on',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelCaps.copyWith(
                                      color: context.sf.highlight,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── "View on Store" CTA ──
                        GestureDetector(
                          onTap: () => openStoreLink(context, product.productUrl),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              gradient: context.sf.brandGradient,
                              borderRadius: BorderRadius.circular(9999),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x0F000000),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.open_in_new_rounded, color: context.sf.onBrand, size: 15),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'View on Store',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelCaps.copyWith(
                                      color: context.sf.onBrand,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),

                        // ── "Save to Wardrobe" secondary button ──
                        GestureDetector(
                          onTap: () {
                            if (isSaved) {
                              wardrobe.removeProduct(product.key);
                            } else {
                              wardrobe.saveProduct(product);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Saved to wardrobe ✨'),
                                  backgroundColor: context.cs.primary,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 1),
                                  margin: const EdgeInsets.all(20),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isSaved ? context.sf.highlight.withValues(alpha: 0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: isSaved
                                    ? context.sf.highlight.withValues(alpha: 0.3)
                                    : context.cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isSaved ? Icons.checkroom_rounded : Icons.add_rounded,
                                  color: context.sf.highlight,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    isSaved ? 'In Wardrobe' : 'Save to Wardrobe',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelCaps.copyWith(color: context.sf.highlight, fontSize: 9.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thumbs-down: "not for me". The product is never recommended again and
/// repeated misses teach the ranking what to avoid (spec §23.15). Undo-able.
class _NotForMeButton extends ConsumerWidget {
  const _NotForMeButton({required this.product, required this.active});

  final ProductRecommendation product;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedback = ref.read(feedbackActionsProvider);
    return Semantics(
      button: true,
      toggled: active,
      label: active ? 'Marked not for me. Tap to undo' : 'Not for me',
      child: Tooltip(
        message: active ? 'Undo "not for me"' : 'Not for me',
        child: GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            if (active) {
              await feedback.undoNotForMe(product);
              return;
            }
            await feedback.notForMe(product);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: const Text(
                    "Got it, not your vibe. I won't show that one again 💅",
                    style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600),
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(20),
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(label: 'Undo', onPressed: () => feedback.undoNotForMe(product)),
                ),
              );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 34,
            height: 32,
            decoration: BoxDecoration(
              color: active ? context.cs.onSurfaceVariant.withValues(alpha: 0.16) : context.sf.glassFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? context.cs.onSurfaceVariant : context.cs.outlineVariant, width: 1.2),
            ),
            child: Icon(
              active ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
              size: 15,
              color: active ? context.cs.onSurface : context.cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
