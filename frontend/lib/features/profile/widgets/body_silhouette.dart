import 'package:flutter/material.dart';

/// Relative proportions of a body type, drawn by [BodySilhouette].
/// Widths are half-widths as a fraction of the figure's height.
class BodyProportions {
  const BodyProportions({required this.shoulders, required this.waist, required this.hips, this.height = 1});

  final double shoulders;
  final double waist;
  final double hips;

  /// 1 = full height; < 1 draws a shorter figure (Petite).
  final double height;
}

/// The body types offered in profile setup before 21 Nov 2026 (still shown for profiles that
/// saved one). Keys are labels stored in `profiles.body_type` — never rename them.
const Map<String, BodyProportions> bodyTypeProportions = {
  'Slim': BodyProportions(shoulders: 0.105, waist: 0.075, hips: 0.095),
  'Lean': BodyProportions(shoulders: 0.12, waist: 0.085, hips: 0.10),
  'Athletic': BodyProportions(shoulders: 0.15, waist: 0.095, hips: 0.105),
  'Average': BodyProportions(shoulders: 0.125, waist: 0.11, hips: 0.12),
  'Curvy': BodyProportions(shoulders: 0.12, waist: 0.085, hips: 0.145),
  'Plus': BodyProportions(shoulders: 0.14, waist: 0.145, hips: 0.155),
  'Petite': BodyProportions(shoulders: 0.12, waist: 0.09, hips: 0.11, height: 0.82),
  'Broad': BodyProportions(shoulders: 0.165, waist: 0.12, hips: 0.12),
};

/// Body shapes by gender (21 Nov 2026, the user's request: all body types for women and men
/// in onboarding). The five shapes stylists use for each: women hourglass, pear, apple,
/// rectangle, inverted triangle; men rectangle, triangle, inverted triangle, oval, trapezoid.
/// Stored in `profiles.body_type` as these labels; recommendations and the look score know
/// them (features.body_flatter, scoring/hints.py). Never rename them.
const Map<String, BodyProportions> womenBodyShapes = {
  'Hourglass': BodyProportions(shoulders: 0.135, waist: 0.085, hips: 0.135),
  'Pear': BodyProportions(shoulders: 0.112, waist: 0.09, hips: 0.152),
  'Apple': BodyProportions(shoulders: 0.13, waist: 0.142, hips: 0.125),
  'Rectangle': BodyProportions(shoulders: 0.125, waist: 0.115, hips: 0.125),
  'Inverted triangle': BodyProportions(shoulders: 0.158, waist: 0.1, hips: 0.108),
};

const Map<String, BodyProportions> menBodyShapes = {
  'Rectangle': BodyProportions(shoulders: 0.13, waist: 0.122, hips: 0.125),
  'Triangle': BodyProportions(shoulders: 0.112, waist: 0.132, hips: 0.142),
  'Inverted triangle': BodyProportions(shoulders: 0.168, waist: 0.1, hips: 0.11),
  'Oval': BodyProportions(shoulders: 0.12, waist: 0.152, hips: 0.13),
  'Trapezoid': BodyProportions(shoulders: 0.158, waist: 0.112, hips: 0.12),
};

/// The shapes offered for a gender ('Male' / 'Female'; men's for anything else).
Map<String, BodyProportions> bodyShapesFor(String? gender) =>
    (gender ?? '').toLowerCase() == 'female' ? womenBodyShapes : menBodyShapes;

/// Proportions for any stored label: the new shapes, or a body type saved before 21 Nov 2026.
BodyProportions? proportionsFor(String? label) =>
    womenBodyShapes[label] ?? menBodyShapes[label] ?? bodyTypeProportions[label];

/// A simple, neutral figure showing a body type's proportions — clearer
/// than stock photos, works offline and in both themes.
class BodySilhouette extends StatelessWidget {
  const BodySilhouette({super.key, required this.proportions, required this.fill});

  final BodyProportions proportions;

  /// Gradient (selected) or flat colour (unselected) for the figure.
  final Gradient fill;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SilhouettePainter(proportions, fill), size: Size.infinite);
  }
}

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter(this.p, this.fill);

  final BodyProportions p;
  final Gradient fill;

  @override
  void paint(Canvas canvas, Size size) {
    final figH = size.height * 0.94 * p.height;
    final top = size.height - figH - size.height * 0.03; // feet on the same line
    final cx = size.width / 2;

    // Draw the figure opaque into a layer, then tint the union once (srcIn),
    // so overlapping parts don't darken where a translucent fill doubles up.
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    final solid = Paint()..color = const Color(0xFF000000);
    final limb = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final headR = figH * 0.075;
    final shoulderY = top + headR * 2 + figH * 0.05;
    final waistY = top + figH * 0.44;
    final hipY = top + figH * 0.55;
    final crotchY = top + figH * 0.60;
    final footY = top + figH;
    final sh = figH * p.shoulders;
    final wa = figH * p.waist;
    final hi = figH * p.hips;
    final neck = figH * 0.03;

    // Arms first, so the torso overlaps where they join.
    limb.strokeWidth = figH * 0.055;
    for (final side in const [-1.0, 1.0]) {
      final shoulder = Offset(cx + side * (sh - limb.strokeWidth * 0.45), shoulderY + figH * 0.03);
      final hand = Offset(cx + side * (hi + limb.strokeWidth * 0.9), crotchY);
      canvas.drawLine(shoulder, hand, limb);
    }

    // Legs.
    final legW = (hi * 0.8).clamp(figH * 0.05, figH * 0.11);
    limb.strokeWidth = legW;
    for (final side in const [-1.0, 1.0]) {
      final hip = Offset(cx + side * (hi - legW * 0.55), crotchY - legW * 0.4);
      final foot = Offset(cx + side * (legW * 0.75), footY - legW / 2);
      canvas.drawLine(hip, foot, limb);
    }

    // Torso: shoulders → waist → hips, mirrored.
    final torso = Path()..moveTo(cx - neck, shoulderY - figH * 0.03);
    torso
      ..quadraticBezierTo(cx - sh * 0.7, shoulderY - figH * 0.025, cx - sh, shoulderY + figH * 0.02)
      ..quadraticBezierTo(cx - (sh + wa) / 2, (shoulderY + waistY) / 2, cx - wa, waistY)
      ..quadraticBezierTo(cx - hi * 1.02, (waistY + hipY) / 2, cx - hi, hipY)
      ..quadraticBezierTo(cx - hi * 0.98, crotchY, cx - hi * 0.85, crotchY + figH * 0.01)
      ..lineTo(cx + hi * 0.85, crotchY + figH * 0.01)
      ..quadraticBezierTo(cx + hi * 0.98, crotchY, cx + hi, hipY)
      ..quadraticBezierTo(cx + hi * 1.02, (waistY + hipY) / 2, cx + wa, waistY)
      ..quadraticBezierTo(cx + (sh + wa) / 2, (shoulderY + waistY) / 2, cx + sh, shoulderY + figH * 0.02)
      ..quadraticBezierTo(cx + sh * 0.7, shoulderY - figH * 0.025, cx + neck, shoulderY - figH * 0.03)
      ..close();
    canvas.drawPath(torso, solid);

    // Neck + head.
    canvas.drawRect(Rect.fromLTRB(cx - neck, top + headR * 1.6, cx + neck, shoulderY), solid);
    canvas.drawCircle(Offset(cx, top + headR), headR, solid);

    canvas
      ..drawRect(bounds, Paint()..shader = fill.createShader(bounds)..blendMode = BlendMode.srcIn)
      ..restore();
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) => old.p != p || old.fill != fill;
}
