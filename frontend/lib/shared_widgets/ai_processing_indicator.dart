import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// "The AI is working" indicator (SFR-021: show progress while analysing).
/// A rotating gradient ring around a sparkle, with status lines that rotate
/// every few seconds so long waits never look frozen.
class AiProcessingIndicator extends StatefulWidget {
  const AiProcessingIndicator({
    super.key,
    required this.messages,
    this.size = 72,
    this.compact = false,
  });

  /// Status lines, e.g. ['Reading your style...', 'Searching 40+ brands...'].
  final List<String> messages;
  final double size;

  /// Inline (row) variant for chat bubbles.
  final bool compact;

  @override
  State<AiProcessingIndicator> createState() => _AiProcessingIndicatorState();
}

class _AiProcessingIndicatorState extends State<AiProcessingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  Timer? _ticker;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.messages.length > 1) {
      _ticker = Timer.periodic(const Duration(milliseconds: 2400), (_) {
        if (mounted) setState(() => _index = (_index + 1) % widget.messages.length);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox(
      width: widget.compact ? 28 : widget.size,
      height: widget.compact ? 28 : widget.size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(progress: _spin.value, stroke: widget.compact ? 3 : 5, from: context.sf.highlight),
          child: Center(
            child: Icon(Icons.auto_awesome_rounded, size: widget.compact ? 14 : widget.size * 0.38, color: AppColors.accent600),
          ),
        ),
      ),
    );

    final message = widget.messages.isEmpty ? '' : widget.messages[_index];
    final text = AnimatedSwitcher(
      duration: AppDurations.slow,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: Text(
        message,
        key: ValueKey(message),
        textAlign: widget.compact ? TextAlign.start : TextAlign.center,
        style: (widget.compact ? context.tt.bodyMedium : context.tt.titleMedium)?.copyWith(color: context.sf.ink),
      ),
    );

    return Semantics(
      liveRegion: true,
      label: message,
      child: widget.compact
          ? Row(mainAxisSize: MainAxisSize.min, children: [ring, const SizedBox(width: AppSpace.sm), Flexible(child: text)])
          : Column(mainAxisSize: MainAxisSize.min, children: [ring, const SizedBox(height: AppSpace.lg), text]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.stroke, required this.from});

  final double progress;
  final double stroke;
  final Color from; // violet on light, lime on dark

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [from.withValues(alpha: 0), from, AppColors.accent600],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(rect);
    canvas.drawArc(rect.deflate(stroke / 2), progress * 2 * math.pi, math.pi * 1.6, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.from != from;
}
