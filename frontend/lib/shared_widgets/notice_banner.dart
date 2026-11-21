import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

enum NoticeTone { info, success, warning, error }

/// Inline notice (form errors, account restrictions, confirmations).
/// Text stays in the ink colour for contrast; the tone shows in the icon,
/// tint and border. Announced to screen readers when it appears.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message, this.title, this.tone = NoticeTone.info, this.onClose});

  final String message;
  final String? title;
  final NoticeTone tone;

  /// Shows a close button when set.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final (color, icon) = switch (tone) {
      NoticeTone.info => (sf.info, Icons.info_outline_rounded),
      NoticeTone.success => (sf.success, Icons.check_circle_outline_rounded),
      NoticeTone.warning => (sf.warning, Icons.gpp_maybe_outlined),
      NoticeTone.error => (context.cs.error, Icons.error_outline_rounded),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.16 : 0.09),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title!, style: context.tt.titleSmall),
                      const SizedBox(height: 2),
                    ],
                    Text(message, style: context.tt.bodyMedium?.copyWith(color: sf.ink)),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: sf.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
