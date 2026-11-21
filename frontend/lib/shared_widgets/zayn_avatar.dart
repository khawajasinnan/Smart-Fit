import 'package:flutter/material.dart';

/// Zayn's face, the AI stylist's icon everywhere in the app (spec §23.16):
/// a 3D render of him winking (assets/mascot/zayn_avatar.png, made from
/// assets/mascot/zayn.html in portrait mode).
class ZaynAvatar extends StatelessWidget {
  const ZaynAvatar({super.key, this.size = 36, this.ring = false});

  static const asset = 'assets/mascot/zayn_avatar.png';

  final double size;

  /// A thin white ring (on gradient buttons).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Zayn, your AI stylist',
        errorBuilder: (_, _, _) => Icon(Icons.auto_awesome_rounded, size: size * 0.6, color: Colors.white),
      ),
    );
    if (!ring) return SizedBox(width: size, height: size, child: image);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.9)),
      child: image,
    );
  }
}
