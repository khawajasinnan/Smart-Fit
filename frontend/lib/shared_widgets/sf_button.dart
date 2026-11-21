import 'package:flutter/material.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/pressable.dart';

/// SmartFit button (design.md §6).
/// * primary — signature violet->pink gradient pill with a soft glow
/// * secondary — quiet neutral surface pill
/// * outline — transparent, outlined in the primary colour
/// * danger — destructive actions
/// * glass — translucent, for use over photos
enum SFButtonVariant { primary, secondary, outline, danger, glass }

class SFButton extends StatelessWidget {
  const SFButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SFButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.width,
    this.height = 56,
    this.showGlow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final SFButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final IconData? trailingIcon;
  final double? width;
  final double height;
  final bool showGlow;

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final cs = context.cs;
    final fg = switch (variant) {
      SFButtonVariant.primary => sf.onBrand,
      SFButtonVariant.glass => Colors.white,
      SFButtonVariant.outline => cs.primary,
      SFButtonVariant.secondary => sf.ink,
      SFButtonVariant.danger => cs.error,
    };

    final decoration = switch (variant) {
      SFButtonVariant.primary => BoxDecoration(
          gradient: sf.brandGradient,
          borderRadius: AppRadius.pillAll,
          boxShadow: showGlow && _enabled ? AppShadows.glow(AppColors.accent600, opacity: 0.3) : null,
        ),
      SFButtonVariant.outline => BoxDecoration(
          borderRadius: AppRadius.pillAll,
          border: Border.all(color: cs.primary, width: 1.5),
        ),
      SFButtonVariant.secondary => BoxDecoration(
          color: sf.surfaceElevated,
          borderRadius: AppRadius.pillAll,
          border: Border.all(color: sf.divider, width: 1.2),
        ),
      SFButtonVariant.danger => BoxDecoration(
          color: cs.errorContainer,
          borderRadius: AppRadius.pillAll,
        ),
      SFButtonVariant.glass => BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: AppRadius.pillAll,
          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        ),
    };

    final labelStyle = context.tt.labelLarge?.copyWith(color: fg, fontSize: 16);
    final content = isLoading
        ? SizedBox(
            width: 22,
            height: 22,
            child: SFLoader.small(color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 20, color: fg)],
            ],
          );

    return Semantics(
      // its own node: without it the label merged into the surrounding card (found by the E2E run,
      // 20 Nov 2026: "Ayesha Test, email, Edit profile" was one button to a screen reader)
      container: true,
      button: true,
      enabled: _enabled,
      label: isLoading ? '$label, loading' : label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null && !isLoading ? 0.5 : 1,
        child: Pressable(
          onTap: _enabled ? onPressed : null,
          child: AnimatedContainer(
            duration: AppDurations.base,
            width: width ?? double.infinity,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: decoration,
            alignment: Alignment.center,
            child: AnimatedSwitcher(duration: AppDurations.fast, child: KeyedSubtree(key: ValueKey(isLoading), child: content)),
          ),
        ),
      ),
    );
  }
}
