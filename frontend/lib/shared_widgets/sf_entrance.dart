import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// Staggered entrance (fade + rise) for content blocks. Item [index] starts
/// [stagger] after the previous one. Shown instantly when the OS asks to
/// reduce motion.
class SFEntrance extends StatelessWidget {
  const SFEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 70),
    this.offsetY = 0.08,
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return child
        .animate(delay: stagger * index)
        .fadeIn(duration: AppDurations.entrance, curve: AppCurves.enter)
        .slideY(begin: offsetY, end: 0, duration: AppDurations.entrance, curve: AppCurves.enter);
  }
}
