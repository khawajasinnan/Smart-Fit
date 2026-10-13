import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';

/// SmartFit primary button with glow effect
/// Light-only design — Luminous Vibe aesthetic
enum SFButtonVariant { primary, ghost, outline, danger }

class SFButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final SFButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;
  final bool showGlow;

  const SFButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SFButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
    this.showGlow = true,
  });

  @override
  State<SFButton> createState() => _SFButtonState();
}

class _SFButtonState extends State<SFButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            HapticFeedback.lightImpact();
            widget.onPressed?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
            child: Container(
              width: widget.width ?? double.infinity,
              height: widget.height,
              decoration: _buildDecoration(),
              child: Material(
                color: Colors.transparent,
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(
                              _foregroundColor(),
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 20, color: _foregroundColor()),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.label,
                              style: AppTextStyles.buttonLg.copyWith(
                                color: _foregroundColor(),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration() {
    switch (widget.variant) {
      case SFButtonVariant.primary:
        return BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(9999),
          boxShadow: widget.showGlow && widget.onPressed != null
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        );
      case SFButtonVariant.ghost:
        return BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: AppColors.primary,
            width: 1.5,
          ),
        );
      case SFButtonVariant.outline:
        return BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: AppColors.outlineVariant,
          ),
        );
      case SFButtonVariant.danger:
        return BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(9999),
        );
    }
  }

  Color _foregroundColor() {
    switch (widget.variant) {
      case SFButtonVariant.primary:
        return Colors.white;
      case SFButtonVariant.ghost:
        return AppColors.primary;
      case SFButtonVariant.outline:
        return AppColors.onSurface;
      case SFButtonVariant.danger:
        return AppColors.error;
    }
  }
}
