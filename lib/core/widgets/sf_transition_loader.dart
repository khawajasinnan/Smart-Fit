import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';

/// Helper to trigger a 2-3 second rounded loading bar transition before navigating.
class SFNavHelper {
  SFNavHelper._();

  /// Navigates to [targetPath] with a 2.5-second rounded loading screen transition.
  static Future<void> navigateWithLoader(
    BuildContext context,
    String targetPath, {
    String? title,
    String? subtitle,
    bool replace = false,
  }) async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (ctx, anim, secAnim) {
          return FadeTransition(
            opacity: anim,
            child: SFTransitionLoader(
              title: title,
              subtitle: subtitle,
              onComplete: () {
                Navigator.of(ctx).pop();
                if (replace) {
                  context.go(targetPath);
                } else {
                  context.push(targetPath);
                }
              },
            ),
          );
        },
      ),
    );
  }
}

/// Ultra-aesthetic glassmorphic screen transition featuring a glowing rounded/circular loading bar (2.5s).
class SFTransitionLoader extends StatefulWidget {
  final String? title;
  final String? subtitle;
  final VoidCallback onComplete;
  final Duration duration;

  const SFTransitionLoader({
    super.key,
    this.title,
    this.subtitle,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<SFTransitionLoader> createState() => _SFTransitionLoaderState();
}

class _SFTransitionLoaderState extends State<SFTransitionLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnim;

  final List<String> _stylingTips = [
    'Curating your high-res wardrobe look...',
    'Analyzing fit harmony & silhouette...',
    'Tailoring custom personal style aesthetics...',
    'Ready for your fit check!',
  ];

  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _progressAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.addListener(() {
      final progress = _controller.value;
      final newIndex = (progress * (_stylingTips.length - 1)).floor();
      if (newIndex != _tipIndex && mounted) {
        setState(() => _tipIndex = newIndex);
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Frosted glass backdrop ──
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),

          // ── Ambient Glow Orbs ──
          Positioned(
            top: -60,
            right: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF2E93).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6C4CE0).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Clothing silhouettes background pattern ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.08,
              color: Color(0xFFFF2E93),
            ),
          ),

          // ── Center Content: Rounded Loading Bar ──
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedBuilder(
                animation: _progressAnim,
                builder: (context, _) {
                  final progress = _progressAnim.value;
                  final percentage = (progress * 100).toInt().clamp(0, 100);

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 36,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: const Color(0xFFFF2E93).withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E93).withValues(alpha: 0.12),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: const Color(0xFF6C4CE0).withValues(alpha: 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Circular Rounded Loading Indicator ──
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Custom Circular Rounded Progress Painter
                              CustomPaint(
                                size: const Size(130, 130),
                                painter: _CircularRoundedProgressPainter(
                                  progress: progress,
                                ),
                              ),

                              // Inner Glowing Disc
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      const Color(0xFFFFF0F7).withValues(alpha: 0.95),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF2E93).withValues(alpha: 0.15),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$percentage%',
                                        style: const TextStyle(
                                          fontFamily: 'SpaceGrotesk',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1B1425),
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 13,
                                        color: Color(0xFFFF2E93),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 26),

                        // Title
                        Text(
                          widget.title ?? 'SmartFit Couture',
                          style: AppTextStyles.headlineMd.copyWith(
                            color: const Color(0xFF1B1425),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Dynamic Status Subtitle
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            widget.subtitle ?? _stylingTips[_tipIndex],
                            key: ValueKey<int>(_tipIndex),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                              fontSize: 12.5,
                              fontFamily: 'Inter',
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for a circular progress bar with rounded ends and glowing iridescent gradient.
class _CircularRoundedProgressPainter extends CustomPainter {
  final double progress;

  _CircularRoundedProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = const Color(0xFFFF2E93).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.0) return;

    // Glowing Neon Sweep Gradient for the active arc
    const sweepGradient = SweepGradient(
      colors: [
        Color(0xFFFF2E93),
        Color(0xFF6C4CE0),
        Color(0xFF00E5FF),
        Color(0xFFFF2E93),
      ],
      stops: [0.0, 0.4, 0.75, 1.0],
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
    );

    final sweepRect = Rect.fromCircle(center: center, radius: radius);

    // Outer glow for the active arc
    final glowPaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(sweepRect, -math.pi / 2, sweepAngle, false, glowPaint);

    // Foreground active arc with rounded caps
    final progressPaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9.0;

    canvas.drawArc(sweepRect, -math.pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularRoundedProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
