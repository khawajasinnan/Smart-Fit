import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/profile/widgets/settings_widgets.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// What powers SmartFit, with the models' licences (spec §23.8: IDM-VTON is
/// non-commercial, so the app must never be presented as commercial).
const _credits = <(String, String, String)>[
  ('AI stylist chat', 'Google Gemini', 'Google API terms'),
  ('Body analysis', 'Google MediaPipe Pose & Face', 'Apache 2.0'),
  ('Outfit ranking', 'Marqo-FashionCLIP', 'Apache 2.0'),
  ('Virtual try-on', 'IDM-VTON', 'CC BY-NC-SA 4.0 (non-commercial)'),
  ('Products', 'Outfitters and Breakout websites', "Each store's own terms"),
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SFScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxxl),
        children: [
          const SettingsPageHeader(title: 'About'),
          SFEntrance(
            child: Column(
              children: [
                const SFLogoMark(size: 72, glow: true),
                const SizedBox(height: AppSpace.md),
                const SFWordmark(fontSize: 30),
                Text(AppStrings.appTagline, style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted)),
                const SizedBox(height: AppSpace.xs),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => Text(
                    snap.hasData ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})' : ' ',
                    style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
              ],
            ),
          ),
          SettingsSection(
            title: 'About the app',
            index: 1,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text(
                  'SmartFit is a Final Year Project: an AI fashion stylist for Pakistan that recommends real '
                  'clothes from local stores, estimates your size, and lets you try outfits on virtually. '
                  'It is an academic, non-commercial project.',
                  style: context.tt.bodyMedium,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Powered by',
            index: 2,
            children: [
              for (final (what, by, licence) in _credits)
                SettingsTile(icon: Icons.auto_awesome_outlined, title: what, subtitle: '$by · $licence'),
            ],
          ),
          SettingsSection(
            title: 'Legal',
            index: 3,
            children: [
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Open-source licences',
                subtitle: 'Libraries used to build the app',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppStrings.appName,
                  applicationLegalese: 'Academic Final Year Project. Non-commercial.',
                ),
              ),
            ],
          ),
          Center(
            child: Text('Made in Pakistan 🇵🇰', style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted)),
          ),
        ],
      ),
    );
  }
}
