import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/shared_widgets/ai_processing_indicator.dart';
import 'package:smartfit/shared_widgets/coming_soon_view.dart';
import 'package:smartfit/shared_widgets/section_header.dart';
import 'package:smartfit/shared_widgets/sf_bottom_nav_bar.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:smartfit/shared_widgets/skeletons.dart';
import 'package:smartfit/shared_widgets/state_views.dart';

import '../helpers/screenshot_harness.dart';

/// Visual review of the shared widget kit in light and dark mode.
/// Skipped unless SF_SCREENSHOT_DIR is set (see screenshot_harness.dart).
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode.name;

    testWidgets('kit: controls ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        mode: mode,
        SFScaffold(
          bottomNavigationBar: SFBottomNavBar(currentIndex: 0, onTap: (_) {}),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SectionHeader(eyebrow: 'Widget kit', title: 'Buttons', actionLabel: 'See all'),
              const SizedBox(height: 16),
              SFButton(label: 'Get started', trailingIcon: Icons.arrow_forward_rounded, onPressed: () {}),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: SFButton(label: 'Secondary', variant: SFButtonVariant.secondary, onPressed: () {})),
                  const SizedBox(width: 12),
                  Expanded(child: SFButton(label: 'Outline', variant: SFButtonVariant.outline, onPressed: () {})),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: SFButton(label: 'Delete', variant: SFButtonVariant.danger, onPressed: () {})),
                  const SizedBox(width: 12),
                  const Expanded(child: SFButton(label: 'Disabled')),
                ],
              ),
              const SizedBox(height: 12),
              SFButton(label: 'Saving', isLoading: true, onPressed: () {}),
              const SizedBox(height: 24),
              SFGlassCard(
                child: Builder(
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Glass card', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text('Frosted surface used for hero and info cards.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Loading'),
              const SizedBox(height: 12),
              const ListRowSkeleton(),
              const ListRowSkeleton(),
            ],
          ),
        ),
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'kit_controls_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('kit: states ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        mode: mode,
        SFScaffold(
          body: Column(
            children: [
              const SizedBox(height: 24),
              const AiProcessingIndicator(messages: ['Reading your style...', 'Searching 40+ brands...']),
              const SizedBox(height: 24),
              Expanded(
                child: EmptyStateView(
                  icon: Icons.favorite_border_rounded,
                  title: 'Nothing saved yet',
                  message: 'Tap the heart on any outfit to keep it here.',
                  actionLabel: 'Find outfits',
                  onAction: () {},
                ),
              ),
              Expanded(child: ErrorStateView(onRetry: () {})),
            ],
          ),
        ),
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'kit_states_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('kit: coming soon ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        mode: mode,
        wrapInScaffold: true,
        ComingSoonView(
          imageUrl: '',
          eyebrow: 'Coming soon',
          title: 'Virtual Try-On',
          description: 'See any outfit from Pakistani brands on your own photo before you buy.',
          points: const [
            ComingSoonPoint(Icons.checkroom_rounded, 'Diffusion try-on', 'Photo-real fit on your pose'),
            ComingSoonPoint(Icons.straighten_rounded, 'Size aware', 'Uses your saved measurements'),
          ],
          requirements: 'SFR-026 – SFR-028',
          actionLabel: 'Ask the AI Stylist',
          onAction: () {},
        ),
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'kit_coming_soon_$suffix');
    }, skip: !screenshotsEnabled);
  }
}
