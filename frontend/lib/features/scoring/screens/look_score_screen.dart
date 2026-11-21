import 'package:smartfit/features/hairstyle/providers/hairstyle_provider.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_back_button.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';

/// Look Score (SFR-032), styling comments and hints (SFR-033), and the
/// user's rating of the score (SFR-034). Opened with a [LookScoreArgs]
/// from a finished try-on; without one it explains how to get a score.
class LookScoreScreen extends ConsumerWidget {
  const LookScoreScreen({super.key, this.args});

  final LookScoreArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = args;
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: ClothingPatternBackground()),
          SafeArea(
            child: Column(
              children: [
                const _Header(),
                Expanded(child: look == null ? const _NothingToScore() : _ScoreBody(look: look)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
      child: Row(
        children: [
          const SFBackButton(),
          const SizedBox(width: 4),
          Text('Look Score', style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NothingToScore extends StatelessWidget {
  const _NothingToScore();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 72, color: context.sf.highlight).animate().scale(curve: Curves.easeOutBack),
            const SizedBox(height: 20),
            Text('Score a look', style: AppTextStyles.headlineLg.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              'Try on an outfit, then tap "Score this look". SmartFit rates how well the outfit and your '
              'chosen hairstyle suit you, explains why, and tells you what to change.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 28),
            SFButton(
              label: 'Find an outfit',
              icon: Icons.auto_awesome_rounded,
              onPressed: () => context.go(RoutePaths.chat),
            ),
          ],
        ),
      ),
    );
  }
}

const _occasions = ['casual', 'office', 'eid', 'mehndi', 'nikah', 'wedding', 'party', 'date', 'interview'];

class _ScoreBody extends ConsumerWidget {
  const _ScoreBody({required this.look});

  final LookScoreArgs look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lookScoreControllerProvider(look));
    final controller = ref.read(lookScoreControllerProvider(look).notifier);
    final hairstyle = ref.watch(chosenHairstyleProvider);
    final result = state.result;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _ProductRow(look: look),
        const SizedBox(height: 16),
        Text('Occasion', style: AppTextStyles.labelCaps.copyWith(color: context.cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in _occasions)
              ChoiceChip(
                label: Text(o[0].toUpperCase() + o.substring(1)),
                selected: state.occasion == o,
                onSelected: (on) => controller.setOccasion(on ? o : null),
              ),
          ],
        ),
        if (hairstyle != null) ...[
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: state.includeHairstyle,
            onChanged: controller.setIncludeHairstyle,
            title: Text('Include my hairstyle', style: AppTextStyles.titleSm),
            subtitle: Text(
              '${hairstyle.name} (${hairstyle.faceShape} face)',
              style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              ref.read(hairstyleOutfitProvider.notifier).state = look.product; // SFR-029: match this outfit
              context.go(RoutePaths.hairstyle);
            },
            child: Text(
              'Add a hairstyle to score the complete look →',
              style: AppTextStyles.bodySm.copyWith(color: context.sf.highlight, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (state.failure != null && result == null)
          Column(
            children: [
              NoticeBanner(tone: NoticeTone.error, title: 'Could not score this look', message: state.failure!.message),
              const SizedBox(height: 12),
              SFButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: controller.score),
            ],
          )
        else if (result == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (state.failure != null) ...[
            NoticeBanner(tone: NoticeTone.warning, message: state.failure!.message),
            const SizedBox(height: 12),
          ],
          AnimatedOpacity(
            opacity: state.loading ? 0.5 : 1,
            duration: const Duration(milliseconds: 200),
            child: _Result(result: result),
          ),
          const SizedBox(height: 24),
          _RateLook(look: look),
        ],
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.look});

  final LookScoreArgs look;

  @override
  Widget build(BuildContext context) {
    final p = look.product;
    final fit = look.fit;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 64,
            height: 80,
            child: (p.imageUrl ?? '').isEmpty
                ? ColoredBox(color: context.cs.surfaceContainerHigh, child: const Icon(Icons.checkroom_rounded))
                : SafeNetworkImage(imageUrl: p.imageUrl!, width: 64, height: 80, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.titleMd),
              const SizedBox(height: 2),
              Text(p.brand, style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant)),
              if (fit != null && fit.status != TryOnFitStatus.unknown) ...[
                const SizedBox(height: 4),
                Text(
                  switch (fit.status) {
                    TryOnFitStatus.fits => 'Size ${fit.size ?? ''} fits you',
                    TryOnFitStatus.small => 'Size ${fit.size ?? ''} is small for you',
                    _ => 'Size ${fit.size ?? ''} is big for you',
                  },
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fit.fits ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Color _scoreColour(BuildContext context, int score) {
  if (score >= 80) return AppColors.success;
  if (score >= 60) return context.sf.highlight;
  if (score >= 45) return AppColors.warning;
  return AppColors.error;
}

class _Result extends StatelessWidget {
  const _Result({required this.result});

  final LookScoreResult result;

  @override
  Widget build(BuildContext context) {
    final validation = result.validation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _ScoreRing(score: result.score)),
        const SizedBox(height: 14),
        Text(
          result.verdict,
          textAlign: TextAlign.center,
          style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700),
        ),
        if (validation != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                validation.agrees ? Icons.verified_rounded : Icons.info_outline_rounded,
                size: 16,
                color: validation.agrees ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  validation.note,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        Text('Why this score', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final (i, c) in result.components.indexed)
          _ComponentBar(component: c).animate().fadeIn(delay: (80 * i).ms).slideX(begin: 0.05),
        if (result.hints.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Styling hints', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final h in result.hints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_rounded, size: 18, color: context.sf.highlight),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h, style: AppTextStyles.bodyMd.copyWith(height: 1.4))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final colour = _scoreColour(context, score);
    return Semantics(
      label: 'Look score $score out of 100',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score / 100),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: _RingPainter(progress: t, colour: colour, track: context.cs.surfaceContainerHigh),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(t * 100).round()}',
                    style: AppTextStyles.displayXl.copyWith(fontWeight: FontWeight.w800, color: colour, height: 1),
                  ),
                  Text('/ 100', style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.colour, required this.track});

  final double progress;
  final Color colour;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.08;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, base..color = track);
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * progress, false, base..color = colour);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.colour != colour || old.track != track;
}

class _ComponentBar extends StatelessWidget {
  const _ComponentBar({required this.component});

  final LookComponent component;

  @override
  Widget build(BuildContext context) {
    final c = component;
    final colour = c.known ? _scoreColour(context, c.score) : context.cs.outline;
    final effect = c.effect;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.label, style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700))),
              if (effect != null && effect.abs() >= 1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${effect > 0 ? '+' : '−'}${effect.abs().round()}',
                    style: AppTextStyles.labelSm.copyWith(
                      color: effect > 0 ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(
                c.known ? '${c.score}' : '—',
                style: AppTextStyles.titleSm.copyWith(color: colour, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.score / 100,
              minHeight: 8,
              backgroundColor: context.cs.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          const SizedBox(height: 6),
          Text(c.note, style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, height: 1.35)),
        ],
      ),
    );
  }
}

class _RateLook extends ConsumerWidget {
  const _RateLook({required this.look});

  final LookScoreArgs look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lookScoreControllerProvider(look));
    final controller = ref.read(lookScoreControllerProvider(look).notifier);
    // Its own group with separate children: without it the web build merged the whole card into
    // the comment field (screen readers read the card as one text box; found by the E2E run).
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.sf.glassBorder),
      ),
      child: Column(
        children: [
          Text(
            state.ratingSent ? 'Thanks — SmartFit learns from your rating' : 'Do you agree with this score?',
            style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: '$star star${star == 1 ? '' : 's'}',
                  icon: Icon(
                    (state.rating ?? 0) >= star ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF5A524),
                    size: 32,
                  ),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final error = await controller.rate(star);
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                ),
            ],
          ),
          if (state.ratingSent && state.result != null)
            state.detailsSent
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Thanks — your notes help SmartFit get better',
                      style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
                    ),
                  )
                : _FeedbackDetails(look: look, components: state.result!.components),
        ],
      ),
      ),
    );
  }
}

/// SFR-034: after the stars, optionally say which parts of the score are off
/// (corrections) and add a comment. Both are stored with the rating.
class _FeedbackDetails extends ConsumerStatefulWidget {
  const _FeedbackDetails({required this.look, required this.components});

  final LookScoreArgs look;
  final List<LookComponent> components;

  @override
  ConsumerState<_FeedbackDetails> createState() => _FeedbackDetailsState();
}

class _FeedbackDetailsState extends ConsumerState<_FeedbackDetails> {
  final _comment = TextEditingController();
  final _off = <String>{};
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final error = await ref
        .read(lookScoreControllerProvider(widget.look).notifier)
        .sendDetails(corrections: _off.toList()..sort(), comment: _comment.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text("What's off? (optional)", style: AppTextStyles.labelLg.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in widget.components)
              FilterChip(
                label: Text(c.label),
                selected: _off.contains(c.key),
                onSelected: (on) => setState(() => on ? _off.add(c.key) : _off.remove(c.key)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          child: TextField(
          controller: _comment,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Comment (optional)',
            hintText: 'e.g. the colour is fine, it is just too formal for me',
          ),
        ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send feedback'),
          ),
        ),
      ],
    );
  }
}
