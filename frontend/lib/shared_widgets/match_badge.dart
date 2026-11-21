import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:flutter/material.dart';

/// Match percentage badge per design.md §2.5
/// ≥90%: gradient accent600→primary600 pill, white text
/// 80-89%: filled primary600 pill, white text  
/// <80%: outline ink400 pill, ink700 text
class MatchBadge extends StatelessWidget {
  final int matchPercent;
  final double fontSize;

  const MatchBadge({
    super.key,
    required this.matchPercent,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isHighMatch = matchPercent >= 90;
    final isMediumMatch = matchPercent >= 80;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: isHighMatch
            ? context.sf.brandGradient
            : null,
        color: !isHighMatch && isMediumMatch ? context.sf.surfaceSunken : null,
        borderRadius: BorderRadius.circular(999),
        border: !isMediumMatch
            ? Border.all(color: context.cs.outline, width: 1.2)
            : null,
      ),
      child: Text(
        '$matchPercent% Match',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: isHighMatch ? context.sf.onBrand : isMediumMatch ? context.sf.ink : context.cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
