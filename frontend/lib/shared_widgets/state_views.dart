import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';

/// Friendly empty state (rules.md §3.1: every data view has empty, error,
/// loading and success states).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: icon,
      title: title,
      message: message,
      action: actionLabel == null ? null : SFButton(label: actionLabel!, onPressed: onAction, width: 240),
    );
  }
}

/// Error state with a retry action — plain language, no codes (SRDS §4.3.2).
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'Please check your connection and try again.',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: Icons.wifi_tethering_error_rounded,
      title: title,
      message: message,
      iconColor: context.cs.error,
      action: onRetry == null
          ? null
          : SFButton(label: 'Try again', icon: Icons.refresh_rounded, variant: SFButtonVariant.outline, onPressed: onRetry, width: 200),
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({required this.icon, required this.title, required this.message, this.action, this.iconColor});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: AppSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: (iconColor ?? context.cs.primary).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: iconColor ?? context.cs.primary),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(title, textAlign: TextAlign.center, style: context.tt.headlineSmall),
            const SizedBox(height: AppSpace.xs),
            Text(message, textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: sf.textMuted)),
            if (action != null) ...[const SizedBox(height: AppSpace.xl), action!],
          ],
        ),
      ),
    );
  }
}
