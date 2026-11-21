import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';

/// One capability a coming-soon feature will offer.
class ComingSoonPoint {
  const ComingSoonPoint(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

/// Polished placeholder for features scaffolded but not built yet (try-on,
/// hairstyle, look score). Explains what's coming instead of a dead end, and
/// offers something useful to do meanwhile.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({
    super.key,
    required this.imageUrl,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.points,
    this.requirements,
    this.actionLabel,
    this.onAction,
    this.leading,
  });

  final String imageUrl;
  final String eyebrow;
  final String title;
  final String description;
  final List<ComingSoonPoint> points;

  /// e.g. "SFR-026 – SFR-028" (shown small, for the FYP demo).
  final String? requirements;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional back button shown over the hero image.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final media = MediaQuery.of(context);
    final heroHeight = (media.size.height * 0.46).clamp(300.0, 440.0);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SafeNetworkImage(imageUrl: imageUrl, alignment: Alignment.topCenter),
                DecoratedBox(decoration: BoxDecoration(gradient: sf.heroGradient)),
                if (leading != null) Positioned(top: media.padding.top + AppSpace.xs, left: AppSpace.xs, child: leading!),
                Positioned(
                  left: AppSpace.gutter,
                  right: AppSpace.gutter,
                  bottom: AppSpace.xl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SFEntrance(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(gradient: sf.brandGradient, borderRadius: AppRadius.pillAll),
                          child: Text(
                            eyebrow.toUpperCase(),
                            style: context.tt.labelSmall?.copyWith(color: sf.onBrand, letterSpacing: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SFEntrance(
                        index: 1,
                        child: Text(title, style: context.tt.displaySmall?.copyWith(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xl,
            AppSpace.gutter,
            AppSpace.xl + media.padding.bottom,
          ),
          sliver: SliverList.list(
            children: [
              SFEntrance(
                index: 2,
                child: Text(description, style: context.tt.bodyLarge?.copyWith(color: sf.textMuted)),
              ),
              const SizedBox(height: AppSpace.xl),
              for (var i = 0; i < points.length; i++)
                SFEntrance(
                  index: 3 + i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: _PointRow(point: points[i]),
                  ),
                ),
              if (actionLabel != null) ...[
                const SizedBox(height: AppSpace.sm),
                SFEntrance(
                  index: 3 + points.length,
                  child: SFButton(label: actionLabel!, trailingIcon: Icons.arrow_forward_rounded, onPressed: onAction),
                ),
              ],
              if (requirements != null) ...[
                const SizedBox(height: AppSpace.lg),
                Center(
                  child: Text(
                    'In development · $requirements',
                    style: context.tt.labelSmall?.copyWith(color: sf.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});

  final ComingSoonPoint point;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: sf.surfaceElevated,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: sf.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: sf.brandGradient, borderRadius: AppRadius.mdAll),
            child: Icon(point.icon, color: sf.onBrand, size: 22),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.title, style: context.tt.titleMedium),
                const SizedBox(height: 2),
                Text(point.subtitle, style: context.tt.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
