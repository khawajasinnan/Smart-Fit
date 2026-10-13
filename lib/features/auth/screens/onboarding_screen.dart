import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  final List<Map<String, String>> _pages = [
    {
      'title': 'See yourself in new clothes.',
      'subtitle': 'Upload a photo and instantly try on hundreds of styles without stepping into a fitting room.',
      'image': 'https://images.unsplash.com/photo-1550639524-a6f58345a059?q=80&w=1000&auto=format&fit=crop',
    },
    {
      'title': 'Your personal AI stylist.',
      'subtitle': 'Get outfit recommendations based on your unique body type, skin tone, and personal vibe.',
      'image': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?q=80&w=1000&auto=format&fit=crop',
    },
    {
      'title': 'Curate your dream vault.',
      'subtitle': 'Save your favorite looks, discover new trends, and build a wardrobe you truly love.',
      'image': 'https://images.unsplash.com/photo-1483985988355-763728e1935b?q=80&w=1000&auto=format&fit=crop',
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (mounted) context.go(RoutePaths.register);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background Images PageView
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              _animController.reset();
              _animController.forward();
            },
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  SafeNetworkImage(
                    imageUrl: _pages[index]['image']!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  // Gradient to fade into the glassmorphic card
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.5),
                          AppColors.background,
                        ],
                        stops: const [0.5, 0.8, 1.0],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.05,
              color: Color(0xFFFF2E93),
            ),
          ),
          
          // Skip Button
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    foregroundColor: AppColors.onSurface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          
          // Bottom Sheet — glassmorphic per design.md Screen 8
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 48),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    boxShadow: [
                      BoxShadow(color: AppColors.secondaryContainer.withValues(alpha: 0.15), blurRadius: 60, offset: const Offset(0, -20)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress indicator — active: wide pill with secondary glow
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentPage == index ? 40 : 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index ? AppColors.secondary : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: _currentPage == index
                                ? [BoxShadow(color: AppColors.secondary.withValues(alpha: 0.5), blurRadius: 12)]
                                : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Animated Text — displayXl per design.md
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Text(
                              _pages[_currentPage]['title']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                                height: 1.1,
                                letterSpacing: -0.96,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _pages[_currentPage]['subtitle']!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // CTA — secondary glow button with CAPS label + arrow
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(9999),
                          boxShadow: [
                            BoxShadow(color: AppColors.secondary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (_currentPage == _pages.length - 1) {
                              _completeOnboarding();
                            } else {
                              _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentPage == _pages.length - 1 ? 'GET STARTED' : 'NEXT',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
