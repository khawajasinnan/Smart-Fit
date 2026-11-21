import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

import 'zayn_mood.dart';
import 'zayn_voice.dart';
import 'zayn_surface.dart';

/// Zayn at the top of the AI stylist chat (spec §23.14): large on a new chat,
/// compact once the conversation is going, always reacting. Tap to poke.
class ZaynHero extends ConsumerStatefulWidget {
  const ZaynHero({super.key, required this.compact});

  final bool compact;

  static const double expandedHeight = 268;
  static const double compactHeight = 108;

  @override
  ConsumerState<ZaynHero> createState() => _ZaynHeroState();
}

class _ZaynHeroState extends ConsumerState<ZaynHero> with WidgetsBindingObserver {
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (!visible) ref.read(zaynVoiceProvider.notifier).stop(); // never talk from the background
    if (visible != _appVisible) setState(() => _appVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final zayn = ref.watch(zaynProvider);
    final speaking = ref.watch(zaynVoiceProvider.select((v) => v.speaking));
    final reduced = MediaQuery.of(context).disableAnimations;
    // TickerMode is off while the chat tab is in the background (StatefulShellRoute).
    final active = _appVisible && TickerMode.valuesOf(context).enabled;
    final duration = reduced ? Duration.zero : const Duration(milliseconds: 420);
    const curve = Curves.easeOutCubic;
    final compact = widget.compact;
    final width = MediaQuery.sizeOf(context).width;
    final mascot = compact ? 104.0 : 222.0;

    return Semantics(
      label: 'Zayn, your AI stylist, is ${zayn.mood.description}${speaking ? ' and talking' : ''}',
      button: true,
      onTapHint: 'poke Zayn',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(zaynProvider.notifier).poke();
        },
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          height: compact ? ZaynHero.compactHeight : ZaynHero.expandedHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: compact ? 14 : (width - mascot) / 2,
                top: compact ? 2 : 0,
                width: mascot,
                height: mascot,
                child: ZaynSurface(
                  mood: zayn.mood,
                  reducedMotion: reduced,
                  active: active,
                  speaking: speaking,
                  fallback: _ZaynStill(mood: zayn.mood),
                ),
              ),
              // Sound animation: a little equalizer badge while Zayn talks.
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: compact ? 14 + mascot - 30 : (width + mascot) / 2 - 34,
                top: compact ? mascot - 26 : mascot - 40,
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: speaking ? 1 : 0,
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: ZaynSoundBars(active: speaking && active, animate: !reduced),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: compact ? 124 : 24,
                right: compact ? 16 : 24,
                top: compact ? 20 : null,
                bottom: compact ? null : 4,
                child: _QuipBubble(text: zayn.quip, seq: zayn.seq, pointsLeft: compact),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A still frame of the mood (no WebGL, tests, or while the 3D page loads).
class _ZaynStill extends StatelessWidget {
  const _ZaynStill({required this.mood});

  final ZaynMood mood;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Image.asset(
        'assets/mascot/still/${mood.name}.png',
        key: ValueKey(mood),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _QuipBubble extends StatelessWidget {
  const _QuipBubble({required this.text, required this.seq, required this.pointsLeft});

  final String? text;
  final int seq;
  final bool pointsLeft;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final line = text;
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(animation),
          alignment: pointsLeft ? Alignment.centerLeft : Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: line == null
          ? const SizedBox(key: ValueKey('none'), height: 0)
          : Align(
              key: ValueKey(seq),
              alignment: pointsLeft ? Alignment.centerLeft : Alignment.center,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sf.surfaceElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(pointsLeft ? 4 : 18),
                      topRight: const Radius.circular(18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: const Radius.circular(18),
                    ),
                    border: Border.all(color: AppColors.primary400.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: pointsLeft ? TextAlign.start : TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: sf.ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Animated equalizer shown while Zayn's voice plays.
class ZaynSoundBars extends StatefulWidget {
  const ZaynSoundBars({super.key, required this.active, this.animate = true});

  final bool active;
  final bool animate;

  @override
  State<ZaynSoundBars> createState() => _ZaynSoundBarsState();
}

class _ZaynSoundBarsState extends State<ZaynSoundBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ZaynSoundBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && widget.animate) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary600, AppColors.accent600]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
                width: 3,
                height: 5 + 9 * (widget.animate
                    ? (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi * (i.isEven ? 2 : 3) + i * 1.3)).abs()
                    : const [0.4, 0.9, 0.6, 0.8][i]),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }
}
