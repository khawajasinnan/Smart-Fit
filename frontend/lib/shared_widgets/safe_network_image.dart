import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/skeletons.dart';

/// Network image with disk caching (product photos, avatars, editorial
/// imagery), a shimmer while loading and a branded fallback when the photo
/// is missing or fails — never a broken-image box.
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.fadeInDuration = const Duration(milliseconds: 350),
    this.fallbackIcon = Icons.checkroom_rounded,
    this.alignment = Alignment.center,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;
  final IconData fallbackIcon;
  final Alignment alignment;

  /// Test hook: resolve URLs to local images (screenshot tests can't reach
  /// the network). Never set in the app.
  @visibleForTesting
  static ImageProvider Function(String url)? debugImageProviderOverride;

  bool get _isValidUrl {
    final uri = Uri.tryParse(imageUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (!_isValidUrl) {
      image = _Fallback(icon: fallbackIcon);
    } else if (debugImageProviderOverride != null) {
      image = Image(
        image: debugImageProviderOverride!(imageUrl),
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => _Fallback(icon: fallbackIcon),
      );
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = (width != null && width!.isFinite) ? (width! * dpr).round() : null;
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        memCacheWidth: cacheWidth,
        fadeInDuration: fadeInDuration,
        placeholder: (_, _) => const SFShimmer(child: SkeletonBox(radius: 0)),
        errorWidget: (_, _, _) => _Fallback(icon: fallbackIcon),
      );
    }

    image = SizedBox(width: width, height: height, child: image);
    if (borderRadius != null) image = ClipRRect(borderRadius: borderRadius!, child: image);
    return image;
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sf.orbA.withValues(alpha: 0.25), sf.orbB.withValues(alpha: 0.25)],
        ),
      ),
      child: Center(child: Icon(icon, size: 36, color: sf.ink.withValues(alpha: 0.35))),
    );
  }
}
