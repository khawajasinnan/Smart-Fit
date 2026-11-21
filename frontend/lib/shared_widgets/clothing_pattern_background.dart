import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// SmartFit's signature wallpaper: softly rotated fashion icons (hanger,
/// dress, bag, tape, scissors...) tiled behind content.
///
/// Theme-aware by default (tint + opacity from [SFColors]); pass [color] /
/// [opacity] to override. The old version forced a minimum opacity of 0.16,
/// which overrode every caller and made busy screens noisy.
class ClothingPatternBackground extends StatelessWidget {
  const ClothingPatternBackground({
    super.key,
    this.opacity,
    this.color,
    this.child,
    this.density = 1,
  });

  final double? opacity;
  final Color? color;
  final Widget? child;

  /// 1 = default spacing; < 1 spreads icons out further.
  final double density;

  /// On: the user wants the clothing icons behind content (pink, 18 Nov 2026).
  static const bool enabled = true;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child ?? const SizedBox.shrink();
    final sf = context.sf;
    final tint = (color ?? sf.patternTint).withValues(alpha: (opacity ?? sf.patternOpacity).clamp(0, 1).toDouble());
    final pattern = IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ClothingIconsPainter(color: tint, step: 72 / density.clamp(0.5, 2)),
          size: Size.infinite,
        ),
      ),
    );
    if (child == null) return pattern;
    return Stack(fit: StackFit.expand, children: [pattern, child!]);
  }
}

class _ClothingIconsPainter extends CustomPainter {
  _ClothingIconsPainter({required this.color, required this.step});

  final Color color;
  final double step;

  static const List<IconData> _fashionIcons = [
    Icons.checkroom_rounded,
    Icons.dry_cleaning_rounded,
    Icons.shopping_bag_outlined,
    Icons.auto_awesome,
    Icons.diamond_outlined,
    Icons.content_cut_rounded,
    Icons.style_outlined,
    Icons.straighten_outlined,
    Icons.local_mall_outlined,
    Icons.brush_outlined,
    Icons.flare_rounded,
    Icons.favorite_border_rounded,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const double iconSize = 24;

    var col = 0;
    for (double x = -10; x < size.width + 40; x += step, col++) {
      var row = 0;
      for (double y = -10; y < size.height + 40; y += step, row++) {
        // Stagger every second column for a diamond layout.
        final drawY = y + (col.isOdd ? step / 2 : 0);
        final icon = _fashionIcons[(col * 7 + row * 3) % _fashionIcons.length];
        final angle = (((col + row) % 3) - 1) * 0.18;

        canvas
          ..save()
          ..translate(x + iconSize / 2, drawY + iconSize / 2)
          ..rotate(angle);
        textPainter
          ..text = TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(fontSize: iconSize, fontFamily: icon.fontFamily, package: icon.fontPackage, color: color),
          )
          ..layout()
          ..paint(canvas, const Offset(-iconSize / 2, -iconSize / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ClothingIconsPainter old) => old.color != color || old.step != step;
}
