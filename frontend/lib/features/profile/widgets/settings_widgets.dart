import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/sf_back_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';

/// A titled group of settings rows on one glass card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.index = 0});

  final String title;
  final List<Widget> children;
  final int index;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 64, color: context.sf.divider));
      rows.add(children[i]);
    }
    return SFEntrance(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.xs),
              child: Semantics(
                header: true,
                child: Text(
                  title.toUpperCase(),
                  style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted, letterSpacing: 1.1),
                ),
              ),
            ),
            SFGlassCard(
              padding: EdgeInsets.zero,
              child: Column(children: rows),
            ),
          ],
        ),
      ),
    );
  }
}

/// One settings row: tinted icon, title, optional subtitle and trailing widget.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tint;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.cs.error : (tint ?? context.cs.primary);
    // one node per row, like ListTile: title, subtitle and any switch read together. Without it a
    // section's only row merged with the section title ("SECURITY, Change password" was one
    // button to a screen reader; E2E run, 21 Nov 2026).
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDark ? 0.22 : 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.tt.titleSmall?.copyWith(color: destructive ? context.cs.error : context.sf.ink),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                trailing ??
                    (onTap != null
                        ? Icon(Icons.chevron_right_rounded, color: context.sf.textMuted)
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header row for settings sub-pages: back button + title.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Row(
        children: [
          const SFBackButton(),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: context.tt.headlineSmall)),
                if (subtitle != null)
                  Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
