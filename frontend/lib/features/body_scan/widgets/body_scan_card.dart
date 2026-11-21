import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';

/// The scan results as a chat message.
class BodyScanCard extends StatelessWidget {
  const BodyScanCard({super.key, required this.summary});

  final ScanSummary summary;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final tt = Theme.of(context).textTheme;
    final rows = [
      if (summary.bodyShape != null) (Icons.accessibility_new_rounded, 'Body', summary.bodyShape!),
      if (summary.shoulderText != null) (Icons.straighten_rounded, 'Shoulders', summary.shoulderText!),
      if (summary.faceShape != null) (Icons.face_retouching_natural_rounded, 'Face', summary.faceShape!),
      if (summary.skinTone != null) (Icons.palette_outlined, 'Skin tone', summary.skinTone!),
      if (summary.size != null) (Icons.checkroom_rounded, 'Size', summary.size!),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md, right: AppSpace.xxl),
      child: SFGlassCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SFLogoMark(size: 26),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text('Body & face scan', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                const Icon(Icons.verified_rounded, color: AppColors.success, size: 20),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (rows.isEmpty)
              Text(summary.note ?? 'Nothing could be measured from this photo.', style: tt.bodyMedium)
            else
              for (final (icon, label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: context.sf.highlight),
                      const SizedBox(width: AppSpace.xs),
                      SizedBox(width: 78, child: Text(label, style: tt.bodyMedium?.copyWith(color: sf.textMuted))),
                      Expanded(child: Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
            if (summary.agreement != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text('MediaPipe vs HRNet: ${summary.agreement}', style: tt.bodySmall?.copyWith(color: sf.textMuted)),
            ],
            if (rows.isNotEmpty && summary.note != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(summary.note!, style: tt.bodySmall?.copyWith(color: sf.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
