import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TryOnScreen extends ConsumerWidget {
  const TryOnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient orbs
          Positioned(
            top: -60, right: -40,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 80, left: -80,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.secondaryFixedDim.withValues(alpha: 0.10),
                  Colors.transparent,
                ]),
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

          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('Virtual Try-On', style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('BETA', style: AppTextStyles.labelSm.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),

                // Main content
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glass card with icon
                          ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                width: 160, height: 160,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) => LinearGradient(
                                        colors: [AppColors.primary, AppColors.secondaryContainer],
                                      ).createShader(bounds),
                                      child: const Icon(Icons.checkroom_rounded, size: 64, color: Colors.white),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('2D Try-On', style: AppTextStyles.titleSm.copyWith(
                                      color: AppColors.primary, fontWeight: FontWeight.w600,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ).animate().fadeIn(duration: 800.ms).scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),

                          const SizedBox(height: 32),
                          Text(
                            'Coming Soon',
                            style: AppTextStyles.headlineLg.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
                          const SizedBox(height: 12),
                          Text(
                            'AI-powered 2D virtual try-on will let you see outfits on your own photo before buying.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ).animate().fadeIn(delay: 400.ms, duration: 600.ms),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Text('Notify Me', style: AppTextStyles.titleSm.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700,
                            )),
                          ).animate().fadeIn(delay: 600.ms, duration: 600.ms).slideY(begin: 0.2),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
