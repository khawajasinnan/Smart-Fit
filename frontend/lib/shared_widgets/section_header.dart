import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// Section title with an optional eyebrow label and trailing action
/// (e.g. "TRENDING IN PAKISTAN" / "Street to studio" / "See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.eyebrow, this.actionLabel, this.onAction});

  final String title;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(eyebrow!.toUpperCase(), style: context.tt.labelSmall?.copyWith(color: context.sf.accentText)),
                const SizedBox(height: AppSpace.xxs),
              ],
              Text(title, style: context.tt.headlineSmall),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text(actionLabel!), const SizedBox(width: 2), const Icon(Icons.arrow_forward_rounded, size: 16)],
            ),
          ),
      ],
    );
  }
}
