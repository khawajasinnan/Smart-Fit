import 'package:flutter/material.dart';

/// SmartFit Design System — Typography Scale
/// Headlines: Space Grotesk | Body: Inter
/// All values from design.md Section 2.
class AppTextStyles {
  AppTextStyles._();

  // ─── Font Families ───
  static const String headlineFont = 'SpaceGrotesk';
  static const String bodyFont = 'Inter';

  // ─── Display ───
  /// 48px — Screen titles, hero headlines, onboarding titles
  static const TextStyle displayXl = TextStyle(
    fontFamily: headlineFont,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.96, // -0.02em per design.md
  );

  // ─── Headlines ───
  /// 32px — Section headings, card titles
  static const TextStyle headlineLg = TextStyle(
    fontFamily: headlineFont,
    fontSize: 32,
    fontWeight: FontWeight.w600, // design.md says 600, was 700
    height: 1.2,
  );

  /// 24px — Button labels, form section headers
  static const TextStyle headlineMd = TextStyle(
    fontFamily: headlineFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle headlineSm = TextStyle(
    fontFamily: headlineFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // ─── Quote ───
  /// 28px — Inspirational quote text
  static const TextStyle quoteVibrant = TextStyle(
    fontFamily: headlineFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: Color(0xFF3B82F6), // Vibrant blue as requested
  );

  // ─── Title ───
  static const TextStyle titleLg = TextStyle(
    fontFamily: headlineFont,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle titleMd = TextStyle(
    fontFamily: headlineFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle titleSm = TextStyle(
    fontFamily: headlineFont,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // ─── Body ───
  /// 18px — Subtitles, form labels, descriptions
  static const TextStyle bodyLg = TextStyle(
    fontFamily: bodyFont,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  /// 16px — Body copy, chat bubbles
  static const TextStyle bodyMd = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ─── Labels ───
  static const TextStyle labelLg = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.5,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.0,
    letterSpacing: 1.2,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.0,
    letterSpacing: 1.1,
  );

  /// 12px — ALL-CAPS chip labels, nav labels, field labels
  /// 0.1em letter-spacing = 1.2px at 12px
  static const TextStyle labelCaps = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.2, // 0.1em
  );

  // ─── Button Text ───
  static const TextStyle buttonLg = TextStyle(
    fontFamily: headlineFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonMd = TextStyle(
    fontFamily: headlineFont,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0.3,
  );
}
