import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';

/// SafeNetworkImage widget with error handling and loading states
class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;
  final VoidCallback? onError;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.fadeInDuration = const Duration(milliseconds: 400),
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    // Validate URL
    if (imageUrl.isEmpty || !(Uri.tryParse(imageUrl)?.hasAbsolutePath ?? false)) {
      return _buildPlaceholder();
    }

    final int? cacheHeight = (height != null && height!.isFinite && height! > 0) ? height!.toInt() : null;
    final int? cacheWidth = (width != null && width!.isFinite && width! > 0) ? width!.toInt() : null;

    Widget imageWidget = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: fadeInDuration,
          child: child,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.electricPurple),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        onError?.call();
        return _buildPlaceholder();
      },
      headers: const {'Accept': 'image/*'},
      cacheHeight: cacheHeight,
      cacheWidth: cacheWidth,
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }

    return SizedBox(
      width: width,
      height: height,
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.outlineVariant.withValues(alpha: 0.1),
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: AppColors.outlineVariant,
          size: 40,
        ),
      ),
    );
  }
}
