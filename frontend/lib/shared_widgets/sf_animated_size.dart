import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// AnimatedSize that respects reduce-motion. Never use AnimatedSize with
/// Duration.zero: it finishes inside its own layout pass and asserts
/// ("RenderAnimatedSize was mutated in its own performLayout").
class SFAnimatedSize extends StatelessWidget {
  const SFAnimatedSize({super.key, required this.child, this.alignment = Alignment.topCenter});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return AnimatedSize(duration: AppDurations.base, curve: AppCurves.enter, alignment: alignment, child: child);
  }
}
