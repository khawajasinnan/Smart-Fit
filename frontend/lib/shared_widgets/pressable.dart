import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/theme/app_tokens.dart';

/// Tactile press feedback for any tappable surface (design.md §5.2):
/// scales to [pressedScale] while held and gives a light haptic on tap.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
    this.semanticLabel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _active => widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _active ? (_) => _set(true) : null,
        onTapCancel: _active ? () => _set(false) : null,
        onTapUp: _active ? (_) => _set(false) : null,
        onTap: _active
            ? () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onTap?.call();
              }
            : null,
        onLongPress: _active ? widget.onLongPress : null,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: AppDurations.instant,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
