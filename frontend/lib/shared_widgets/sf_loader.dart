import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// SmartFit's loading indicator: a spinning 3D tee on a hanger inside a
/// rounded gradient ring (spec §23.19; frames in assets/loader/, made by
/// tool/loader_cloth/).
///
/// Below [_logoMinSize] the tee would be unreadable, so small loaders
/// (inside buttons, list rows) are just the ring. Honours "remove
/// animations" (the ring and the tee stay still).
class SFLoader extends StatefulWidget {
  const SFLoader({super.key, this.size = 72, this.label, this.color});

  /// Small ring for buttons and inline rows.
  const SFLoader.small({super.key, this.color}) : size = 20, label = null;

  final double size;

  /// Optional caption under the loader, e.g. "Analyzing your photo…".
  final String? label;

  /// Single ring colour (e.g. white on a filled button); default is the brand gradient.
  final Color? color;

  static const double _logoMinSize = 40;

  @override
  State<SFLoader> createState() => _SFLoaderState();
}

class _SFLoaderState extends State<SFLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _turns = (_turns + 1) % 2;
    });

  /// Which half of the tee's turn this ring turn shows (0 or 1).
  int _turns = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final withLogo = size >= SFLoader._logoMinSize;
    final stroke = withLogo ? math.max(4.0, size * 0.075) : math.max(2.0, size * 0.12);
    final ring = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _spin,
            builder: (context, _) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: _spin.value,
                stroke: stroke,
                track: (widget.color ?? context.sf.ink).withValues(alpha: 0.10),
                color: widget.color,
                from: context.sf.highlight,
              ),
            ),
          ),
          if (withLogo)
            AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => ClothFrames.frame(
                // two frames per ring turn would look jerky: the tee turns once every ~2 ring turns
                ((_spin.value + _turns) * ClothFrames.count / 2).floor() % ClothFrames.count,
                size: size * 0.66,
              ),
            ),
        ],
      ),
    );
    return Semantics(
      label: widget.label ?? 'Loading',
      child: widget.label == null
          ? ring
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ring,
                const SizedBox(height: 14),
                Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.sf.textMuted),
                ),
              ],
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.stroke, required this.track, this.color, this.from = AppColors.primary600});

  final double progress;
  final double stroke;
  final Color track;
  final Color? color;

  /// The arc's first colour (violet on light, lime on dark), then pink.
  final Color from;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);

    // The arc breathes between ~25% and ~75% of the circle while it turns.
    final sweep = math.pi * (0.5 + 1.0 * (0.5 - 0.5 * math.cos(progress * math.pi * 2)));
    final start = progress * math.pi * 2 * 1.5 - math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        colors: [from, AppColors.accent600],
        transform: GradientRotation(start),
      ).createShader(rect);
    }
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.stroke != stroke || old.track != track || old.color != color || old.from != from;
}

/// The loader's spinning 3D tee: 24 pre-rendered frames.
class ClothFrames {
  ClothFrames._();

  static const count = 24;
  static String path(int i) => 'assets/loader/cloth_${i.toString().padLeft(2, '0')}.png';

  static bool _precached = false;

  /// Decode every frame once up front so the first spin doesn't flicker.
  static void precache(BuildContext context) {
    if (_precached) return;
    _precached = true;
    for (var i = 0; i < count; i++) {
      precacheImage(AssetImage(path(i)), context).catchError((Object _) {});
    }
  }

  static Widget frame(int i, {required double size}) => Image.asset(
        path(i),
        width: size,
        height: size,
        gaplessPlayback: true, // no blank between frames
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
      );
}
