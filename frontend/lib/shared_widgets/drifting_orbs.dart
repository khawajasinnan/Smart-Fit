import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// The app's signature (design.md §1): large, soft gradient orbs drifting
/// slowly behind content. Painted with radial gradients (no blur filter, so
/// it's cheap), isolated in its own layer, frozen when the OS asks to reduce
/// motion, and paused automatically on hidden tabs (TickerMode).
class DriftingOrbs extends StatefulWidget {
  const DriftingOrbs({super.key, this.intensity = 1});

  /// 0..1 — scales the orbs' opacity (e.g. 0.6 behind dense content).
  final double intensity;

  @override
  State<DriftingOrbs> createState() => _DriftingOrbsState();
}

class _DriftingOrbsState extends State<DriftingOrbs> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppDurations.ambient);

  /// Off since the flat "Neon Fit" redesign (18 Nov 2026): no ambient colour blobs.
  static const bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) return;
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    if (_enabled) _controller.dispose(); // never created when off (it's late)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final sf = context.sf;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _OrbsPainter(
            animation: _controller,
            colors: [sf.orbA, sf.orbB, sf.orbC],
            intensity: widget.intensity.clamp(0, 1).toDouble(),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.animation, required this.colors, required this.intensity}) : super(repaint: animation);

  final Animation<double> animation;
  final List<Color> colors;
  final double intensity;

  // (anchor x, anchor y, radius as fraction of shortest side, phase, drift x, drift y)
  static const _orbs = [
    (0.05, 0.08, 0.95, 0.0, 0.10, 0.06),
    (0.98, 0.36, 0.80, 2.1, 0.08, 0.09),
    (0.20, 0.92, 0.85, 4.2, 0.09, 0.05),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * 2 * math.pi;
    final base = math.min(size.width, size.height);
    for (var i = 0; i < _orbs.length; i++) {
      final (ax, ay, r, phase, dx, dy) = _orbs[i];
      final center = Offset(
        size.width * (ax + dx * math.sin(t + phase)),
        size.height * (ay + dy * math.cos(t * 0.8 + phase)),
      );
      final radius = base * r * (1 + 0.06 * math.sin(t * 1.3 + phase));
      final color = colors[i];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: color.a * intensity),
            color.withValues(alpha: color.a * intensity * 0.35),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter old) => old.colors != colors || old.intensity != intensity;
}
