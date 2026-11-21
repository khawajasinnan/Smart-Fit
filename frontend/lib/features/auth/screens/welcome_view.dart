import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_images.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/tilt_card.dart';
import 'package:smartfit/shared_widgets/zayn_avatar.dart';

/// The landing page a signed-out user sees (shown by the splash at `/`).
///
/// A scrolling page — hero with photo collage, the numbers behind the app,
/// what it does, how it works, the brands, and Zayn — with the sign-up /
/// log-in buttons pinned at the bottom so they are always one tap away.
/// Every number shown is real (catalog brands, hairstyle library).
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  Future<void> _getStarted(BuildContext context) async {
    var seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(OnboardingScreen.seenKey) ?? false;
    } catch (_) {
      // Preferences unavailable — show the intro.
    }
    if (!context.mounted) return;
    context.push(seen ? RoutePaths.register : RoutePaths.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Room for the pinned call-to-action panel.
    final panelSpace = 150.0 + bottomInset;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TopBar(onLogin: () => context.push(RoutePaths.login))),
            const SliverToBoxAdapter(child: _Hero()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
            const SliverToBoxAdapter(child: _Stats()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxxl)),
            const SliverToBoxAdapter(child: _Features()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxxl)),
            const SliverToBoxAdapter(child: _HowItWorks()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxxl)),
            const SliverToBoxAdapter(child: _Brands()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxxl)),
            const SliverToBoxAdapter(child: _MeetZayn()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
            const SliverToBoxAdapter(child: Center(child: SFTagline(fontSize: 15))),
            SliverToBoxAdapter(child: SizedBox(height: panelSpace)),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CtaPanel(onGetStarted: () => _getStarted(context), onLogin: () => context.push(RoutePaths.login)),
        ),
      ],
    );
  }
}

// ── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.md, 0),
        child: SFEntrance(
          child: Row(
            children: [
              const SFLogoMark(size: 34),
              const SizedBox(width: AppSpace.xs),
              const Flexible(child: FittedBox(child: SFWordmark(fontSize: 22))),
              const Spacer(),
              OutlinedButton(
                onPressed: onLogin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: sf.ink,
                  side: BorderSide(color: sf.divider, width: 1.5),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  textStyle: context.tt.labelLarge,
                ),
                child: const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final headline = context.tt.displayMedium!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SFEntrance(index: 1, child: _Eyebrow()),
              const SizedBox(height: AppSpace.sm),
              SFEntrance(
                index: 2,
                child: Semantics(
                  header: true,
                  label: 'Get your fit now!',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Get your', style: headline),
                      GradientText('fit now!', style: headline),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              SFEntrance(
                index: 3,
                child: Text(
                  'Your AI stylist for Pakistani fashion. Outfits picked for your body, skin tone, '
                  'budget and occasion — tried on your own photo before you buy.',
                  style: context.tt.bodyLarge?.copyWith(color: sf.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        const SFEntrance(index: 4, child: _Collage()),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: sf.surfaceElevated,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: sf.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.hotPink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'STYLIST · TRY-ON · HAIR · LOOK SCORE',
              style: context.tt.labelSmall?.copyWith(color: sf.ink, letterSpacing: 1.1),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three editorial photos fanned out like cards on a table; the front one
/// tilts under the finger. Small chips show what the app does with them.
class _Collage extends StatelessWidget {
  const _Collage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cardH = math.min(w * 0.58 * 4 / 3, 420.0);
        final cardW = cardH * 3 / 4;
        final height = cardH * 1.12;
        final spread = math.min(w * 0.3, cardW * 0.62);

        return ExcludeSemantics(
          child: SizedBox(
            height: height,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
              curve: AppCurves.playful,
              builder: (context, t, _) => Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _fanned(AppImages.stylistHero, cardW * 0.86, cardH * 0.86, dx: -spread * t, angle: -9 * t),
                  _fanned(AppImages.hairstyleHero, cardW * 0.86, cardH * 0.86, dx: spread * t, angle: 9 * t),
                  TiltCard(
                    child: _PhotoCard(
                      url: AppImages.tryOnHero,
                      width: cardW,
                      height: cardH,
                      overlay: const Positioned(left: 10, bottom: 10, child: _MatchChip()),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: AppSpace.gutter,
                    child: Opacity(opacity: t.clamp(0.0, 1.0), child: const _ZaynBubble()),
                  ),
                  Positioned(
                    bottom: 0,
                    right: AppSpace.gutter,
                    child: Opacity(opacity: t.clamp(0.0, 1.0), child: const _ScoreChip()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fanned(String url, double w, double h, {required double dx, required double angle}) {
    return Transform.translate(
      offset: Offset(dx, h * 0.06),
      child: Transform.rotate(angle: angle * math.pi / 180, child: _PhotoCard(url: url, width: w, height: h)),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.url, required this.width, required this.height, this.overlay});

  final String url;
  final double width;
  final double height;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl - 4);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: context.isDark ? 0.14 : 1), width: 4),
        boxShadow: context.sf.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: radius - const BorderRadius.all(Radius.circular(4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeNetworkImage(imageUrl: url, alignment: Alignment.topCenter, width: width),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

/// White "match" chip on the front photo.
class _MatchChip extends StatelessWidget {
  const _MatchChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: AppRadius.pillAll,
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.greenDeep),
          const SizedBox(width: 4),
          Text('Fits you · M', style: context.tt.labelMedium?.copyWith(color: AppColors.ink900)),
        ],
      ),
    );
  }
}

/// Zayn's speech bubble over the collage.
class _ZaynBubble extends StatelessWidget {
  const _ZaynBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.6)),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZaynAvatar(size: 26),
          const SizedBox(width: 8),
          Text(
            'Weekend plans? Try this.',
            style: context.tt.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Pink look-score chip over the collage.
class _ScoreChip extends StatelessWidget {
  const _ScoreChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.hotPink,
        borderRadius: AppRadius.mdAll,
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('87', style: context.tt.titleLarge?.copyWith(color: AppColors.ink900, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LOOK SCORE', style: context.tt.labelSmall?.copyWith(color: AppColors.ink900)),
              Text('Great for a day out', style: context.tt.labelSmall?.copyWith(color: AppColors.ink900)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Numbers ─────────────────────────────────────────────────────────────────

class _Stats extends StatelessWidget {
  const _Stats();

  // Real figures: catalog brands and products (scraper, Nov 2026) and the
  // hairstyle library (CelebAMask-HQ styles).
  static const _items = [('60+', 'Pakistani\nbrands'), ('25k+', 'real\nproducts'), ('80', 'hairstyles\nto try')];

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: SFEntrance(
        index: 5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          decoration: BoxDecoration(
            color: sf.surfaceElevated,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: sf.divider),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) VerticalDivider(width: 1, thickness: 1, color: sf.divider),
                  Expanded(
                    child: Semantics(
                      label: '${_items[i].$1} ${_items[i].$2.replaceAll('\n', ' ')}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          FittedBox(
                            child: Text(
                              _items[i].$1,
                              style: context.tt.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: i == 1 ? sf.accentText : sf.ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _items[i].$2,
                            textAlign: TextAlign.center,
                            style: context.tt.labelMedium?.copyWith(color: sf.textMuted, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── What it does ────────────────────────────────────────────────────────────

class _Feature {
  const _Feature(this.title, this.body, {this.icon, this.zayn = false, this.pink = false});

  final String title;
  final String body;
  final IconData? icon;
  final bool zayn;
  final bool pink;
}

class _Features extends StatelessWidget {
  const _Features();

  static const _items = [
    _Feature('Chat with Zayn', 'Tell him the occasion, mood and budget. He builds full outfits and says why.', zayn: true),
    _Feature('Virtual try-on', 'See the outfit on your own photo before you spend a rupee.', icon: Icons.checkroom_rounded),
    _Feature('Hairstyles', 'Styles matched to your face shape, previewed on you.', icon: Icons.content_cut_rounded, pink: true),
    _Feature('Look score', 'Every look rated out of 100 for colour, fit and occasion, with tips.', icon: Icons.insights_rounded),
    _Feature('Body scan', 'Measurements from your photos, so the size you pick fits.', icon: Icons.straighten_rounded),
    _Feature('Shop real brands', 'Live prices from Pakistani stores. Save favourites for later.', icon: Icons.shopping_bag_outlined, pink: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(eyebrow: 'WHAT IT DOES', title: 'Everything for\nyour fit, in one app.'),
          const SizedBox(height: AppSpace.lg),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < 300 ? 1 : 2;
              final itemW = (c.maxWidth - AppSpace.sm * (cols - 1)) / cols;
              return Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [for (final f in _items) SizedBox(width: itemW, child: _FeatureCard(feature: f))],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final tint = feature.pink ? AppColors.hotPink : AppColors.neonGreen;
    return Container(
      constraints: const BoxConstraints(minHeight: 168),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: sf.surfaceElevated,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: sf.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (feature.zayn)
            const ZaynAvatar(size: 40)
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint, borderRadius: AppRadius.smAll),
              child: Icon(feature.icon, size: 22, color: AppColors.ink900),
            ),
          const SizedBox(height: AppSpace.sm),
          Text(feature.title, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(feature.body, style: context.tt.bodySmall?.copyWith(color: sf.textMuted, height: 1.35)),
        ],
      ),
    );
  }
}

// ── How it works ────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    ('Build your profile', 'Gender, measurements, skin tone and style. About two minutes.'),
    ('Ask Zayn', "Say where you're going — a mehndi, the office, a weekend out — and your budget."),
    ('Try it on, then shop', "Preview it on you, score the look, and buy from the brand's own store."),
  ];

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(eyebrow: 'HOW IT WORKS', title: 'Three steps to\nyour next outfit.'),
          const SizedBox(height: AppSpace.lg),
          for (var i = 0; i < _steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == _steps.length - 1 ? AppColors.hotPink : AppColors.neonGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: context.tt.titleMedium?.copyWith(color: AppColors.ink900, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (i < _steps.length - 1)
                        Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: sf.divider)),
                    ],
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 6, bottom: i < _steps.length - 1 ? AppSpace.lg : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_steps[i].$1, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(_steps[i].$2, style: context.tt.bodyMedium?.copyWith(color: sf.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Brands ──────────────────────────────────────────────────────────────────

class _Brands extends StatelessWidget {
  const _Brands();

  // A selection of the brands in the catalog (backend/shared/feed_brands.py).
  static const names = [
    'Outfitters', 'Breakout', 'Sana Safinaz', 'Edenrobe', 'Junaid Jamshed', 'Maria.B', 'Engine', 'Diners',
    'Zellbury', 'Alkaram Studio', 'Nishat Linen', 'Limelight', 'Charcoal', 'Rastah', 'Cambridge', 'Uniworth',
    'Beechtree', 'Baroque', 'Lulusar', 'Zeen', 'Generation', 'Cougar',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: _SectionTitle(eyebrow: 'SHOP THE BRANDS', title: 'Real stock from\n60+ Pakistani brands.'),
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          label: 'Brands include ${names.join(', ')}',
          excludeSemantics: true,
          child: const _BrandMarquee(names: names),
        ),
      ],
    );
  }
}

/// Brand names drifting sideways in an endless loop (still, and scrollable by
/// hand, under reduce-motion).
class _BrandMarquee extends StatefulWidget {
  const _BrandMarquee({required this.names});

  final List<String> names;

  @override
  State<_BrandMarquee> createState() => _BrandMarqueeState();
}

class _BrandMarqueeState extends State<_BrandMarquee> with SingleTickerProviderStateMixin {
  static const _pixelsPerSecond = 28.0;

  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = context.reduceMotion;
    if (_still) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    // The row holds the names twice; jump back one copy to loop seamlessly.
    final copy = (p.maxScrollExtent + p.viewportDimension) / 2;
    if (copy <= 0) return;
    var next = p.pixels + _pixelsPerSecond * dt;
    if (next >= copy) next -= copy;
    _scroll.jumpTo(next.clamp(0.0, p.maxScrollExtent));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final names = _still ? widget.names : [...widget.names, ...widget.names];
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: _still ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: _still ? AppSpace.gutter : 0),
        child: Row(
          children: [
            for (var i = 0; i < names.length; i++)
              Container(
                margin: const EdgeInsets.only(right: AppSpace.xs),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i % 5 == 2 ? AppColors.hotPink.withValues(alpha: 0.12) : sf.surfaceElevated,
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: i % 5 == 2 ? AppColors.hotPink.withValues(alpha: 0.5) : sf.divider),
                ),
                child: Text(names[i], style: context.tt.labelLarge?.copyWith(color: sf.ink)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Meet Zayn ───────────────────────────────────────────────────────────────

class _MeetZayn extends StatelessWidget {
  const _MeetZayn();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.isDark ? AppColors.darkSurface1 : AppColors.ink900,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, 0, AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MEET ZAYN', style: tt.labelSmall?.copyWith(color: AppColors.hotPink, letterSpacing: 1.2)),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      "Hi, I'm Zayn. Tell me where you're going — I'll find your fit.",
                      style: tt.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Your stylist knows your size, your colours and your budget.',
                      style: tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ),
            ExcludeSemantics(
              child: Image.asset(
                'assets/mascot/still/hello.png',
                width: 128,
                height: 150,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox(width: 128, height: 150),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: context.tt.labelSmall?.copyWith(color: context.sf.accentText, letterSpacing: 1.2)),
          const SizedBox(height: AppSpace.xs),
          Text(title, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
        ],
      ),
    );
  }
}

/// Sign-up and log-in, pinned to the bottom over the scrolling page.
class _CtaPanel extends StatelessWidget {
  const _CtaPanel({required this.onGetStarted, required this.onLogin});

  final VoidCallback onGetStarted;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Fades the page out above the panel instead of a hard edge.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.96), bg],
          stops: const [0, 0.22, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xl,
          AppSpace.gutter,
          AppSpace.xs + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SFEntrance(
              index: 6,
              child: SFButton(label: 'Get started', trailingIcon: Icons.arrow_forward_rounded, onPressed: onGetStarted),
            ),
            SFEntrance(
              index: 7,
              child: Center(
                child: TextButton(
                  onPressed: onLogin,
                  child: Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: context.tt.bodyMedium,
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: context.tt.bodyMedium?.copyWith(color: sf.accentText, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
