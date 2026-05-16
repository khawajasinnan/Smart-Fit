import 'package:flutter/material.dart';

/// SmartFit Design System — Color Tokens
/// Luminous Vibe Aesthetic (Light-Only)
/// All values from design.md Section 1 — use ONLY these exact hex values.
class AppColors {
  AppColors._();

  // ─── Core Brand: Primary (Purple) ───
  static const Color primary = Color(0xFF6B38D4);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF8455EF);
  static const Color onPrimaryContainer = Color(0xFFFFFBFF);
  static const Color primaryFixed = Color(0xFFE9DDFF);
  static const Color primaryFixedDim = Color(0xFFD0BCFF);
  static const Color onPrimaryFixed = Color(0xFF23005C);
  static const Color onPrimaryFixedVariant = Color(0xFF5516BE);
  static const Color inversePrimary = Color(0xFFD0BCFF);

  // ─── Secondary (Pink / Hot Pink) ───
  static const Color secondary = Color(0xFFB4136D);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFFD56A7);
  static const Color onSecondaryContainer = Color(0xFF600037);
  static const Color secondaryFixed = Color(0xFFFFD9E4);
  static const Color secondaryFixedDim = Color(0xFFFFB0CD);
  static const Color onSecondaryFixed = Color(0xFF3E0022);
  static const Color onSecondaryFixedVariant = Color(0xFF8C0053);

  // ─── Tertiary (Amber / Warm Orange) ───
  static const Color tertiary = Color(0xFF855000);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFA76500);
  static const Color onTertiaryContainer = Color(0xFFFFFBFF);
  static const Color tertiaryFixed = Color(0xFFFFDCBB);
  static const Color tertiaryFixedDim = Color(0xFFFFB869);
  static const Color onTertiaryFixed = Color(0xFF2C1700);
  static const Color onTertiaryFixedVariant = Color(0xFF673D00);

  // ─── Surface & Background ───
  static const Color background = Color(0xFFFEF7FF);
  static const Color onBackground = Color(0xFF1D1A23);
  static const Color surface = Color(0xFFFEF7FF);
  static const Color onSurface = Color(0xFF1D1A23);
  static const Color surfaceDim = Color(0xFFDED7E4);
  static const Color surfaceBright = Color(0xFFFEF7FF);
  static const Color surfaceVariant = Color(0xFFE7E0ED);
  static const Color onSurfaceVariant = Color(0xFF494454);
  static const Color surfaceTint = Color(0xFF6D3BD7);

  // ─── Surface Containers (Elevation Layers) ───
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF8F1FE);
  static const Color surfaceContainer = Color(0xFFF3EBF8);
  static const Color surfaceContainerHigh = Color(0xFFEDE5F3);
  static const Color surfaceContainerHighest = Color(0xFFE7E0ED);

  // ─── Inverse & Special ───
  static const Color inverseSurface = Color(0xFF322F39);
  static const Color inverseOnSurface = Color(0xFFF5EEFB);

  // ─── Outline ───
  static const Color outline = Color(0xFF7B7486);
  static const Color outlineVariant = Color(0xFFCBC3D7);

  // ─── Error ───
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ─── Semantic Colors ───
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // ─── Password Strength ───
  static const Color strengthWeak = Color(0xFFEF4444);
  static const Color strengthFair = Color(0xFFF59E0B);
  static const Color strengthGood = Color(0xFF22C55E);
  static const Color strengthStrong = Color(0xFF10B981);

  // ─── Gradients ───
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6B38D4), Color(0xFFFD56A7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [Color(0xFF8455EF), Color(0xFFFD56A7)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ─── Legacy Aliases (for backward compatibility during migration) ───
  static const Color electricPurple = primary;
  static const Color neonBlue = Color(0xFF38BDF8);
  static const Color hotPink = secondaryContainer;

  // Legacy light/dark aliases (app is light-only, kept for widget compat)
  static const Color lightBackground = background;
  static const Color lightSurface = surfaceContainerLowest;
  static const Color lightOnSurface = onSurface;
  static const Color lightOnSurfaceVariant = onSurfaceVariant;
  static const Color lightOutlineVariant = outlineVariant;
  static const Color lightError = error;
  static const Color lightErrorContainer = errorContainer;
  static const Color darkBackground = inverseSurface;
  static const Color darkSurface = inverseSurface;
  static const Color darkOnSurface = inverseOnSurface;
  static const Color darkOnSurfaceVariant = Color(0xFF9CA3AF);
  static const Color darkOutlineVariant = Color(0xFF374151);
  static const Color darkError = Color(0xFFFCA5A5);
  static const Color darkErrorContainer = Color(0xFF7F1D1D);

  // Glass helpers
  static const Color glassDarkBg = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
}
