import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry in {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme}.entries) {
    group('${entry.key} theme', () {
      final theme = entry.value;
      final sf = theme.extension<SFColors>()!;

      test('has the SmartFit extension and the right brightness', () {
        expect(sf, isNotNull);
        expect(theme.brightness, entry.key == 'dark' ? Brightness.dark : Brightness.light);
      });

      test('body and muted text meet WCAG AA (4.5:1) on page and card', () {
        for (final bg in [theme.scaffoldBackgroundColor, sf.surfaceElevated]) {
          expect(contrast(sf.ink, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(theme.colorScheme.onSurfaceVariant, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(sf.accentText, bg), greaterThanOrEqualTo(4.5), reason: 'pink text');
        }
      });

      test('primary buttons are readable', () {
        expect(contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary), greaterThanOrEqualTo(4.5));
      });

      test('display type uses Space Grotesk, body uses Inter', () {
        expect(theme.textTheme.displayLarge!.fontFamily, 'SpaceGrotesk');
        expect(theme.textTheme.bodyLarge!.fontFamily, 'Inter');
      });
    });
  }

  test('extension interpolates (smooth theme switch)', () {
    final mid = SFColors.light.lerp(SFColors.dark, 0.5);
    expect(mid.ink, isNot(SFColors.light.ink));
    expect(SFColors.light.lerp(null, 0.5), same(SFColors.light));
  });
}
