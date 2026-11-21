import 'dart:ui';

import 'package:flutter/material.dart';

/// Round frosted icon button for controls that sit on top of photos
/// (back / close on hero images). Readable on any image, light or dark.
class SFGlassIconButton extends StatelessWidget {
  const SFGlassIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip, this.size = 44});

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.black.withValues(alpha: 0.28),
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: Colors.white, size: size * 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
