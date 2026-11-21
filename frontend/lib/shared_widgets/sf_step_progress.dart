import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// Segmented "step x of n" bar for multi-step flows (register, password
/// reset, profile setup). Completed and current segments use the brand
/// gradient.
class SFStepProgress extends StatelessWidget {
  const SFStepProgress({super.key, required this.step, required this.total});

  /// 1-based current step.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Semantics(
      label: 'Step $step of $total',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
                curve: AppCurves.enter,
                height: 4,
                decoration: BoxDecoration(
                  gradient: i <= step ? sf.brandGradient : null,
                  color: i <= step ? null : sf.divider,
                  borderRadius: AppRadius.pillAll,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpace.sm),
          Text('$step/$total', style: context.tt.labelMedium),
        ],
      ),
    );
  }
}
