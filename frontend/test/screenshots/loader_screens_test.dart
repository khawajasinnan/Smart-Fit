import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/shared_widgets/page_loading_gate.dart';

import '../helpers/screenshot_harness.dart';

/// Visual review of the page loader. Skipped unless SF_SCREENSHOT_DIR is set.
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('page loader (${mode.name})', (tester) async {
      await pumpScreen(
        tester,
        const PageLoadingGate(child: Scaffold(body: Center(child: Text('The page underneath')))),
        mode: mode,
      );
      for (final ms in [300, 700]) {
        await tester.pump(Duration(milliseconds: ms));
      }
      await saveScreenshot(tester, 'loader_${mode.name}');
      await tester.pump(kPageLoadDuration); // the cover fades away
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('The page underneath'), findsOneWidget);
    }, skip: !screenshotsEnabled);
  }
}
