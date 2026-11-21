import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/app_images.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_glass_icon_button.dart';

class _IntroPage {
  const _IntroPage({required this.eyebrow, required this.title, required this.body, required this.image});

  final String eyebrow;
  final String title;
  final String body;
  final String image;
}

/// Three-page intro shown before sign-up the first time (the welcome screen
/// skips it once `has_seen_onboarding` is set). Full-bleed photos move with
/// a parallax lag while the caption cross-fades below.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Set once the intro is finished or skipped.
  static const seenKey = 'has_seen_onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static final List<_IntroPage> _content = [
    _IntroPage(
      eyebrow: 'AI stylist',
      title: 'Meet your\nAI stylist.',
      body: 'Tell it the occasion and your mood — it puts together complete outfits and explains why they work.',
      image: AppImages.stylistFullBleed,
    ),
    _IntroPage(
      eyebrow: 'Made for you',
      title: 'Picked for\nyour body.',
      body: 'Your measurements, body shape and skin tone shape every suggestion, so sizes and colours actually suit you.',
      image: AppImages.tryOnFullBleed,
    ),
    _IntroPage(
      eyebrow: 'Shop & save',
      title: 'Brands you\nalready love.',
      body: 'Real pieces from Outfitters, Breakout and more. Save favourites and come back to them anytime.',
      image: AppImages.shoppingFullBleed,
    ),
  ];

  bool get _isLast => _index == _content.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.seenKey, true);
    } catch (_) {
      // Not critical: the intro just shows again next time.
    }
    // Replace (not `go`) so back from register returns to the welcome screen.
    if (mounted) context.pushReplacement(RoutePaths.register);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else if (context.reduceMotion) {
      _pages.jumpToPage(_index + 1);
    } else {
      _pages.nextPage(duration: AppDurations.entrance, curve: AppCurves.move);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final page = _content[_index];
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Scrim stops anchored in pixels from the bottom (the caption has a
    // roughly fixed height), so text sits on a near-solid backdrop on short
    // phones too: solid under body + button, ~85% under the title.
    final h = MediaQuery.sizeOf(context).height;
    final solidAt = ((h - 250 - bottomInset) / h).clamp(0.5, 0.95);
    final mostlyAt = ((h - 420 - bottomInset) / h).clamp(0.3, solidAt - 0.05);
    final clearAt = ((h - 620 - bottomInset) / h).clamp(0.12, mostlyAt - 0.05);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Photos with a parallax lag.
          ExcludeSemantics(
            child: PageView.builder(
              controller: _pages,
              itemCount: _content.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _ParallaxPhoto(controller: _pages, index: i, page: _content[i]),
            ),
          ),

          // Scrim: photo melts into the theme background behind the caption.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent, bg.withValues(alpha: 0.85), bg],
                  stops: [0, clearAt, mostlyAt, solidAt],
                ),
              ),
            ),
          ),

          // Clothing pattern, faded in only where the caption sits.
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white],
                stops: [0.55, 0.85],
              ).createShader(r),
              child: const ClothingPatternBackground(),
            ),
          ),

          // Top controls.
          Positioned(
            top: topInset + AppSpace.xs,
            left: AppSpace.md,
            right: AppSpace.md,
            child: Row(
              children: [
                if (Navigator.of(context).canPop())
                  SFGlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                const Spacer(),
                _SkipPill(onPressed: _finish),
              ],
            ),
          ),

          // Caption + controls. The caption ignores touches so swipes over
          // the text still reach the photos underneath.
          Positioned(
            left: AppSpace.gutter,
            right: AppSpace.gutter,
            bottom: AppSpace.md + bottomInset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Dots(count: _content.length, index: _index),
                      const SizedBox(height: AppSpace.lg),
                      AnimatedSwitcher(
                        duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
                        switchInCurve: AppCurves.enter,
                        layoutBuilder: (current, previous) =>
                            Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        child: Semantics(
                          key: ValueKey(_index),
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${(_index + 1).toString().padLeft(2, '0')} / ${_content.length.toString().padLeft(2, '0')} · ${page.eyebrow.toUpperCase()}',
                                style: context.tt.labelSmall?.copyWith(color: sf.accentText),
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(page.title, style: context.tt.displayMedium),
                              const SizedBox(height: AppSpace.sm),
                              Text(page.body, style: context.tt.bodyLarge?.copyWith(color: sf.textMuted)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                SFButton(
                  label: _isLast ? 'Create my account' : 'Next',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One full-bleed photo that moves at ~75% of the swipe speed.
class _ParallaxPhoto extends StatelessWidget {
  const _ParallaxPhoto({required this.controller, required this.index, required this.page});

  final PageController controller;
  final int index;
  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final position = controller.hasClients && controller.position.haveDimensions
                  ? controller.page ?? controller.initialPage.toDouble()
                  : controller.initialPage.toDouble();
              final delta = (position - index).clamp(-1.0, 1.0);
              return Transform.translate(offset: Offset(delta * w * 0.25, 0), child: child);
            },
            // 1.5× wide so the shifted photo never shows an edge.
            child: OverflowBox(
              maxWidth: w * 1.5,
              minWidth: w * 1.5,
              // No width passed: it would become the decode size and upscale the
              // 1080 px photo (~22 MB per page). OverflowBox sizes it instead.
              child: SafeNetworkImage(imageUrl: page.image, alignment: Alignment.topCenter),
            ),
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppDurations.base,
            curve: AppCurves.enter,
            margin: const EdgeInsets.only(right: 6),
            height: 6,
            width: i == index ? 28 : 6,
            decoration: BoxDecoration(
              gradient: i == index ? sf.brandGradient : null,
              color: i == index ? null : sf.ink.withValues(alpha: 0.18),
              borderRadius: AppRadius.pillAll,
            ),
          ),
      ],
    );
  }
}

class _SkipPill extends StatelessWidget {
  const _SkipPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: context.tt.labelLarge,
      ),
      child: const Text('Skip'),
    );
  }
}
