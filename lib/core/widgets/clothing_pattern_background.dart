import 'package:flutter/material.dart';

/// A reusable background widget that draws stylish clothing and fashion icons
/// in soft pink with low opacity, creating a chic Gen-Z aesthetic wallpaper.
class ClothingPatternBackground extends StatelessWidget {
  /// The opacity of the pink clothing icons (defaults to 0.16 for clear visibility).
  final double opacity;

  /// The color of the clothing icons (defaults to deep vibrant pink 0xFFD81B60).
  final Color color;

  /// Optional child to stack on top of the background.
  final Widget? child;

  const ClothingPatternBackground({
    super.key,
    this.opacity = 0.16,
    this.color = const Color(0xFFD81B60),
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure effective opacity is dark and clearly perceptible (at least 0.16)
    final effectiveOpacity = opacity < 0.14 ? 0.16 : opacity;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ClothingIconsPainter(
                color: color.withValues(alpha: effectiveOpacity),
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _ClothingIconsPainter extends CustomPainter {
  final Color color;

  _ClothingIconsPainter({required this.color});

  // Curated list of fashion & clothing Material Icons
  static const List<IconData> _fashionIcons = [
    Icons.checkroom_rounded,          // Hanger / Wardrobe
    Icons.dry_cleaning_rounded,       // Dress / Suit
    Icons.shopping_bag_outlined,      // Shopping bag
    Icons.auto_awesome,               // Sparkle / Magic style
    Icons.diamond_outlined,           // Luxury accessory
    Icons.content_cut_rounded,        // Tailor / Fashion designer scissors
    Icons.style_outlined,             // Tag / Style
    Icons.straighten_outlined,        // Measuring tape
    Icons.local_mall_outlined,        // Fashion tote bag
    Icons.brush_outlined,             // Stylist brush / sketch
    Icons.flare_rounded,              // Fashion star
    Icons.favorite_border_rounded,    // Fashion love
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const double stepX = 72.0;
    const double stepY = 72.0;
    const double iconSize = 26.0;

    int colIndex = 0;
    for (double x = -10; x < size.width + 40; x += stepX, colIndex++) {
      int rowIndex = 0;
      for (double y = -10; y < size.height + 40; y += stepY, rowIndex++) {
        // Stagger every second column for diamond/hex distribution
        final double offsetY = (colIndex % 2 == 1) ? stepY / 2 : 0.0;
        final double drawX = x;
        final double drawY = y + offsetY;

        final int iconIdx = (colIndex * 7 + rowIndex * 3) % _fashionIcons.length;
        final IconData icon = _fashionIcons[iconIdx];

        // Slight alternating rotation (-15 to +15 deg)
        final double angle = (((colIndex + rowIndex) % 3) - 1) * 0.18;

        canvas.save();
        canvas.translate(drawX + iconSize / 2, drawY + iconSize / 2);
        canvas.rotate(angle);

        textPainter.text = TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: iconSize,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(-iconSize / 2, -iconSize / 2),
        );

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ClothingIconsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
