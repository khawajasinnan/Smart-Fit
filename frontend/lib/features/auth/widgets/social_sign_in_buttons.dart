import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/env.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

/// "or continue with" + Google and Facebook (SFR-001, SFR-004). Used on both
/// the login and register screens: for a new user, signing in IS signing up;
/// their profile (with date of birth) comes next. Facebook appears only when
/// [Env.facebookLogin] is on (user decision 20 Nov 2026: built, switched on
/// once the Facebook app exists in Supabase, docs/oauth-setup.md §3).
class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key, this.enabled = true, this.showFacebook});

  /// False while an email login / sign-up is running.
  final bool enabled;

  /// Overrides [Env.facebookLogin] (tests).
  final bool? showFacebook;

  @override
  ConsumerState<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  OAuthProvider? _opening;

  Future<void> _go(OAuthProvider provider) async {
    if (_opening != null || !widget.enabled) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _opening = provider);
    await ref.read(authNotifierProvider.notifier).signInWithProvider(provider);
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.sf.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: context.cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text('or continue with', style: context.tt.bodySmall?.copyWith(color: muted)),
            ),
            Expanded(child: Divider(color: context.cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        _ProviderButton(
          label: 'Continue with Google',
          semanticLabel: 'Continue with Google',
          mark: const _GoogleMark(),
          loading: _opening == OAuthProvider.google,
          onPressed: widget.enabled && _opening == null ? () => _go(OAuthProvider.google) : null,
        ),
        if (widget.showFacebook ?? Env.facebookLogin) ...[
          const SizedBox(height: AppSpace.sm),
          _ProviderButton(
            label: 'Continue with Facebook',
            semanticLabel: 'Continue with Facebook',
            mark: const _FacebookMark(),
            loading: _opening == OAuthProvider.facebook,
            onPressed: widget.enabled && _opening == null ? () => _go(OAuthProvider.facebook) : null,
          ),
        ],
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.semanticLabel,
    required this.mark,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final Widget mark;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          backgroundColor: context.sf.surfaceElevated,
          foregroundColor: context.cs.onSurface,
          side: BorderSide(color: context.cs.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: loading ? const CircularProgressIndicator(strokeWidth: 2.4) : mark,
            ),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              // shrinks a little on narrow phones instead of cutting the name
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google's four-colour "G".
/// Facebook's mark: a white "f" on its blue circle (drawn, no asset).
class _FacebookMark extends StatelessWidget {
  const _FacebookMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.bottomCenter,
        decoration: const BoxDecoration(color: Color(0xFF1877F2), shape: BoxShape.circle),
        child: const Text(
          'f',
          style: TextStyle(color: Colors.white, fontSize: 17, height: 1.15, fontWeight: FontWeight.w800),
        ),
      );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _GooglePainter(), size: Size.square(22));
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: (s - stroke) / 2);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const blue = Color(0xFF4285F4), green = Color(0xFF34A853), yellow = Color(0xFFFBBC05), red = Color(0xFFEA4335);
    // angles in radians, clockwise from 3 o'clock; the G opens at the top right
    canvas.drawArc(rect, 0, math.pi * 0.25, false, arc(blue));
    canvas.drawArc(rect, math.pi * 0.25, math.pi * 0.58, false, arc(green));
    canvas.drawArc(rect, math.pi * 0.83, math.pi * 0.34, false, arc(yellow));
    canvas.drawArc(rect, math.pi * 1.17, math.pi * 0.58, false, arc(red));
    // the bar of the G, from the centre to the right edge
    canvas.drawRect(Rect.fromLTRB(s / 2, s / 2 - stroke / 2, s - stroke * 0.02, s / 2 + stroke / 2), Paint()..color = blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
