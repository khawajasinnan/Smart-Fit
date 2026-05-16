import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';

/// Glassmorphism card widget matching Stitch design system
class SFGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurAmount;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const SFGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.blurAmount = 20,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurAmount,
            sigmaY: blurAmount,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: Container(
                padding: padding ?? const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.glassDarkBg
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: isDark
                        ? AppColors.glassBorder
                        : Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
