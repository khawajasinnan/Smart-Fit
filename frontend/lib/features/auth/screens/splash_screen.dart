import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/screens/welcome_view.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// App entry (route `/`).
///
/// While the app starts — or while a signed-in user's profile loads — this
/// shows the brand mark. Once a signed-out user is known it becomes the
/// landing page (welcome_view.dart) with the sign-up / log-in CTAs. Where a signed-in user goes
/// next is decided by the router guard (core/router/guards.dart); this screen
/// runs no timers and never navigates on its own.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = ref.watch(guardStateProvider);
    final showWelcome = !guard.bootstrapping && !guard.authed;

    return SFScaffold(
      body: AnimatedSwitcher(
        duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
        switchInCurve: AppCurves.enter,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(animation), child: child),
        ),
        child: showWelcome ? const WelcomeView(key: ValueKey('welcome')) : const _BootView(key: ValueKey('boot')),
      ),
    );
  }
}

// ── Boot ────────────────────────────────────────────────────────────────────

class _BootView extends StatelessWidget {
  const _BootView({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BreathingMark(),
              const SizedBox(height: AppSpace.xl),
              const SFWordmark(fontSize: 40),
              const SizedBox(height: AppSpace.xs),
              const SFTagline(fontSize: 17),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpace.huge + MediaQuery.paddingOf(context).bottom,
          child: const Center(child: _LoadingBar()),
        ),
      ],
    );
  }
}

/// Fills over [kSplashMinimum] (the splash's start-up time) with a few
/// rotating captions; a plain label under reduce-motion.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  static const _captions = ['Warming up your stylist…', 'Picking fresh fits…', 'Almost ready…'];

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    if (context.reduceMotion) return Text('Loading…', style: context.tt.labelMedium);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: kSplashMinimum,
      curve: Curves.easeInOutCubic,
      builder: (context, value, _) {
        final caption = _captions[math.min(_captions.length - 1, (value * _captions.length).floor())];
        return Semantics(
          label: 'Loading',
          value: '${(value * 100).round()}%',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: sf.divider, borderRadius: AppRadius.pillAll),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.02, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: sf.brandGradient,
                          borderRadius: AppRadius.pillAll,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              AnimatedSwitcher(
                duration: AppDurations.base,
                child: Text(caption, key: ValueKey(caption), style: context.tt.labelMedium?.copyWith(color: sf.textMuted)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Logo mark that gently breathes (static under reduce-motion).
class _BreathingMark extends StatefulWidget {
  const _BreathingMark();

  @override
  State<_BreathingMark> createState() => _BreathingMarkState();
}

class _BreathingMarkState extends State<_BreathingMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: const SFLogoMark(size: 96, glow: true),
    );
  }
}
