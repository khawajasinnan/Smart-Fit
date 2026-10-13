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
            ? const LinearGradient(
                colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: !isHighMatch && isMediumMatch ? const Color(0xFF6C4CE0) : null,
        borderRadius: BorderRadius.circular(999),
        border: !isMediumMatch
            ? Border.all(color: const Color(0xFF8B85A0), width: 1.2)
            : null,
      ),
      child: Text(
        '$matchPercent% Match',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: isMediumMatch ? Colors.white : const Color(0xFF443F54),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
