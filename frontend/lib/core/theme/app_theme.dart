import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// SmartFit themes — light (off-white, near-black ink, neon-green fills) and
/// dark (near-black + neon green), built from the same recipe (18 Nov 2026).
class AppTheme {
  AppTheme._();

  // Kept for existing widgets; new code uses AppRadius.
  static const double radiusSm = AppRadius.sm;
  static const double radiusMd = AppRadius.md;
  static const double radiusLg = AppRadius.lg;
  static const double radiusXl = AppRadius.lg;
  static const double radiusXxl = AppRadius.xl;
  static const double radiusFull = AppRadius.pill;

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primary600,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primary100,
          onPrimaryContainer: AppColors.primary700,
          secondary: AppColors.greenDeep,
          onSecondary: Colors.white,
          secondaryContainer: AppColors.neonGreen,
          onSecondaryContainer: AppColors.ink900,
          tertiary: AppColors.tertiary,
          onTertiary: Colors.white,
          error: AppColors.error,
          onError: Colors.white,
          errorContainer: AppColors.errorContainer,
          onErrorContainer: AppColors.onErrorContainer,
          surface: AppColors.surface0,
          onSurface: AppColors.ink900,
          onSurfaceVariant: AppColors.ink700,
          surfaceContainerLowest: AppColors.surface1,
          surfaceContainerLow: AppColors.surfaceContainerLow,
          surfaceContainer: AppColors.surfaceContainer,
          surfaceContainerHigh: AppColors.surfaceContainerHigh,
          surfaceContainerHighest: AppColors.surfaceContainerHighest,
          outline: AppColors.outline,
          outlineVariant: AppColors.border,
          inverseSurface: AppColors.inverseSurface,
          onInverseSurface: AppColors.inverseOnSurface,
          inversePrimary: AppColors.primary400,
          surfaceTint: Colors.transparent,
          shadow: Colors.black,
          scrim: Colors.black,
        ),
        sf: SFColors.light,
      );

  /// Near-black with the neon green for buttons, links, selection and progress.
  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.neonGreen,
          onPrimary: AppColors.ink900,
          primaryContainer: Color(0xFF0E2E16),
          onPrimaryContainer: Color(0xFFB8F5C5),
          secondary: AppColors.neonGreen,
          onSecondary: AppColors.ink900,
          secondaryContainer: Color(0xFF0E2E16),
          onSecondaryContainer: Color(0xFFB8F5C5),
          tertiary: AppColors.neonGreen,
          onTertiary: Colors.black,
          error: AppColors.darkError,
          onError: AppColors.ink900,
          errorContainer: AppColors.darkErrorContainer,
          onErrorContainer: Color(0xFFFFDAD6),
          surface: AppColors.darkSurface0,
          onSurface: AppColors.darkInk,
          onSurfaceVariant: AppColors.darkMuted,
          surfaceContainerLowest: AppColors.darkBg,
          surfaceContainerLow: Color(0xFF0E110E),
          surfaceContainer: AppColors.darkSurface1,
          surfaceContainerHigh: AppColors.darkSurface2,
          surfaceContainerHighest: Color(0xFF232823),
          outline: Color(0xFF5A635B),
          outlineVariant: AppColors.darkBorder,
          inverseSurface: AppColors.darkInk,
          onInverseSurface: AppColors.ink900,
          inversePrimary: AppColors.greenDeep,
          surfaceTint: Colors.transparent,
          shadow: Colors.black,
          scrim: Colors.black,
        ),
        sf: SFColors.dark,
      );

  /// Type scale (design.md §3), bolder for the premium editorial look:
  /// Space Grotesk for display/headlines, Inter for everything read at length.
  static TextTheme _textTheme(Color ink, Color muted) {
    const sg = AppTextStyles.headlineFont;
    const inter = AppTextStyles.bodyFont;
    return TextTheme(
      displayLarge: TextStyle(fontFamily: sg, fontSize: 48, height: 1.05, fontWeight: FontWeight.w700, letterSpacing: -1.4, color: ink),
      displayMedium: TextStyle(fontFamily: sg, fontSize: 40, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -1.0, color: ink),
      displaySmall: TextStyle(fontFamily: sg, fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: ink),
      headlineLarge: TextStyle(fontFamily: sg, fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: ink),
      headlineMedium: TextStyle(fontFamily: sg, fontSize: 24, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: ink),
      headlineSmall: TextStyle(fontFamily: sg, fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: ink),
      titleLarge: TextStyle(fontFamily: sg, fontSize: 18, height: 1.35, fontWeight: FontWeight.w600, color: ink),
      titleMedium: TextStyle(fontFamily: inter, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600, color: ink),
      titleSmall: TextStyle(fontFamily: inter, fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: ink),
      bodyLarge: TextStyle(fontFamily: inter, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: ink),
      bodyMedium: TextStyle(fontFamily: inter, fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, color: muted),
      bodySmall: TextStyle(fontFamily: inter, fontSize: 12, height: 1.35, fontWeight: FontWeight.w400, color: muted),
      labelLarge: TextStyle(fontFamily: inter, fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: ink),
      labelMedium: TextStyle(fontFamily: inter, fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: muted),
      labelSmall: TextStyle(fontFamily: inter, fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: muted),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required SFColors sf,
  }) {
    final isDark = brightness == Brightness.dark;
    final text = _textTheme(sf.ink, scheme.onSurfaceVariant);
    final fieldFill = isDark ? AppColors.darkSurface1 : AppColors.surface1;
    // Selected / active controls: neon green with dark marks, in both themes.
    const selectFill = AppColors.neonGreen;
    const onSelect = AppColors.ink900;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.surface0,
      canvasColor: isDark ? AppColors.darkBg : AppColors.surface0,
      fontFamily: AppTextStyles.bodyFont,
      textTheme: text,
      extensions: [sf],
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: sf.divider, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: sf.ink),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: sf.ink,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: AppColors.ink900,
          elevation: 0,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: AppColors.ink900,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(64, 52),
          side: BorderSide(color: scheme.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: border(sf.divider),
        enabledBorder: border(sf.divider),
        focusedBorder: border(sf.highlight, 1.8),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 1.8),
        hintStyle: text.bodyMedium?.copyWith(color: sf.textMuted),
        labelStyle: text.bodyMedium,
        floatingLabelStyle: text.labelMedium?.copyWith(color: sf.highlight),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        prefixIconColor: sf.textMuted,
        suffixIconColor: sf.textMuted,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: sf.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: sf.divider)),
      ),

      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: sf.divider),
        backgroundColor: sf.surfaceElevated,
        selectedColor: selectFill,
        labelStyle: text.labelMedium?.copyWith(color: sf.ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: onSelect),
        checkmarkColor: onSelect,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.ink900 : sf.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? selectFill : sf.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : sf.divider,
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: sf.highlight,
        inactiveTrackColor: sf.surfaceSunken,
        thumbColor: Colors.white,
        overlayColor: sf.highlight.withValues(alpha: 0.12),
        trackHeight: 6,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sf.surfaceElevated,
        modalBackgroundColor: sf.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: sf.divider,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sf.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurface2 : AppColors.ink900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.neonGreen, // on the dark snackbar in both themes
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? sf.highlight : scheme.primary,
        linearTrackColor: sf.surfaceSunken,
        circularTrackColor: Colors.transparent,
      ),

      // Pages pushed outside GoRouter's custom transitions (e.g. dialogs'
      // full-screen routes) still get the brand motion; iOS keeps swipe-back.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
          TargetPlatform.linux: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
        },
      ),
    );
  }
}
