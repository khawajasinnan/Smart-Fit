import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));
    
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutQuart));

    _startAnimations();
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _fadeController.forward();
    _slideController.forward();
    
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) _navigate();
  }

  Future<void> _navigate() async {
    final authState = ref.read(authNotifierProvider);
    if (!mounted) return;
    
    if (authState.status == AuthStatus.authenticated) {
      context.go(RoutePaths.profileGate);
    }
    // If not authenticated, we stay so user can press Login/Register
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Full bleed editorial fashion image
          Positioned.fill(
            child: SafeNetworkImage(
              imageUrl: 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?q=80&w=1920&auto=format&fit=crop',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // Gradient overlay: from-surface/10 via-surface/30 to-surface/90
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surface.withValues(alpha: 0.1),
                    AppColors.surface.withValues(alpha: 0.3),
                    AppColors.surface.withValues(alpha: 0.9),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // Top Logo — text-primary with text shadow
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Container(
                        margin: const EdgeInsets.only(top: 20),
                        child: Text(
                          'SmartFit',
                          style: AppTextStyles.displayXl.copyWith(
                            color: AppColors.primary,
                            shadows: [
                              Shadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Bottom Glassmorphic Card
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Quote text with gradient
                                ShaderMask(
                                  shaderCallback: (bounds) => const LinearGradient(
                                    colors: [AppColors.primary, AppColors.secondaryContainer],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: Text(
                                    'Your fit,\nyour future.',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.quoteVibrant.copyWith(
                                      color: Colors.white, // needed for ShaderMask
                                      fontSize: 48,
                                      height: 1.1,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'AI-powered style recommendations tailored perfectly for you.',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // Primary CTA — solid primary pill with arrow
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(9999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.3),
                                        blurRadius: 30,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                      elevation: 0,
                                    ),
                                    onPressed: () => context.push(RoutePaths.onboarding),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Get Started',
                                          style: AppTextStyles.headlineMd.copyWith(
                                            color: Colors.white,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.arrow_forward, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () => context.push(RoutePaths.login),
                                    child: RichText(
                                      text: TextSpan(
                                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                                        children: [
                                          const TextSpan(text: 'Already have an account? '),
                                          TextSpan(
                                            text: 'Log in',
                                            style: AppTextStyles.bodyMd.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
