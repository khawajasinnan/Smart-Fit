import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/core/widgets/sf_bottom_nav_bar.dart';
import 'package:smartfit/features/chat/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedProducts = ref.watch(wardrobeNotifierProvider);
    final notifier = ref.read(wardrobeNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      bottomNavigationBar: SFBottomNavBar(currentIndex: 1),
      body: Stack(
        children: [
          // Ambient background orbs
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondaryContainer.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.05,
              color: Color(0xFFFF2E93),
            ),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Glass top app bar with Gen-Z pink accent
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.65),
                              const Color(0xFFFFE5F0).withValues(alpha: 0.55),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.secondaryContainer
                                  .withValues(alpha: 0.15),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _CircleIconButton(
                              icon: Icons.arrow_back_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.secondaryContainer,
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.secondaryContainer
                                        .withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.checkroom_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'My Wardrobe',
                                    style: AppTextStyles.headlineMd.copyWith(
                                      color: AppColors.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${savedProducts.length} saved items',
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.secondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (savedProducts.isNotEmpty)
                              _CircleIconButton(
                                icon: Icons.delete_sweep_rounded,
                                iconColor: AppColors.error,
                                onTap: () =>
                                    _showClearDialog(context, notifier),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Products grid or empty state
                Expanded(
                  child: savedProducts.isEmpty
                      ? _buildEmptyState()
                      : _buildProductGrid(context, savedProducts, notifier),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.checkroom_rounded,
              size: 56,
              color: AppColors.outlineVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your wardrobe is empty',
            style: AppTextStyles.headlineMd.copyWith(
              color: AppColors.onSurface,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Save products from AI Stylist recommendations by tapping the heart icon on any product card.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).scale(
          begin: const Offset(0.9, 0.9),
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildProductGrid(
    BuildContext context,
    List<ProductRecommendation> products,
    WardrobeNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 120),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.74,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _WardrobeCard(
            product: product,
            onRemove: () => notifier.removeProduct(product.id),
          )
              .animate()
              .fadeIn(
                duration: 400.ms,
                delay: Duration(milliseconds: 60 * index),
              )
              .slideY(
                begin: 0.1,
                curve: Curves.easeOutQuad,
                delay: Duration(milliseconds: 60 * index),
              );
        },
      ),
    );
  }

  void _showClearDialog(BuildContext context, WardrobeNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Wardrobe',
          style: AppTextStyles.headlineMd.copyWith(
            color: AppColors.onSurface,
          ),
        ),
        content: Text(
          'Remove all saved products from your wardrobe? This cannot be undone.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.primary),
            ),
          ),
          FilledButton(
            onPressed: () {
              notifier.clearAll();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

/// Small glass-backed circular icon button used in the wardrobe header.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.8),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}

/// Individual wardrobe product card
class _WardrobeCard extends StatelessWidget {
  final ProductRecommendation product;
  final VoidCallback onRemove;

  const _WardrobeCard({required this.product, required this.onRemove});

  Future<void> _openProductUrl() async {
    final uri = Uri.tryParse(product.productUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              Expanded(
                flex: 11,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: product.imageUrl != null &&
                                product.imageUrl!.isNotEmpty
                            ? SafeNetworkImage(
                                imageUrl: product.imageUrl!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppColors.surfaceContainerHigh,
                                child: const Center(
                                  child: Icon(
                                    Icons.checkroom_rounded,
                                    size: 32,
                                    color: AppColors.outlineVariant,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // Remove button (top-right)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surface.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                size: 14,
                                color: Color(0xFFE91E63),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Brand badge (top-left)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              product.brand,
                              style: AppTextStyles.labelCaps.copyWith(
                                color: AppColors.primary,
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Product details
              Expanded(
                flex: 9,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
                          fontSize: 11,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              product.formattedPrice,
                              style: AppTextStyles.titleMd.copyWith(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (product.recommendedSize != null)
                            Text(
                              '📐 ${product.recommendedSize}',
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // View on Store button
                      GestureDetector(
                        onTap: _openProductUrl,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            gradient: AppColors.buttonGradient,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: Colors.white,
                                size: 11,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'View on Store',
                                style: AppTextStyles.labelCaps.copyWith(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
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
