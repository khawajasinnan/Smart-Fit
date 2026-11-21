import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// The "3D" in design.md §5.2: cards lean toward the finger with a subtle
/// perspective rotation (max [maxTiltDegrees]) and spring back on release.
/// Uses a raw Listener so it never steals scroll or tap gestures.
class TiltCard extends StatefulWidget {
  const TiltCard({super.key, required this.child, this.maxTiltDegrees = 8});

  final Widget child;
  final double maxTiltDegrees;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Offset _tilt = Offset.zero; // x = rotateY, y = rotateX, in -1..1
  Offset _releasedFrom = Offset.zero;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() {
      final t = Curves.easeOutBack.transform(_spring.value);
      setState(() => _tilt = Offset.lerp(_releasedFrom, Offset.zero, t)!);
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _update(Offset local, Size size) {
    if (context.reduceMotion || size.isEmpty) return;
    _spring.stop();
    final dx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _tilt = Offset(dx, dy));
  }

  void _release() {
    if (_tilt == Offset.zero) return;
    _releasedFrom = _tilt;
    _spring.forward(from: 0);
  }

  /// Rotation in radians for the current tilt (exposed for tests).
  @visibleForTesting
  double get maxAppliedRadians => math.max(_tilt.dx.abs(), _tilt.dy.abs()) * widget.maxTiltDegrees * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final maxRad = widget.maxTiltDegrees * math.pi / 180;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          onPointerDown: (e) => _update(e.localPosition, size),
          onPointerMove: (e) => _update(e.localPosition, size),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-_tilt.dy * maxRad)
              ..rotateY(_tilt.dx * maxRad),
            child: widget.child,
          ),
        );
      },
    );
  }
}
