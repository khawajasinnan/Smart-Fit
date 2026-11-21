import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/shared_widgets/coming_soon_view.dart';
import 'package:smartfit/shared_widgets/drifting_orbs.dart';
import 'package:smartfit/shared_widgets/pressable.dart';
import 'package:smartfit/shared_widgets/sf_animated_size.dart';
import 'package:smartfit/shared_widgets/sf_bottom_nav_bar.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:smartfit/shared_widgets/tilt_card.dart';

/// Pumps [child] in the app theme, optionally with the OS "remove
/// animations" accessibility setting on.
Future<void> _pump(WidgetTester tester, Widget child, {bool reduceMotion = false}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: child,
    ),
  );
}

double _scaleOf(WidgetTester tester, Finder pressable) =>
    tester.widget<AnimatedScale>(find.descendant(of: pressable, matching: find.byType(AnimatedScale))).scale;

void main() {
  group('Pressable', () {
    testWidgets('scales to 0.96 while held and fires onTap on release', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Scaffold(
          body: Center(
            child: Pressable(onTap: () => taps++, child: const SizedBox(width: 120, height: 60)),
          ),
        ),
      );
      final pressable = find.byType(Pressable);
      expect(_scaleOf(tester, pressable), 1);

      final gesture = await tester.startGesture(tester.getCenter(pressable));
      await tester.pump();
      expect(_scaleOf(tester, pressable), 0.96);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, pressable), 1);
      expect(taps, 1);
    });

    testWidgets('does not scale or fire when disabled', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Scaffold(
          body: Center(
            child: Pressable(enabled: false, onTap: () => taps++, child: const SizedBox(width: 120, height: 60)),
          ),
        ),
      );
      final pressable = find.byType(Pressable);
      final gesture = await tester.startGesture(tester.getCenter(pressable));
      await tester.pump();
      expect(_scaleOf(tester, pressable), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });
  });

  group('Ambient motion respects reduce-motion', () {
    testWidgets('DriftingOrbs is frozen so pumpAndSettle completes', (tester) async {
      await _pump(tester, const DriftingOrbs(), reduceMotion: true);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('DriftingOrbs are off in the flat design: nothing drawn, nothing animating', (tester) async {
      await _pump(tester, const DriftingOrbs());
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.descendant(of: find.byType(DriftingOrbs), matching: find.byType(CustomPaint)), findsNothing);
    });

    testWidgets('SFScaffold (orbs + pattern) settles with reduce-motion', (tester) async {
      await _pump(tester, const SFScaffold(body: Text('content')), reduceMotion: true);
      await tester.pumpAndSettle();
      expect(find.text('content'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('nav bar centre glow stops with reduce-motion', (tester) async {
      await _pump(
        tester,
        Scaffold(bottomNavigationBar: SFBottomNavBar(currentIndex: 0, onTap: (_) {})),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('TiltCard', () {
    dynamic stateOf(WidgetTester tester) => tester.state(find.byType(TiltCard));
    final maxRadians = 8 * math.pi / 180;

    Future<void> pumpCard(WidgetTester tester, {bool reduceMotion = false}) => _pump(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(width: 200, height: 200, child: TiltCard(child: ColoredBox(color: Colors.purple))),
        ),
      ),
      reduceMotion: reduceMotion,
    );

    testWidgets('tilt never exceeds 8° even when dragged past the edge', (tester) async {
      await pumpCard(tester);
      final rect = tester.getRect(find.byType(TiltCard));

      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.topLeft + const Offset(1, 1));
      await tester.pump();
      final atCorner = stateOf(tester).maxAppliedRadians as double;
      expect(atCorner, greaterThan(0));
      expect(atCorner, lessThanOrEqualTo(maxRadians + 1e-9));

      // Pointer far outside the card: still clamped to the maximum.
      await gesture.moveTo(rect.bottomRight + const Offset(400, 400));
      await tester.pump();
      expect(stateOf(tester).maxAppliedRadians as double, closeTo(maxRadians, 1e-9));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(stateOf(tester).maxAppliedRadians as double, 0);
    });

    testWidgets('does not tilt with reduce-motion', (tester) async {
      await pumpCard(tester, reduceMotion: true);
      final rect = tester.getRect(find.byType(TiltCard));
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.topLeft + const Offset(1, 1));
      await tester.pump();
      expect(stateOf(tester).maxAppliedRadians as double, 0);
      await gesture.up();
    });
  });

  testWidgets('SFBottomNavBar reports the tapped tab index', (tester) async {
    final tapped = <int>[];
    await _pump(
      tester,
      Scaffold(bottomNavigationBar: SFBottomNavBar(currentIndex: 0, onTap: tapped.add)),
      reduceMotion: true,
    );
    await tester.tap(find.bySemanticsLabel('Try-On'));
    await tester.tap(find.bySemanticsLabel('Hair'));
    await tester.tap(find.bySemanticsLabel('AI Stylist'));
    await tester.tap(find.bySemanticsLabel('Saved'));
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.tap(find.bySemanticsLabel('Home'));
    expect(tapped, [1, 2, 3, 4, 5, 0]);
  });

  testWidgets('ComingSoonView renders its content and action', (tester) async {
    var actions = 0;
    await _pump(
      tester,
      Scaffold(
        body: ComingSoonView(
          imageUrl: '', // invalid URL → branded fallback, no network
          eyebrow: 'Coming soon',
          title: 'Virtual Try-On',
          description: 'See any outfit on you.',
          points: const [ComingSoonPoint(Icons.checkroom_rounded, 'Diffusion try-on', 'Photo-real fit')],
          requirements: 'SFR-026 – SFR-028',
          actionLabel: 'Ask the AI Stylist',
          onAction: () => actions++,
        ),
      ),
      reduceMotion: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Virtual Try-On'), findsOneWidget);
    expect(find.text('Diffusion try-on'), findsOneWidget);
    expect(find.text('In development · SFR-026 – SFR-028'), findsOneWidget);

    await tester.ensureVisible(find.text('Ask the AI Stylist'));
    await tester.tap(find.text('Ask the AI Stylist'));
    await tester.pumpAndSettle();
    expect(actions, 1);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('SFAnimatedSize grows and shrinks (reduceMotion: $reduceMotion)', (tester) async {
      final show = ValueNotifier(false);
      await _pump(
        tester,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => Column(
              children: [
                SFAnimatedSize(child: visible ? const SizedBox(height: 80, child: Text('notice')) : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
        reduceMotion: reduceMotion,
      );
      show.value = true;
      await tester.pumpAndSettle();
      expect(find.text('notice'), findsOneWidget);
      show.value = false;
      await tester.pumpAndSettle();
      expect(find.text('notice'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
