import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// The logo's neon green (docs/brand/smartfit_mark.svg).
const Color kBrandLime = AppColors.neonGreen;

/// The brand line, shown under the wordmark (splash, login, about).
const String kTagline = 'Get your fit now!';

/// The SmartFit app mark: a neon hanger with a T-shirt and a tick on a
/// near-black tile (same artwork as the launcher icon; source:
/// docs/brand/smartfit_mark.svg).
class SFLogoMark extends StatelessWidget {
  const SFLogoMark({super.key, this.size = 40, this.glow = false});

  final double size;

  /// Kept for existing callers; the flat design has no glows.
  final bool glow;

  static const String asset = 'assets/images/smartfit_mark.png';

  @override
  Widget build(BuildContext context) {
    // Decorative: the wordmark or screen title next to it names the app.
    return ExcludeSemantics(
      child: Image.asset(asset, width: size, height: size, filterQuality: FilterQuality.medium),
    );
  }
}

/// "smartfit" in Space Grotesk Bold; "fit" in the brand green (neon on dark,
/// deep green on light, where neon text can't be read).
class SFWordmark extends StatelessWidget {
  const SFWordmark({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontWeight: FontWeight.w700,
      fontSize: fontSize,
      letterSpacing: -fontSize * 0.04,
      height: 1.05,
      color: context.sf.ink,
    );
    return Semantics(
      label: 'SmartFit',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'smart'),
            TextSpan(text: 'fit', style: TextStyle(color: context.sf.highlight)),
          ],
        ),
      ),
    );
  }
}

/// "Get your fit now!" under the wordmark.
class SFTagline extends StatelessWidget {
  const SFTagline({super.key, this.fontSize = 14, this.textAlign});

  final double fontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      kTagline,
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w500,
        fontSize: fontSize,
        height: 1.2,
        letterSpacing: 0.2,
        color: context.sf.textMuted,
      ),
    );
  }
}

/// Text in the brand colour. Was a gradient fill; the flat design uses one
/// readable colour ([SFColors.highlight]) unless a [gradient] is passed.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.gradient, this.textAlign});

  final String text;
  final TextStyle style;
  final Gradient? gradient;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final g = gradient;
    if (g == null) return Text(text, style: style.copyWith(color: context.sf.highlight), textAlign: textAlign);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => g.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style.copyWith(color: Colors.white), textAlign: textAlign),
    );
  }
}

/// Logo mark + "smartfit" wordmark side by side (headers, auth screens);
/// [tagline] adds "Get your fit now!" under the wordmark.
class SFBrandLockup extends StatelessWidget {
  const SFBrandLockup({super.key, this.markSize = 34, this.fontSize = 20, this.glow = false, this.tagline = false});

  final double markSize;
  final double fontSize;
  final bool glow;
  final bool tagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SFLogoMark(size: markSize),
        SizedBox(width: markSize * 0.3),
        if (!tagline)
          SFWordmark(fontSize: fontSize)
        else
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SFWordmark(fontSize: fontSize),
              SizedBox(height: fontSize * 0.15),
              SFTagline(fontSize: fontSize * 0.5),
            ],
          ),
      ],
    );
  }
}
