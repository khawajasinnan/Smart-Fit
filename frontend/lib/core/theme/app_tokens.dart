import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:smartfit/core/constants/app_colors.dart';

/// Spacing scale — 4 px grid (design.md §4).
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;
  static const double giant = 64;

  /// Side gutter of every screen.
  static const double gutter = 20;
}

/// Corner radii — generous and pill-leaning (design.md §4).
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion durations (design.md §5.1).
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration entrance = Duration(milliseconds: 550);
  static const Duration ambient = Duration(seconds: 9);
}

/// Motion curves (design.md §5.1).
abstract final class AppCurves {
  static const Curve enter = Curves.easeOutCubic;
  static const Curve move = Curves.easeInOutCubic;
  static const Curve playful = Curves.easeOutBack;
}

/// Quiet, neutral elevation: hairline borders do most of the work (18 Nov 2026).
abstract final class AppShadows {
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Formerly a coloured glow; now nothing (no glows in the flat design).
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) => const [];

  static const List<BoxShadow> darkMd = [];

  static final List<BoxShadow> brandGlow = glow(AppColors.accent600);
}
