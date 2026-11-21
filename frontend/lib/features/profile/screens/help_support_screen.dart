import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/profile/widgets/settings_widgets.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

const _faqs = <(String, String)>[
  ('How does the AI stylist work?',
      'Tell it the occasion, your style, colours and budget. It asks follow-up questions, then searches real '
          'products from 60+ Pakistani stores (like Outfitters and Breakout) and ranks them for your body, size and taste.'),
  ('How is my size estimated?',
      'From the measurements in your profile and, if you do a body scan, from your photo. Where a product has its '
          "own size chart, we compare your measurements with that chart; otherwise we show the store's sizes "
          'without guessing.'),
  ('How long does virtual try-on take?',
      'About a minute per outfit — the AI redraws the garment on your photo. We send you a notification when '
          "it's ready, so you can keep browsing."),
  ('Are my photos private?',
      'Photos are used only for body analysis and try-on, are never shown to other users, and are deleted '
          'with your account. See Profile → Privacy & security.'),
  ('Where do the products come from?',
      "From the stores' own websites. Tapping a product opens the store's page, where you buy it — SmartFit "
          "doesn't sell anything itself."),
  ('How do I delete my account?',
      'Profile → Privacy & security → Delete account. You can also deactivate it instead and come back later.'),
];

/// FAQs, contact and bug reports.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _email(BuildContext context, {required String subject, String body = ''}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppStrings.supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    final opened = await launchUrl(uri).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('No email app found. Write to us at ${AppStrings.supportEmail}.'),
      ));
    }
  }

  Future<void> _reportBug(BuildContext context) async {
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!context.mounted) return;
    await _email(
      context,
      subject: 'SmartFit bug report',
      body: 'What happened:\n\n\nWhat I expected:\n\n\nSteps to repeat it:\n1.\n2.\n\n'
          '— App $version on ${defaultTargetPlatform.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SFScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxxl),
        children: [
          const SettingsPageHeader(title: 'Help & support', subtitle: "We're here to help"),
          SettingsSection(
            title: 'Contact',
            children: [
              SettingsTile(
                icon: Icons.mail_outline_rounded,
                tint: context.sf.info,
                title: 'Email support',
                subtitle: AppStrings.supportEmail,
                onTap: () => _email(context, subject: 'SmartFit support'),
              ),
              SettingsTile(
                icon: Icons.bug_report_outlined,
                tint: context.sf.warning,
                title: 'Report a bug',
                subtitle: 'Opens an email with your app version',
                onTap: () => _reportBug(context),
              ),
            ],
          ),
          SFEntrance(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.xs),
              child: Text('FREQUENT QUESTIONS',
                  style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted, letterSpacing: 1.1)),
            ),
          ),
          SFEntrance(
            index: 2,
            child: SFGlassCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Column(
                  children: [
                    for (final (q, a) in _faqs)
                      ExpansionTile(
                        title: Text(q, style: context.tt.titleSmall),
                        childrenPadding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(a, style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted))],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
