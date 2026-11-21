import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';

/// SmartFit-specific theme colours that Material's ColorScheme doesn't cover:
/// brand gradients, glass surfaces, ambient orbs, the clothing pattern tint,
/// skeleton shimmer and the floating nav bar. Has a light and a dark variant.
@immutable
class SFColors extends ThemeExtension<SFColors> {
  const SFColors({
    required this.brandGradient,
    required this.heroGradient,
    required this.ink,
    required this.textMuted,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.divider,
    required this.glassFill,
    required this.glassBorder,
    required this.cardShadow,
    required this.orbA,
    required this.orbB,
    required this.orbC,
    required this.patternTint,
    required this.patternOpacity,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.navFill,
    required this.navBorder,
    required this.accentText,
    required this.success,
    required this.warning,
    required this.info,
    required this.highlight,
    this.onBrand = AppColors.ink900,
  });

  /// The neon-green brand fill (CTAs, badges, avatar ring, user chat bubbles).
  /// Flat: both stops are the same colour. Text/icons on it use [onBrand].
  final LinearGradient brandGradient;

  /// Text and icons drawn on [brandGradient] (dark: neon green needs dark text).
  final Color onBrand;

  /// Dark scrim over editorial photos so white text stays readable.
  final LinearGradient heroGradient;

  final Color ink;
  final Color textMuted;
  final Color surfaceElevated;
  final Color surfaceSunken;
  final Color divider;
  final Color glassFill;
  final Color glassBorder;
  final List<BoxShadow> cardShadow;
  final Color orbA;
  final Color orbB;
  final Color orbC;
  final Color patternTint;
  final double patternOpacity;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color navFill;
  final Color navBorder;

  /// The pink accent, readable as text on this theme's surfaces (section labels).
  final Color accentText;
  final Color success;
  final Color warning;
  final Color info;

  /// The second brand colour for small accents (section labels, selected
  /// states, outlines, glows): violet on light, lime green on dark.
  final Color highlight;

  static const SFColors light = SFColors(
    brandGradient: AppColors.primaryGradient,
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0x3314121F), Color(0xD914121F)],
      stops: [0.35, 0.6, 1],
    ),
    ink: AppColors.ink900,
    textMuted: AppColors.ink400,
    surfaceElevated: AppColors.surface1,
    surfaceSunken: Color(0xFFEDEFEA),
    divider: AppColors.border,
    glassFill: AppColors.surface1, // solid cards, no frosted glass
    glassBorder: AppColors.border,
    cardShadow: AppShadows.sm,
    orbA: Color(0x00000000), // no ambient colour blobs
    orbB: Color(0x00000000),
    orbC: Color(0x00000000),
    patternTint: AppColors.hotPink, // the pink clothing icons behind content
    patternOpacity: 0.08,
    shimmerBase: Color(0xFFECEEEA),
    shimmerHighlight: Color(0xFFF8F9F6),
    navFill: AppColors.surface1,
    navBorder: AppColors.border,
    accentText: AppColors.pinkText,
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    info: Color(0xFF2563EB),
    highlight: AppColors.greenDeep,
  );

  /// Near-black with the neon green.
  static const SFColors dark = SFColors(
    brandGradient: AppColors.primaryGradient,
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0x66000000), Color(0xF2000000)],
      stops: [0.3, 0.6, 1],
    ),
    ink: AppColors.darkInk,
    textMuted: AppColors.darkMuted,
    surfaceElevated: AppColors.darkSurface1,
    surfaceSunken: Color(0xFF050605),
    divider: AppColors.darkBorder,
    glassFill: AppColors.darkSurface1,
    glassBorder: AppColors.darkBorder,
    cardShadow: AppShadows.darkMd,
    orbA: Color(0x00000000),
    orbB: Color(0x00000000),
    orbC: Color(0x00000000),
    patternTint: AppColors.hotPink,
    patternOpacity: 0.12, // pink needs more on near-black to be seen
    shimmerBase: Color(0xFF121512),
    shimmerHighlight: Color(0xFF1E231E),
    navFill: AppColors.darkSurface1,
    navBorder: AppColors.darkBorder,
    accentText: AppColors.hotPink,
    success: AppColors.neonLime,
    warning: AppColors.warning,
    info: Color(0xFF7AB8F0),
    highlight: AppColors.neonGreen,
  );

  @override
  SFColors copyWith({
    LinearGradient? brandGradient,
    LinearGradient? heroGradient,
    Color? ink,
    Color? textMuted,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? divider,
    Color? glassFill,
    Color? glassBorder,
    List<BoxShadow>? cardShadow,
    Color? orbA,
    Color? orbB,
    Color? orbC,
    Color? patternTint,
    double? patternOpacity,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? navFill,
    Color? navBorder,
    Color? accentText,
    Color? success,
    Color? warning,
    Color? info,
    Color? highlight,
    Color? onBrand,
  }) {
    return SFColors(
      brandGradient: brandGradient ?? this.brandGradient,
      heroGradient: heroGradient ?? this.heroGradient,
      ink: ink ?? this.ink,
      textMuted: textMuted ?? this.textMuted,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      divider: divider ?? this.divider,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      orbA: orbA ?? this.orbA,
      orbB: orbB ?? this.orbB,
      orbC: orbC ?? this.orbC,
      patternTint: patternTint ?? this.patternTint,
      patternOpacity: patternOpacity ?? this.patternOpacity,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      navFill: navFill ?? this.navFill,
      navBorder: navBorder ?? this.navBorder,
      accentText: accentText ?? this.accentText,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      highlight: highlight ?? this.highlight,
      onBrand: onBrand ?? this.onBrand,
    );
  }

  @override
  SFColors lerp(ThemeExtension<SFColors>? other, double t) {
    if (other is! SFColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SFColors(
      brandGradient: LinearGradient.lerp(brandGradient, other.brandGradient, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      ink: c(ink, other.ink),
      textMuted: c(textMuted, other.textMuted),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      divider: c(divider, other.divider),
      glassFill: c(glassFill, other.glassFill),
      glassBorder: c(glassBorder, other.glassBorder),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? other.cardShadow,
      orbA: c(orbA, other.orbA),
      orbB: c(orbB, other.orbB),
      orbC: c(orbC, other.orbC),
      patternTint: c(patternTint, other.patternTint),
      patternOpacity: lerpDouble(patternOpacity, other.patternOpacity, t)!,
      shimmerBase: c(shimmerBase, other.shimmerBase),
      shimmerHighlight: c(shimmerHighlight, other.shimmerHighlight),
      navFill: c(navFill, other.navFill),
      navBorder: c(navBorder, other.navBorder),
      accentText: c(accentText, other.accentText),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      info: c(info, other.info),
      highlight: c(highlight, other.highlight),
      onBrand: c(onBrand, other.onBrand),
    );
  }
}

/// Short-hands: `context.sf`, `context.cs`, `context.tt`, `context.reduceMotion`.
extension SFThemeContext on BuildContext {
  SFColors get sf => Theme.of(this).extension<SFColors>() ?? SFColors.light;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// True when the OS asks for reduced motion — ambient/looping animation
  /// must stop (design.md §8).
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
