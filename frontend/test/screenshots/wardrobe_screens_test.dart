import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/features/wardrobe/screens/wardrobe_screen.dart';

import '../helpers/fake_wardrobe.dart';
import '../helpers/screenshot_harness.dart';

/// Visual review of the wardrobe. Skipped unless SF_SCREENSHOT_DIR is set.
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('wardrobe (${mode.name})', (tester) async {
      await pumpScreen(tester, const WardrobeScreen(), mode: mode, overrides: [
        wardrobeNotifierProvider.overrideWith((ref) => FakeWardrobe(sampleWardrobe(DateTime.now()))),
      ]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'wardrobe_${mode.name}');
      await tester.tap(find.text('Jacquard Jacket'));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'wardrobe_flipped_${mode.name}');
    }, skip: !screenshotsEnabled);

    testWidgets('wardrobe empty (${mode.name})', (tester) async {
      await pumpScreen(tester, const WardrobeScreen(), mode: mode, overrides: [
        wardrobeNotifierProvider.overrideWith((ref) => FakeWardrobe(const [])),
      ]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'wardrobe_empty_${mode.name}');
    }, skip: !screenshotsEnabled);
  }
}
