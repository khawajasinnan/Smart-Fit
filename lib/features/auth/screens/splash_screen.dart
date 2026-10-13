import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/ai_chat_logo.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _checkAutoNavigation();
  }

  Future<void> _checkAutoNavigation() async {
    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    if (authState.status == AuthStatus.authenticated) {
      context.go(RoutePaths.profileGate);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F9),
      body: Stack(
        children: [
          // ── Atmospheric Radial Glows (Light mode palette) ──
          Positioned(
            top: -100,
            right: -60,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF2E93).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF9B85F0).withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.35,
            left: MediaQuery.of(context).size.width * 0.15,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFB6DE).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Pink Clothing Icons Background ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.16,
              color: Color(0xFFD81B60),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Top SmartFit Brand Badge with Sparkle Logo
                  Center(
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseCtrl.value * 0.06);
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF2E93).withValues(alpha: 0.25),
                                      blurRadius: 36,
                                      offset: const Offset(0, 12),
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF6C4CE0).withValues(alpha: 0.2),
                                      blurRadius: 40,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(3),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: AiChatLogo(
                                      size: 52,
                                      padding: 0,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF1E1A2A), Color(0xFFFF2E93)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: Text(
                            'SmartFit',
                            style: AppTextStyles.displayXl.copyWith(
                              color: const Color(0xFF1E1A2A),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              fontSize: 38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF2E93).withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'AI FASHION & STYLING SANCTUARY',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: Color(0xFFFF2E93),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .slideY(begin: -0.1, curve: Curves.easeOutCubic),

                  const Spacer(),

                  // Bottom Glassmorphic Card — Clean Light Mode
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Headline
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF1E1A2A), Color(0xFFFF2E93)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Text(
                                'Your Fit.\nYour Future.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  height: 1.12,
                                  letterSpacing: -1,
                                  color: Color(0xFF1E1A2A),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Next-gen AI fashion assistant, dynamic Gen-Z trends, and instant body-fit analysis.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMd.copyWith(
                                color: const Color(0xFF5F5B6E),
                                height: 1.45,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Primary CTA Button
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(9999),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2E93).withValues(alpha: 0.35),
                                    blurRadius: 26,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                    horizontal: 24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () => context.push(RoutePaths.onboarding),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Get Started',
                                      style: TextStyle(
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            )
                                .animate()
                                .scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack),

                            const SizedBox(height: 14),

                            // Log in link
                            TextButton(
                              onPressed: () => context.push(RoutePaths.login),
                              child: RichText(
                                text: TextSpan(
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: const Color(0xFF6B6678),
                                    fontSize: 13,
                                  ),
                                  children: const [
                                    TextSpan(text: 'Already have an account? '),
                                    TextSpan(
                                      text: 'Log in',
                                      style: TextStyle(
                                        color: Color(0xFFFF2E93),
                                        fontWeight: FontWeight.w800,
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
                  )
                      .animate()
                      .fadeIn(duration: 700.ms, delay: 200.ms)
                      .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
