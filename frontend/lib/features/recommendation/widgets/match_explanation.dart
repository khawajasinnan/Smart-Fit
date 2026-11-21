import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// "92% match" chip on a product card; tap to see why (spec §23.25 explainable ranking).
class MatchBadge extends StatelessWidget {
  const MatchBadge({super.key, required this.product});

  final ProductRecommendation product;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${product.matchScore} percent match. Why this pick?',
      child: GestureDetector(
        onTap: () => showMatchExplanation(context, product),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: Colors.black.withValues(alpha: 0.45),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    product.validated == false ? Icons.help_outline_rounded : Icons.auto_awesome_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${product.matchScore}% match',
                    style: AppTextStyles.labelSm.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _aspectLabels = {
  'skin_tone': 'Suits your skin tone',
  'colours': 'Colours work together',
  'size': 'Your size in stock',
  'body_shape': 'Flatters your body shape',
  'occasion': 'Right for the occasion',
  'budget': 'Fits your budget',
};

Future<void> showMatchExplanation(BuildContext context, ProductRecommendation product) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MatchExplanationSheet(product: product),
  );
}

class MatchExplanationSheet extends StatelessWidget {
  const MatchExplanationSheet({super.key, required this.product});

  final ProductRecommendation product;

  @override
  Widget build(BuildContext context) {
    final helps = product.explanation.where((f) => f.helps).toList();
    final hurts = product.explanation.where((f) => !f.helps).toList();
    final aspects = [
      for (final e in _aspectLabels.entries)
        if (product.suitability[e.key] case final v?) (e.value, v),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Why this pick?', style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${product.matchScore}% match for you · ${product.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final f in helps) _FactorRow(text: f.text, helps: true),
            for (final f in hurts) _FactorRow(text: f.text, helps: false),
            if (aspects.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Suitability', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final (label, value) in aspects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 170, child: Text(label, style: AppTextStyles.bodySm)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: value / 100,
                            minHeight: 8,
                            backgroundColor: context.cs.surfaceContainerHigh,
                            valueColor: AlwaysStoppedAnimation(
                              value >= 70 ? AppColors.success : (value >= 45 ? AppColors.warning : AppColors.error),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 30,
                        child: Text('$value', textAlign: TextAlign.end, style: AppTextStyles.labelSm),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  product.validated == false ? Icons.info_outline_rounded : Icons.verified_rounded,
                  size: 16,
                  color: product.validated == false ? AppColors.warning : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    product.validated == false
                        ? 'Our second AI check was less sure about this one, so it is shown lower.'
                        : 'Ranked by our AI ranking model and confirmed by a second, independent AI check.',
                    style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.text, required this.helps});

  final String text;
  final bool helps;

  @override
  Widget build(BuildContext context) {
    final label = text[0].toUpperCase() + text.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            helps ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: helps ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTextStyles.bodyMd)),
        ],
      ),
    );
  }
}
