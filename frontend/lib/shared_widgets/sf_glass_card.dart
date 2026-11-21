import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/pressable.dart';

/// Frosted-glass surface (design.md §2.6). Use it where something shows
/// through (orbs, photos). [blur] costs GPU time, so it's off by default and
/// reserved for hero cards; the translucent fill alone already reads as glass.
class SFGlassCard extends StatelessWidget {
  const SFGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.margin,
    this.borderRadius = AppRadius.lg,
    this.blur = false,
    this.onTap,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool blur;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final radius = BorderRadius.circular(borderRadius);
    Widget surface = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: sf.glassFill,
        borderRadius: radius,
        border: Border.all(color: sf.glassBorder),
      ),
      child: child,
    );
    if (blur) {
      surface = BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: surface);
    }
    surface = DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: sf.cardShadow),
      child: ClipRRect(borderRadius: radius, child: surface),
    );
    if (onTap != null) surface = Pressable(onTap: onTap, semanticLabel: semanticLabel, child: surface);
    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}
