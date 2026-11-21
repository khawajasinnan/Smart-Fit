import 'package:flutter/material.dart';

/// SmartFit colour tokens — "Neon Fit" (18 Nov 2026): near-black and off-white,
/// neon green for buttons and the logo, hot pink as the second accent (hearts,
/// badges, section labels, the background clothing icons). No gradients or glows.
///
/// Prefer theme-aware access in widgets: `Theme.of(context).colorScheme` and
/// the [SFColors] extension (`context.sf`) adapt to light/dark. The constants
/// here are the raw palette both themes are built from.
class AppColors {
  AppColors._();

  // ─── Brand palette (design.md §2.1) ───
  /// The signature neon green: fills, rings, progress, the logo. Text on it is [ink900].
  static const Color neonGreen = Color(0xFF39FF5A);

  /// Deep green: readable as text/icons on light surfaces (5.3:1 on white).
  static const Color greenDeep = Color(0xFF0A7D3B);

  static const Color primary600 = greenDeep; // light theme primary (text, icons, outlines)
  static const Color primary700 = Color(0xFF075F2C); // pressed
  static const Color primary400 = Color(0xFF5BD98A);
  static const Color primary100 = Color(0xFFE3F5E8); // green tint
  static const Color accent600 = neonGreen; // fills only, never under white text
  static const Color accent700 = greenDeep; // accent text on light
  static const Color accent100 = Color(0xFFE6FBEA);

  // ─── Neutrals (design.md §2.2) ───
  static const Color ink900 = Color(0xFF0A0C0A);
  static const Color ink700 = Color(0xFF3B433D);
  static const Color ink400 = Color(0xFF6E776F);
  static const Color surface0 = Color(0xFFF5F6F2); // page background (off-white)
  static const Color surface1 = Color(0xFFFFFFFF); // cards
  static const Color border = Color(0xFFE2E5DF);

  // ─── Dark palette (design.md §7) ───
  // Dark theme = near-black with the neon green (18 Nov 2026).
  static const Color darkBg = Color(0xFF050605);
  static const Color darkSurface0 = Color(0xFF0A0C0A);
  static const Color darkSurface1 = Color(0xFF121512);
  static const Color darkSurface2 = Color(0xFF1A1E1A);
  static const Color darkInk = Color(0xFFF2F5F1);
  static const Color darkMuted = Color(0xFF9AA39B);
  static const Color darkBorder = Color(0xFF252A25);
  // Old names, now all the one neon green (kept so existing widgets compile).
  static const Color neonPink = neonGreen;
  static const Color neonPinkButton = neonGreen; // filled buttons: dark text on it
  static const Color neonPinkDeep = Color(0xFF22D447);
  static const Color neonLime = neonGreen;

  // ─── Semantic (design.md §2.3) ───
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF5A524);
  static const Color info = Color(0xFF4C9BE0);

  // ─── Material roles used across existing screens ───
  // Kept by name so the codebase keeps compiling; values now follow the brand.
  static const Color primary = primary600;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = primary100;
  static const Color onPrimaryContainer = Color(0xFF053D1D);
  static const Color primaryFixed = primary100;
  static const Color primaryFixedDim = Color(0xFFB8EBC8);
  static const Color onPrimaryFixed = Color(0xFF053D1D);
  static const Color onPrimaryFixedVariant = primary700;
  static const Color inversePrimary = neonGreen;

  /// Green used for text/icons on light surfaces (contrast-safe).
  static const Color secondary = accent700;
  static const Color onSecondary = Color(0xFFFFFFFF);

  /// Neon fills (badges, highlights); dark text on them.
  static const Color secondaryContainer = accent600;
  static const Color onSecondaryContainer = ink900;
  static const Color secondaryFixed = accent100;
  static const Color secondaryFixedDim = Color(0xFFB8EBC8);
  static const Color onSecondaryFixed = ink900;
  static const Color onSecondaryFixedVariant = primary700;

  static const Color tertiary = Color(0xFF855000);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFA76500);
  static const Color onTertiaryContainer = Color(0xFFFFFBFF);
  static const Color tertiaryFixed = Color(0xFFFFDCBB);
  static const Color tertiaryFixedDim = Color(0xFFFFB869);
  static const Color onTertiaryFixed = Color(0xFF2C1700);
  static const Color onTertiaryFixedVariant = Color(0xFF673D00);

  static const Color background = surface0;
  static const Color onBackground = ink900;
  static const Color surface = surface0;
  static const Color onSurface = ink900;
  static const Color surfaceDim = Color(0xFFE6E8E3);
  static const Color surfaceBright = surface0;
  static const Color surfaceVariant = Color(0xFFEDEFEA);
  static const Color onSurfaceVariant = ink700;
  static const Color surfaceTint = primary600;

  static const Color surfaceContainerLowest = surface1;
  static const Color surfaceContainerLow = Color(0xFFF9FAF7);
  static const Color surfaceContainer = Color(0xFFF0F2EE);
  static const Color surfaceContainerHigh = Color(0xFFEAEDE8);
  static const Color surfaceContainerHighest = Color(0xFFE3E6E1);

  static const Color inverseSurface = ink900;
  static const Color inverseOnSurface = Color(0xFFF2F5F1);

  static const Color outline = Color(0xFF7A827B);
  static const Color outlineVariant = border;

  static const Color error = Color(0xFFE11D48); // readable on light (design error #F5304F is for fills)
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ─── Password strength ───
  static const Color strengthWeak = Color(0xFFEF4444);
  static const Color strengthFair = Color(0xFFF59E0B);
  static const Color strengthGood = Color(0xFF22C55E);
  static const Color strengthStrong = Color(0xFF10B981);

  // ─── "Gradients": flat neon now (kept as gradients so existing widgets compile) ───
  static const LinearGradient primaryGradient = LinearGradient(colors: [neonGreen, neonGreen]);

  static const LinearGradient buttonGradient = LinearGradient(colors: [neonGreen, neonGreen]);

  // ─── Legacy aliases (kept for existing widgets; migrate to theme access) ───
  static const Color electricPurple = primary600;
  static const Color neonBlue = Color(0xFF3B82F6);
  /// The second accent: hearts, badges, notification dot, background clothing icons.
  static const Color hotPink = Color(0xFFFF2E93);

  /// Pink for text on light surfaces (4.9:1 on white); on dark use [hotPink].
  static const Color pinkText = Color(0xFFD4157A);

  static const Color lightBackground = background;
  static const Color lightSurface = surface1;
  static const Color lightOnSurface = onSurface;
  static const Color lightOnSurfaceVariant = onSurfaceVariant;
  static const Color lightOutlineVariant = outlineVariant;
  static const Color lightError = error;
  static const Color lightErrorContainer = errorContainer;
  static const Color darkBackground = darkBg;
  static const Color darkOnSurface = darkInk;
  static const Color darkOnSurfaceVariant = darkMuted;
  static const Color darkOutlineVariant = darkBorder;
  static const Color darkError = Color(0xFFFB7185);
  static const Color darkErrorContainer = Color(0xFF4C0519);

  static const Color glassDarkBg = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  /// Swatches for the skin-tone picker (SFR-012), keyed by the stored label.
  /// Content colours, not theme colours: identical in light and dark mode.
  static const Map<String, Color> skinToneSwatches = {
    'Fair': Color(0xFFFCE4D6),
    'Light': Color(0xFFF5D0B0),
    'Medium': Color(0xFFD4A574),
    'Olive': Color(0xFFB08D57),
    'Brown': Color(0xFF8B6914),
    'Dark': Color(0xFF5C4033),
  };
}
