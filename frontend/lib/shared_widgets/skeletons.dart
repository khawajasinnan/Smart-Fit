import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// Skeleton placeholders shown while content loads — never a bare spinner
/// when the content's shape is known (design.md §5.2, SFR-021).
class SFShimmer extends StatelessWidget {
  const SFShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Shimmer.fromColors(
      baseColor: sf.shimmerBase,
      highlightColor: sf.shimmerHighlight,
      enabled: !context.reduceMotion,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// A single grey block (use inside [SFShimmer]).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = AppRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Skeleton for a product card (image + two text lines + price).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SFShimmer(
      child: SizedBox(
        width: width,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 3 / 4, child: SkeletonBox(radius: AppRadius.lg)),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(width: 90, height: 10),
            SizedBox(height: AppSpace.xs),
            SkeletonBox(height: 14),
            SizedBox(height: AppSpace.xs),
            SkeletonBox(width: 70, height: 14),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a list row (avatar + two lines).
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SFShimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: [
            SkeletonBox(width: 56, height: 56, radius: AppRadius.md),
            SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14),
                  SizedBox(height: AppSpace.xs),
                  SkeletonBox(width: 140, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
