import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/home/data/style_streak.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/data/services/scraper_api_service.dart';
import 'package:smartfit/features/recommendation/providers/taste_feedback_provider.dart';
import 'package:smartfit/features/recommendation/widgets/product_card_widget.dart';
import 'package:smartfit/features/home/widgets/home_peekers.dart';
import 'package:smartfit/shared_widgets/pressable.dart';
import 'package:smartfit/shared_widgets/skeletons.dart';
import 'package:smartfit/shared_widgets/zayn_avatar.dart';

/// Home cards (spec §23.19): Zayn's tip of the day, the style streak with a
/// daily challenge, and trending picks from the synced catalog.

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: context.sf.surfaceElevated,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: context.sf.glassBorder),
      boxShadow: context.sf.cardShadow,
    );

// ── Zayn's tip of the day ────────────────────────────────────────────────────

const zaynTips = [
  'Tuck the front of your shirt, leave the back out. Instant "I tried, but not too hard."',
  'Match one colour from your shoes to one thing up top. Your outfit will thank you.',
  'Lawn kurta + straight jeans + white sneakers = the easiest uni fit in Pakistan.',
  'Oversized top? Slim bottom. Slim top? Go wide-leg. Balance is everything, bestie.',
  'Black on black is iconic, but one metallic accessory makes it look expensive.',
  'Roll your sleeves twice, not once. The details are where the drip is.',
  'For shaadi season: pick your colour first, then the fabric. Never the other way.',
  'If it fits in the shoulders, a tailor can fix the rest. Remember that at sales.',
  'Earth tones for warm skin, jewel tones for cool skin. Zayn has spoken.',
  'A crisp white tee is the best investment in your wardrobe. Fight me.',
  'Socks are the plot twist of your outfit. Make them interesting.',
  'Dupatta drape changes the whole vibe: one shoulder for casual, both for formal.',
  'When in doubt, monochrome. Same colour, different shades. Effortless.',
  'Your watch and your belt should be on speaking terms (same metal tone).',
];

String tipFor(DateTime day, [int offset = 0]) =>
    zaynTips[(day.difference(DateTime(2026)).inDays.abs() + offset) % zaynTips.length];

class ZaynTipCard extends StatefulWidget {
  const ZaynTipCard({super.key});

  @override
  State<ZaynTipCard> createState() => _ZaynTipCardState();
}

class _ZaynTipCardState extends State<ZaynTipCard> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    Widget avatar = const ZaynAvatar(size: 58, ring: true);
    if (!reduced) {
      avatar = avatar
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: -2, end: 3, duration: 1600.ms, curve: Curves.easeInOut)
          .rotate(begin: -0.015, end: 0.015, duration: 1600.ms);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.hotPink, // Zayn's ring on his tip card
            ),
            child: avatar,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("ZAYN'S TIP OF THE DAY",
                        style: context.tt.labelSmall?.copyWith(
                            color: context.sf.accentText, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                  ],
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
                  ),
                  child: Text(
                    '"${tipFor(DateTime.now(), _offset)}"',
                    key: ValueKey(_offset),
                    style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _SmallAction(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Ask Zayn',
                      filled: true,
                      onTap: () => context.go(RoutePaths.chat),
                    ),
                    _SmallAction(
                      icon: Icons.refresh_rounded,
                      label: 'Another tip',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _offset++);
                        PeekersScope.maybeOf(context)?.react('roll'); // the eyes: "another one?"
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({super.key, required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? context.sf.onBrand : context.sf.highlight;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: filled ? context.sf.brandGradient : null,
          color: filled ? null : context.sf.highlight.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label, style: context.tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── Style streak + daily challenge ───────────────────────────────────────────

class StyleStreakCard extends ConsumerStatefulWidget {
  const StyleStreakCard({super.key});

  @override
  ConsumerState<StyleStreakCard> createState() => _StyleStreakCardState();
}

class _StyleStreakCardState extends ConsumerState<StyleStreakCard> {
  bool _celebrate = false;

  Future<void> _done() async {
    HapticFeedback.heavyImpact();
    await ref.read(styleStreakProvider.notifier).completeChallenge();
    if (!mounted) return;
    PeekersScope.maybeOf(context)?.react('star');
    setState(() => _celebrate = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _celebrate = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(styleStreakProvider);
    final reduced = MediaQuery.of(context).disableAnimations;
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    Widget flame = const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF7A1A), size: 30);
    if (!reduced && s.streak > 0) {
      flame = flame
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.92, end: 1.1, duration: 900.ms, curve: Curves.easeInOut);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  flame,
                  const SizedBox(width: 8),
                  Semantics(
                    label: '${s.streak} day style streak',
                    excludeSemantics: true,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${s.streak}', style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                      TextSpan(
                          text: s.streak == 1 ? ' day streak' : ' day streak',
                          style: context.tt.titleSmall?.copyWith(color: context.sf.textMuted, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                  const Spacer(),
                  Text('Best ${s.best}', style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              // the last 7 days, oldest on the left
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var ago = 6; ago >= 0; ago--)
                    _DayDot(
                      letter: letters[now.subtract(Duration(days: ago)).weekday - 1],
                      lit: s.week.contains(ago),
                      today: ago == 0,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.sf.highlight.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("TODAY'S CHALLENGE",
                        style: context.tt.labelSmall?.copyWith(color: context.sf.highlight, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(challengeFor(now), style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
                      child: s.doneToday
                          ? Row(
                              key: const ValueKey('done'),
                              children: [
                                const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('Challenge done. Zayn is proud. See you tomorrow!',
                                      style: context.tt.labelLarge?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                                ),
                              ],
                            )
                          : _SmallAction(
                              key: const ValueKey('todo'),
                              icon: Icons.check_circle_rounded,
                              label: 'I did it!',
                              filled: true,
                              onTap: _done,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_celebrate && !reduced) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.letter, required this.lit, required this.today});

  final String letter;
  final bool lit;
  final bool today;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? AppColors.neonGreen : context.sf.highlight.withValues(alpha: 0.08),
            border: today
                ? Border.all(color: context.sf.highlight, width: 2)
                : (lit ? null : Border.all(color: context.sf.highlight.withValues(alpha: 0.22), width: 1.2)),
          ),
          child: lit ? const Icon(Icons.local_fire_department_rounded, size: 16, color: AppColors.ink900) : null,
        ),
        const SizedBox(height: 4),
        Text(letter, style: context.tt.labelSmall?.copyWith(color: context.sf.textMuted, fontWeight: today ? FontWeight.w900 : null)),
      ],
    );
  }
}

/// A short burst of sparkles and hearts when a challenge is done.
class _Confetti extends StatelessWidget {
  const _Confetti();

  @override
  Widget build(BuildContext context) {
    final second = context.sf.highlight;
    final items = [
      (Icons.auto_awesome, const Color(0xFFF6C945), -0.8, -0.9),
      (Icons.favorite, AppColors.hotPink, 0.7, -1.0),
      (Icons.star_rounded, second, -0.2, -1.1),
      (Icons.auto_awesome, AppColors.accent600, 0.9, -0.3),
      (Icons.favorite, second, -1.0, -0.2),
      (Icons.star_rounded, const Color(0xFFF6C945), 0.3, -0.6),
    ];
    return Stack(
      children: [
        for (var i = 0; i < items.length; i++)
          Align(
            alignment: Alignment(items[i].$3 * 0.6, 0.6),
            child: Icon(items[i].$1, color: items[i].$2, size: 26)
                .animate(delay: (i * 60).ms)
                .moveY(begin: 0, end: 160 * items[i].$4, duration: 900.ms, curve: Curves.easeOutCubic)
                .moveX(begin: 0, end: 40 * items[i].$3, duration: 900.ms)
                .scaleXY(begin: 0.4, end: 1.2, duration: 400.ms)
                .then()
                .fadeOut(duration: 500.ms),
          ),
      ],
    );
  }
}

// ── Trending picks ───────────────────────────────────────────────────────────

/// Real products from the synced catalog for this profile and taste,
/// loaded once per session.
final trendingPicksProvider = FutureProvider.autoDispose<List<ProductRecommendation>>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return const [];
  final profile = ref.watch(profileNotifierProvider(userId)).valueOrNull;
  if (profile == null) return const [];
  final taste = ref.read(feedbackActionsProvider).tasteProfile();
  final result = await ref.read(scraperApiServiceProvider).searchProducts(profile: profile, taste: taste, maxProducts: 10);
  ref.keepAlive();
  return result.products;
});

class TrendingPicks extends ConsumerWidget {
  const TrendingPicks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(trendingPicksProvider);
    final rejected = ref.watch(tasteFeedbackProvider.select((t) => t.disliked.keys.toSet()));
    return picks.when(
      loading: () => SizedBox(
        height: 300,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, _) => const SkeletonBox(width: 220, height: 300, radius: 26),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        final visible = [for (final p in items) if (!rejected.contains(p.key)) p];
        if (visible.isEmpty) return const SizedBox.shrink();
        return ProductCarousel(products: visible, title: 'Trending for you');
      },
    );
  }
}
