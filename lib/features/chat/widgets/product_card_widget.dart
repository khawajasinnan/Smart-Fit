import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/chat/providers/loved_fits_provider.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A horizontal carousel of glassmorphic product cards shown inside the AI Stylist chat.
class ProductCarousel extends StatelessWidget {
  final List<ProductRecommendation> products;
  final String? searchQuery;

  const ProductCarousel({super.key, required this.products, this.searchQuery});

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
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.secondaryContainer,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Found ${products.length} items for you',
                  style: AppTextStyles.labelCaps.copyWith(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Horizontal card list
          SizedBox(
            height: 450,
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

  Future<void> _openProductUrl() async {
    final uri = Uri.tryParse(product.productUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.read(wardrobeNotifierProvider.notifier);
    // Watch the wardrobe state to get reactive updates on the heart icon
    ref.watch(wardrobeNotifierProvider);
    final isSaved = wardrobe.isProductSaved(product.id);

    // Watch loved fits state for reactive Love Fit checkbox updates
    final lovedFits = ref.watch(lovedFitsProvider);
    final lovedNotifier = ref.read(lovedFitsProvider.notifier);
    final isLoved = lovedFits.contains(product.id.isNotEmpty ? product.id : product.productUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 240,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isLoved
                  ? const Color(0xFFFF2E93).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.6),
              width: isLoved ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isLoved
                    ? const Color(0xFFFF2E93).withValues(alpha: 0.18)
                    : const Color(0xFF8B5CF6).withValues(alpha: 0.12),
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
                flex: 4,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        child:
                            product.imageUrl != null &&
                                product.imageUrl!.isNotEmpty
                            ? SafeNetworkImage(
                                imageUrl: product.imageUrl!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: double.infinity,
                                color: AppColors.surfaceContainerHigh,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.checkroom_rounded,
                                      size: 40,
                                      color: AppColors.outlineVariant,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'View on store',
                                      style: AppTextStyles.bodySm.copyWith(
                                        color: AppColors.outlineVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    // ── Save to Wardrobe heart icon (top-right) ──
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () {
                          if (isSaved) {
                            wardrobe.removeProduct(product.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Removed from wardrobe'),
                                backgroundColor: AppColors.onSurfaceVariant,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                duration: const Duration(seconds: 1),
                                margin: const EdgeInsets.all(20),
                              ),
                            );
                          } else {
                            wardrobe.saveProduct(product);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Saved to wardrobe ✨'),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                                    ? const Color(
                                        0xFFE91E63,
                                      ).withValues(alpha: 0.15)
                                    : AppColors.surface.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSaved
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: isSaved
                                    ? const Color(0xFFE91E63)
                                    : AppColors.secondaryContainer,
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
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
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
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            product.formattedPrice,
                            style: AppTextStyles.titleMd.copyWith(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (product.sizes.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Sizes: ${product.sizes.take(4).join(", ")}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (product.recommendedSize != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '📐 Your Size: ${product.recommendedSize}',
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),

                      // ── Interactive "Love Fit" Checkbox with Feedback Learning ──
                      GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final nowLoved = await lovedNotifier.toggleLoveFit(product);
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
                                    : AppColors.onSurfaceVariant,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isLoved
                                ? const Color(0xFFFF2E93).withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLoved
                                  ? const Color(0xFFFF2E93)
                                  : Colors.black.withValues(alpha: 0.15),
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
                                  gradient: isLoved
                                      ? const LinearGradient(
                                          colors: [Color(0xFFFF2E93), Color(0xFF8A2BE2)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: isLoved ? null : Colors.white,
                                  border: Border.all(
                                    color: isLoved
                                        ? Colors.transparent
                                        : Colors.black.withValues(alpha: 0.25),
                                    width: 1.4,
                                  ),
                                  boxShadow: isLoved
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFFF2E93).withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isLoved
                                    ? const Center(
                                        child: Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
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
                                    color: isLoved
                                        ? const Color(0xFFFF2E93)
                                        : AppColors.onSurface,
                                  ),
                                ),
                              ),
                              if (isLoved)
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 13,
                                  color: Color(0xFFFF2E93),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // ── "View on Store" CTA ──
                      GestureDetector(
                        onTap: _openProductUrl,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            gradient: AppColors.buttonGradient,
                            borderRadius: BorderRadius.circular(9999),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'View on Store',
                                style: AppTextStyles.labelCaps.copyWith(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
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
                            wardrobe.removeProduct(product.id);
                          } else {
                            wardrobe.saveProduct(product);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Saved to wardrobe ✨'),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                            color: isSaved
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(
                              color: isSaved
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isSaved
                                    ? Icons.checkroom_rounded
                                    : Icons.add_rounded,
                                color: AppColors.primary,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSaved ? 'In Wardrobe' : 'Save to Wardrobe',
                                style: AppTextStyles.labelCaps.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 9.5,
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
    );
  }
}
