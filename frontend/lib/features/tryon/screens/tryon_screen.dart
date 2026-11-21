import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/features/hairstyle/providers/hairstyle_provider.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/image_saver.dart';
import 'package:smartfit/core/utils/store_link.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/features/tryon/providers/tryon_provider.dart';
import 'package:smartfit/features/tryon/widgets/turntable_viewer.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// Opens the Try-On tab with [product] selected (used by "Try on" buttons):
/// the user lands straight on step 2, "Your photo".
void openTryOn(BuildContext context, WidgetRef ref, ProductRecommendation product) {
  ref.read(tryOnControllerProvider.notifier).selectProduct(product);
  context.go(RoutePaths.tryOn);
}

/// Virtual try-on (SRDS SFR-026..028, SF-UC-06) in three clear steps:
///   1. Clothes: a product from the wardrobe / chat, or a photo of your own clothes.
///   2. Your photo: one front photo (quick), or four photos for the 360° view.
///   3. Result: the 2D try-on, or a drag-to-spin 360° view of the four sides.
class TryOnScreen extends ConsumerWidget {
  const TryOnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tryOnControllerProvider);
    final body = switch (state.phase) {
      TryOnPhase.setup => state.hasGarment ? _PhotoStep(state: state) : _ClothesStep(state: state),
      TryOnPhase.running => _RunningView(state: state),
      TryOnPhase.result => _ResultView(state: state),
      TryOnPhase.unavailable => _UnavailableView(state: state),
      TryOnPhase.error => _ErrorView(state: state),
    };
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SFScaffold(
      body: Column(
        children: [
          _Header(step: state.step),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey('${state.phase}-${_garmentKey(state)}'), child: body),
            ),
          ),
        ],
      ),
    );
  }
}

String _garmentKey(TryOnState s) => s.product?.key ?? (s.ownGarment == null ? 'none' : 'own-${s.ownGarment.hashCode}');

/// Space the floating bottom navigation bar takes (the shell uses extendBody).
double _navSpace(BuildContext context) => MediaQuery.paddingOf(context).bottom;

// ── header with the three steps ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.step});

  final int step;

  static const _labels = ['Clothes', 'Your photo', 'Result'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Virtual Try-On', style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(gradient: context.sf.brandGradient, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '2D · 360°',
                  style: AppTextStyles.labelSm.copyWith(
                    color: context.sf.onBrand,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'Step $step of 3: ${_labels[step - 1]}',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 1; i <= 3; i++) ...[
                  if (i > 1)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          gradient: i <= step ? context.sf.brandGradient : null,
                          color: i <= step ? null : context.cs.outlineVariant.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  _StepDot(number: i, label: _labels[i - 1], state: i < step ? 1 : (i == step ? 0 : -1)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.number, required this.label, required this.state});

  final int number;
  final String label;

  /// 1 done, 0 current, -1 upcoming.
  final int state;

  @override
  Widget build(BuildContext context) {
    final active = state >= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: active ? context.sf.brandGradient : null,
            color: active ? null : context.cs.surfaceContainerHigh,
          ),
          child: state == 1
              ? Icon(Icons.check_rounded, size: 16, color: context.sf.onBrand)
              : Text(
                  '$number',
                  style: AppTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: active ? context.sf.onBrand : context.cs.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.labelSm.copyWith(
            fontWeight: state == 0 ? FontWeight.w700 : FontWeight.w500,
            color: state == 0 ? context.cs.onSurface : context.cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── step 1: choose the clothes ───────────────────────────────────────────────

class _ClothesStep extends ConsumerStatefulWidget {
  const _ClothesStep({required this.state});

  final TryOnState state;

  @override
  ConsumerState<_ClothesStep> createState() => _ClothesStepState();
}

class _ClothesStepState extends ConsumerState<_ClothesStep> {
  /// A clothes photo picked but not confirmed yet (needs its type).
  Uint8List? _pending;
  GarmentType? _type;
  final _name = TextEditingController();
  final _chest = TextEditingController();
  final _waist = TextEditingController();
  bool _inches = false;

  @override
  void initState() {
    super.initState();
    final debug = debugPickedClothes;
    if (debug != null) {
      _pending = debug.$1;
      _type = debug.$2;
    }
    _chest.addListener(_changed);
    _waist.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _chest.dispose();
    _waist.dispose();
    super.dispose();
  }

  Future<void> _pickClothes(ImageSource source) async {
    final bytes = await _pickImage(context, source);
    if (bytes != null && mounted) setState(() => _pending = bytes);
  }

  /// The typed width in cm, or null when empty / not a number / out of range.
  double? _cm(TextEditingController c) => flatWidthCm(c.text, inches: _inches);

  /// What's still missing before "Next" (null = ready).
  String? get _missing {
    final type = _type;
    if (type == null) return 'Choose what it is';
    if (type.needsChest && _cm(_chest) == null) return 'Enter the chest width';
    if (type.needsWaist && _cm(_waist) == null) return 'Enter the waist width';
    return null;
  }

  void _confirm() {
    final bytes = _pending;
    final type = _type;
    if (bytes == null || type == null || _missing != null) return;
    ref
        .read(tryOnControllerProvider.notifier)
        .selectOwnGarment(bytes, type, name: _name.text, chestWidthCm: _cm(_chest), waistWidthCm: _cm(_waist));
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(wardrobeNotifierProvider);
    final failure = widget.state.failure;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, _navSpace(context) + 24),
      children: [
        Text('What would you like to try on?', style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Upload a photo of your own clothes, or pick something from your wardrobe.',
          style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, height: 1.4),
        ),
        if (failure is TryOnPhotoFailure && failure.angle == 'garment') ...[
          const SizedBox(height: 12),
          NoticeBanner(tone: NoticeTone.error, title: 'Please use another clothes photo', message: failure.message),
        ],
        const SizedBox(height: 16),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _pending == null
              ? _UploadClothesCard(onPick: _pickClothes)
              : _ConfirmClothes(
                  bytes: _pending!,
                  type: _type,
                  name: _name,
                  chest: _chest,
                  waist: _waist,
                  inches: _inches,
                  onInches: (v) => setState(() => _inches = v),
                  missing: _missing,
                  onType: (t) => setState(() => _type = t),
                  onRetake: () => setState(() {
                    _pending = null;
                    _type = null;
                  }),
                  onConfirm: _missing == null ? _confirm : null,
                ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text('From your wardrobe', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: () => context.go(RoutePaths.chat),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Ask Zayn'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (saved.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: context.cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Icon(Icons.checkroom_rounded, color: context.cs.primary, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Nothing saved yet. Tap "Try on" on any product Zayn shows you, or save items to your wardrobe '
                    'to see them here.',
                    style: AppTextStyles.bodySm.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            itemCount: saved.length,
            itemBuilder: (context, i) =>
                _ProductTile(product: saved[i].product).animate().fadeIn(delay: (30 * i).ms, duration: 260.ms),
          ),
      ],
    );
  }
}

class _UploadClothesCard extends StatelessWidget {
  const _UploadClothesCard({required this.onPick});

  final void Function(ImageSource source) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.cs.primary.withValues(alpha: 0.12), context.cs.tertiary.withValues(alpha: 0.10)],
        ),
        border: Border.all(color: context.cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(gradient: context.sf.brandGradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.add_photo_alternate_rounded, color: context.sf.onBrand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your own clothes', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'A clear photo of one item, laid flat or on a hanger.',
                      style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Upload photo',
                  filled: true,
                  onTap: () => onPick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PillButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Take photo',
                  onTap: () => onPick(ImageSource.camera),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "52" (or "20.5" in inches) -> cm, or null when empty, not a number or out
/// of the accepted range (the server checks the same range).
@visibleForTesting
double? flatWidthCm(String text, {required bool inches}) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null) return null;
  final cm = inches ? value * 2.54 : value;
  if (cm < kMinFlatWidthCm || cm > kMaxFlatWidthCm) return null;
  return double.parse(cm.toStringAsFixed(1));
}

class _ConfirmClothes extends StatelessWidget {
  const _ConfirmClothes({
    required this.bytes,
    required this.type,
    required this.name,
    required this.chest,
    required this.waist,
    required this.inches,
    required this.onInches,
    required this.missing,
    required this.onType,
    required this.onRetake,
    required this.onConfirm,
  });

  final Uint8List bytes;
  final GarmentType? type;
  final TextEditingController name;
  final TextEditingController chest;
  final TextEditingController waist;
  final bool inches;
  final ValueChanged<bool> onInches;
  final String? missing;
  final ValueChanged<GarmentType> onType;
  final VoidCallback onRetake;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cs.primary.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(bytes, width: 92, height: 122, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What is it?', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'This tells the AI which part of your outfit to change.',
                      style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: onRetake,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Use another photo'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final t in GarmentType.values) ...[
            _ChoiceCard(
              selected: type == t,
              icon: switch (t) {
                GarmentType.upper => Icons.dry_cleaning_rounded,
                GarmentType.lower => Icons.straighten_rounded,
                GarmentType.dress => Icons.woman_rounded,
              },
              title: t.label,
              subtitle: t.examples,
              onTap: () => onType(t),
            ),
            const SizedBox(height: 8),
          ],
          if (type != null) ...[
            const SizedBox(height: 6),
            _MeasureClothes(type: type!, chest: chest, waist: waist, inches: inches, onInches: onInches),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: name,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name it (optional)',
              hintText: 'e.g. white cotton kurta',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          SFButton(
            label: missing ?? 'Next: your photo',
            trailingIcon: missing == null ? Icons.arrow_forward_rounded : null,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// The garment's size, measured flat with a tape: the server compares it with
/// the user's profile measurements and reports small / big (the try-on still runs).
class _MeasureClothes extends StatelessWidget {
  const _MeasureClothes({
    required this.type,
    required this.chest,
    required this.waist,
    required this.inches,
    required this.onInches,
  });

  final GarmentType type;
  final TextEditingController chest;
  final TextEditingController waist;
  final bool inches;
  final ValueChanged<bool> onInches;

  @override
  Widget build(BuildContext context) {
    final unit = inches ? 'in' : 'cm';
    Widget field(TextEditingController c, String label, String help) {
      final filled = c.text.trim().isNotEmpty;
      final ok = flatWidthCm(c.text, inches: inches) != null;
      return TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          suffixText: unit,
          errorText: filled && !ok
              ? (inches
                    ? 'Between 6 and 47 in'
                    : 'Between ${kMinFlatWidthCm.toInt()} and ${kMaxFlatWidthCm.toInt()} cm')
              : null,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: context.cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.straighten_rounded, color: context.cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Its size', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('cm')),
                  ButtonSegment(value: true, label: Text('in')),
                ],
                selected: {inches},
                onSelectionChanged: (s) => onInches(s.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lay it flat and measure straight across with a tape. We compare it with the measurements in '
            "your profile and tell you if it's small or big.",
            style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, height: 1.35),
          ),
          if (type.needsChest) ...[
            const SizedBox(height: 10),
            field(chest, 'Chest width', 'Armpit to armpit, front side only'),
          ],
          if (type.needsWaist) ...[
            const SizedBox(height: 10),
            field(waist, 'Waist width', 'Waistband, edge to edge, not stretched'),
          ],
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.10) : cs.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: AppTextStyles.bodySm.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: selected
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey(true), color: cs.primary)
                      : Icon(Icons.circle_outlined, key: const ValueKey(false), color: cs.outlineVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final ProductRecommendation product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: context.cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ref.read(tryOnControllerProvider.notifier).selectProduct(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SafeNetworkImage(imageUrl: product.imageUrl ?? ''),
                  if (product.hasTryOn)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ActionChip(
                        avatar: const Icon(Icons.threesixty_rounded, size: 16),
                        label: const Text('Saved try-on'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => showSavedTryOn(context, ref, product),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.brand.toUpperCase(),
                    style: AppTextStyles.labelSm.copyWith(color: context.cs.primary, fontWeight: FontWeight.w700),
                  ),
                  Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A try-on saved in the wardrobe: fresh signed links, then the 360° view.
Future<void> showSavedTryOn(BuildContext context, WidgetRef ref, ProductRecommendation product) async {
  final api = ref.read(tryOnApiServiceProvider);
  final ordered = [
    for (final a in TryOnAngle.values)
      if (product.tryOnPaths[a.id] != null) a,
  ];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: FutureBuilder<Map<String, String>>(
        future: api.sign([for (final a in ordered) product.tryOnPaths[a.id]!]),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: SFLoader(label: 'Opening your try-on…'));
          }
          final urls = snap.data ?? const {};
          final frames = [
            for (final a in ordered)
              if (urls[product.tryOnPaths[a.id]] != null)
                TurntableFrame(image: _remote(urls[product.tryOnPaths[a.id]]!), label: a.label),
          ];
          if (frames.isEmpty) {
            return const _CenteredMessage(
              icon: Icons.image_not_supported_outlined,
              title: "Couldn't open this try-on",
              message: 'It may have been removed. You can try the item on again.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text(product.title, style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TurntableViewer(frames: frames),
              const SizedBox(height: 16),
              _DownloadButton(
                urls: {
                  for (final a in ordered)
                    if (urls[product.tryOnPaths[a.id]] != null) a: urls[product.tryOnPaths[a.id]]!,
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

// ── step 2: the user's photo(s) ──────────────────────────────────────────────

class _PhotoStep extends ConsumerWidget {
  const _PhotoStep({required this.state});

  final TryOnState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(tryOnControllerProvider.notifier);
    final photoFailure = state.failure is TryOnPhotoFailure ? state.failure as TryOnPhotoFailure : null;
    final missing = state.missingPhotos;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              _GarmentSummary(state: state, onChange: controller.clearProduct),
              const SizedBox(height: 18),
              Text('How do you want to see it?', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      selected: !state.spin360,
                      icon: Icons.person_rounded,
                      title: 'Quick',
                      subtitle: '1 photo · ~1 min',
                      onTap: () => controller.setSpin360(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeCard(
                      selected: state.spin360,
                      icon: Icons.threesixty_rounded,
                      title: '360° view',
                      subtitle: '4 photos · ~2 min',
                      onTap: () => controller.setSpin360(true),
                    ),
                  ),
                ],
              ),
              if (photoFailure != null && photoFailure.angle != 'garment') ...[
                const SizedBox(height: 14),
                NoticeBanner(tone: NoticeTone.error, title: 'Please retake a photo', message: photoFailure.message),
              ],
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: state.spin360
                    ? _FourPhotos(key: const ValueKey('360'), state: state, failedAngle: photoFailure?.angle)
                    : _OnePhoto(
                        key: const ValueKey('one'),
                        bytes: state.photos[TryOnAngle.front],
                        highlighted: photoFailure?.angle == TryOnAngle.front.id,
                      ),
              ),
              const SizedBox(height: 14),
              const _TipsCard(),
            ],
          ),
        ),
        _BottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SFButton(
                label: missing == 0
                    ? (state.spin360 ? 'Create my 360° try-on' : 'Create my try-on')
                    : (state.spin360 ? 'Add $missing more photo${missing == 1 ? '' : 's'}' : 'Add your photo first'),
                icon: Icons.auto_awesome_rounded,
                onPressed: state.readyToStart ? controller.start : null,
              ),
              const SizedBox(height: 6),
              Text(
                'Private: your photos are used only for this try-on.',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSm.copyWith(color: context.cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sticky action area above the floating navigation bar.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, _navSpace(context) + 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: context.cs.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: child,
    );
  }
}

class _GarmentSummary extends StatelessWidget {
  const _GarmentSummary({required this.state, this.onChange});

  final TryOnState state;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final product = state.product;
    final own = state.ownGarment;
    final Widget thumb = product != null
        ? SafeNetworkImage(
            imageUrl: product.imageUrl ?? '',
            width: 60,
            height: 78,
            borderRadius: BorderRadius.circular(14),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(own!.bytes, width: 60, height: 78, fit: BoxFit.cover),
          );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product != null ? product.brand.toUpperCase() : 'YOUR CLOTHES · ${own!.type.label.toUpperCase()}',
                  style: AppTextStyles.labelSm.copyWith(color: context.cs.primary, fontWeight: FontWeight.w700),
                ),
                Text(
                  product?.title ?? own!.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w600),
                ),
                if (product != null) ...[
                  const SizedBox(height: 2),
                  Text(product.formattedPrice, style: AppTextStyles.bodySm),
                ],
              ],
            ),
          ),
          if (onChange != null) TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Semantics(
      selected: selected,
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: selected ? context.sf.brandGradient : null,
              color: selected ? null : cs.surfaceContainerLow,
              border: Border.all(color: selected ? Colors.transparent : cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: selected ? context.sf.onBrand : cs.primary),
                    const Spacer(),
                    if (selected) Icon(Icons.check_circle_rounded, color: context.sf.onBrand, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTextStyles.titleSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? context.sf.onBrand : cs.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.labelSm.copyWith(
                    color: selected ? context.sf.onBrand.withValues(alpha: 0.8) : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick mode: one big front photo with the three ways to add it.
class _OnePhoto extends ConsumerWidget {
  const _OnePhoto({super.key, required this.bytes, this.highlighted = false});

  final Uint8List? bytes;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const angle = TryOnAngle.front;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            // Small while empty so the add buttons stay on screen; bigger once there's a photo to check.
            constraints: BoxConstraints(maxWidth: bytes == null ? 165 : 210),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _PhotoFrame(
                bytes: bytes,
                label: 'Your full-body photo',
                hint: 'Facing the camera, head to knees.',
                highlighted: highlighted,
                onTap: () => _showPhotoSheet(context, ref, angle),
                onRemove: () => ref.read(tryOnControllerProvider.notifier).removePhoto(angle),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (bytes != null)
          Text(
            'Looks good? Tap the photo to change it.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
          )
        else
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  filled: true,
                  onTap: () => _addPhoto(context, ref, angle, ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PillButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () => _addPhoto(context, ref, angle, ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PillButton(
                  icon: Icons.account_circle_rounded,
                  label: 'Profile',
                  onTap: () => _useProfilePhoto(context, ref, angle),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 360° mode: four sides; tap a side to add its photo.
class _FourPhotos extends StatelessWidget {
  const _FourPhotos({super.key, required this.state, this.failedAngle});

  final TryOnState state;
  final String? failedAngle;

  @override
  Widget build(BuildContext context) {
    final done = TryOnAngle.values.where(state.photos.containsKey).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Turn a quarter for each photo',
                style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
              ),
            ),
            Text('$done of 4 added', style: AppTextStyles.labelSm.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: done / 4),
            duration: const Duration(milliseconds: 300),
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 3 / 4,
          children: [
            for (final angle in TryOnAngle.values)
              Consumer(
                builder: (context, ref, _) => _PhotoFrame(
                  bytes: state.photos[angle],
                  label: angle.label,
                  hint: angle.instruction,
                  icon: _angleIcon(angle),
                  compact: true,
                  highlighted: failedAngle == angle.id,
                  onTap: () => _showPhotoSheet(context, ref, angle),
                  onRemove: () => ref.read(tryOnControllerProvider.notifier).removePhoto(angle),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

IconData _angleIcon(TryOnAngle a) => switch (a) {
  TryOnAngle.front => Icons.person_rounded,
  TryOnAngle.right => Icons.turn_right_rounded,
  TryOnAngle.back => Icons.person_outline_rounded,
  TryOnAngle.left => Icons.turn_left_rounded,
};

class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({
    required this.bytes,
    required this.label,
    required this.hint,
    required this.onTap,
    required this.onRemove,
    this.icon = Icons.accessibility_new_rounded,
    this.compact = false,
    this.highlighted = false,
  });

  final Uint8List? bytes;
  final String label;
  final String hint;
  final IconData icon;
  final bool compact;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final border = highlighted ? cs.error : (bytes != null ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant);
    // "Front" -> "Front photo"; "Your full-body photo" stays as it is (was "Add Your full-body photo photo")
    final what = label.toLowerCase().endsWith('photo') ? label : '$label photo';
    return Semantics(
      button: true,
      label: bytes == null ? 'Add ${what[0].toLowerCase()}${what.substring(1)}' : '$what added. Tap to replace.',
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border, width: highlighted ? 2.2 : 1.4),
            ),
            child: bytes != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _Badge(text: label, icon: Icons.check_circle_rounded),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          tooltip: 'Remove $label photo',
                          onPressed: onRemove,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 220.ms)
                : Padding(
                    padding: EdgeInsets.all(compact ? 10 : 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: compact ? 46 : 64,
                          height: compact ? 46 : 64,
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
                          child: Icon(icon, color: cs.primary, size: compact ? 26 : 34),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: (compact ? AppTextStyles.titleSm : AppTextStyles.titleMd).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            maxLines: compact ? 3 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSm.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                          ),
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_rounded, size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to add',
                              style: AppTextStyles.labelSm.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                            ),
                          ],
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

/// Camera / gallery / profile photo for one side.
Future<void> _showPhotoSheet(BuildContext context, WidgetRef ref, TryOnAngle angle) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${angle.label} photo', style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(angle.instruction, style: AppTextStyles.bodySm.copyWith(color: sheet.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                Navigator.of(sheet).pop();
                _addPhoto(context, ref, angle, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                Navigator.of(sheet).pop();
                _addPhoto(context, ref, angle, ImageSource.gallery);
              },
            ),
            if (angle == TryOnAngle.front)
              ListTile(
                leading: const Icon(Icons.account_circle_rounded),
                title: const Text('Use my profile photo'),
                subtitle: const Text('Best if it shows your whole body'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _useProfilePhoto(context, ref, angle);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<Uint8List?> _pickImage(BuildContext context, ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return null;
    return await file.readAsBytes();
  } catch (_) {
    if (context.mounted) _snack(context, "Couldn't open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.");
    return null;
  }
}

Future<void> _addPhoto(BuildContext context, WidgetRef ref, TryOnAngle angle, ImageSource source) async {
  final bytes = await _pickImage(context, source);
  if (bytes != null) ref.read(tryOnControllerProvider.notifier).setPhoto(angle, bytes);
}

/// SFR-017: reuse the profile photo instead of uploading a new one.
Future<void> _useProfilePhoto(BuildContext context, WidgetRef ref, TryOnAngle angle) async {
  final uid = ref.read(currentUserProvider)?.id;
  final url = uid == null ? null : ref.read(profileNotifierProvider(uid)).valueOrNull?.photoUrl;
  if (url == null || url.trim().isEmpty) {
    _snack(context, 'You have no profile photo yet. Use the camera or gallery instead.');
    return;
  }
  try {
    final res = await ref
        .read(externalDioProvider)
        .get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    final data = res.data;
    if (data == null || data.isEmpty) throw StateError('empty');
    ref.read(tryOnControllerProvider.notifier).setPhoto(angle, Uint8List.fromList(data));
    if (context.mounted) _snack(context, 'Using your profile photo. A full-body photo gives the best result.');
  } catch (_) {
    if (context.mounted) _snack(context, "Couldn't load your profile photo. Please use the camera instead.");
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    const tips = [
      (Icons.accessibility_new_rounded, 'Full body, head to knees at least, standing straight.'),
      (Icons.wb_sunny_rounded, 'Plain wall, good light, only you in the photo.'),
      (Icons.checkroom_rounded, 'Fitted clothes work best; take off jackets and bags.'),
      (Icons.timer_rounded, 'For the sides and back, ask a friend or use the phone timer.'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          leading: Icon(Icons.tips_and_updates_rounded, color: context.cs.primary),
          title: Text('Tips for a great result', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: context.cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: AppTextStyles.bodySm.copyWith(height: 1.35))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── step 3a: creating ────────────────────────────────────────────────────────

class _RunningView extends StatefulWidget {
  const _RunningView({required this.state});

  final TryOnState state;

  @override
  State<_RunningView> createState() => _RunningViewState();
}

class _RunningViewState extends State<_RunningView> {
  static const _lines = [
    'Finding your pose…',
    'Fitting the garment to your shape…',
    'Matching the fabric and the light…',
    'Checking the drape from every side…',
    'Adding the finishing touches…',
  ];
  int _line = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => setState(() => _line = (_line + 1) % _lines.length));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final job = state.job;
    final views = job?.views ?? const <TryOnView>[];
    final estimate = job?.estimatedSeconds ?? 0;
    final front = state.photos[TryOnAngle.front];
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 12, 24, _navSpace(context) + 24),
      children: [
        // garment + you = try-on
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundThumb(child: _garmentImage(state, 84, 112)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.add_rounded, color: context.cs.onSurfaceVariant),
            ),
            _RoundThumb(
              child: front == null
                  ? const SizedBox(width: 84, height: 112)
                  : Image.memory(front, width: 84, height: 112, fit: BoxFit.cover),
            ),
          ],
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 26),
        // the cloth-warping step, shown as soon as it's ready (21 Nov 2026)
        if (_fittingOf(views) case final fitting?) ...[
          _FittingPreview(url: fitting),
          const SizedBox(height: 18),
        ] else
          const Center(child: SFLoader(size: 84)),
        const SizedBox(height: 18),
        Text(
          state.spin360 ? 'Creating your 360° try-on' : 'Creating your try-on',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSm.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_lines[_line], key: ValueKey(_line), textAlign: TextAlign.center, style: AppTextStyles.bodyMd),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: job?.progress ?? 0.02),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          job == null
              ? 'Sending your photos securely…'
              : 'Usually about ${(estimate / 60).ceil()} min. The first try-on after a break takes a little longer '
                    'while the AI studio warms up.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
        ),
        if (views.length > 1) ...[
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final v in views) _ViewStatusChip(view: v)],
          ),
        ],
        const SizedBox(height: 20),
        Text(
          "You can look around the app meanwhile. We'll keep working on it.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RoundThumb extends StatelessWidget {
  const _RoundThumb({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.6)),
        color: context.cs.surfaceContainerLow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// The fitting preview to show: the front view's, else the first one ready.
String? _fittingOf(List<TryOnView> views) {
  final ready = views.where((v) => v.fittingUrl != null).toList();
  if (ready.isEmpty) return null;
  return (ready.where((v) => v.angle == TryOnAngle.front).firstOrNull ?? ready.first).fittingUrl;
}

/// The cloth-warping step while the GPU works: the garment laid over the body outline.
class _FittingPreview extends StatelessWidget {
  const _FittingPreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          image: true,
          label: 'Fitting preview: your garment laid over your body outline',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image(image: _remote(url), height: 280, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 8),
        Text('Fitting your garment', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
        Text(
          'Step 1: the garment is warped to your shape. Next the AI paints it realistically.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
        ),
      ],
    ).animate().fadeIn(duration: 350.ms);
  }
}

/// "How it was fitted": the store photo, the warped garment on the body, the final try-on.
class _HowItWasFitted extends StatelessWidget {
  const _HowItWasFitted({required this.state, required this.fittingUrl, required this.resultUrl});

  final TryOnState state;
  final String fittingUrl;
  final String resultUrl;

  @override
  Widget build(BuildContext context) {
    Widget step(Widget image, String label) => Expanded(
      child: Column(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 120, child: image)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: AppTextStyles.labelSm),
        ],
      ),
    );
    final arrow = Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Icon(Icons.arrow_forward_rounded, size: 18, color: context.cs.onSurfaceVariant),
    );
    return SFGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it was fitted', style: AppTextStyles.titleMd.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              step(_garmentImage(state, 90, 120), 'Garment'),
              arrow,
              step(Image(image: _remote(fittingUrl), fit: BoxFit.cover), 'Warped to you'),
              arrow,
              step(Image(image: _remote(resultUrl), fit: BoxFit.cover), 'AI try-on'),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _garmentImage(TryOnState state, double w, double h) {
  final own = state.ownGarment;
  if (own != null) return Image.memory(own.bytes, width: w, height: h, fit: BoxFit.cover);
  return SafeNetworkImage(imageUrl: state.product?.imageUrl ?? '', width: w, height: h);
}

class _ViewStatusChip extends StatelessWidget {
  const _ViewStatusChip({required this.view});

  final TryOnView view;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (view.status) {
      TryOnViewStatus.done => (Icons.check_circle_rounded, Colors.green),
      TryOnViewStatus.failed => (Icons.error_rounded, context.cs.error),
      _ => (Icons.hourglass_top_rounded, context.cs.primary),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: colour),
      label: Text(view.angle.label),
    );
  }
}

// ── step 3b: the result ──────────────────────────────────────────────────────

class _ResultView extends ConsumerStatefulWidget {
  const _ResultView({required this.state});

  final TryOnState state;

  @override
  ConsumerState<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends ConsumerState<_ResultView> {
  bool _showOriginal = false;
  bool _downloading = false;

  Future<void> _download(List<TryOnView> views) async {
    setState(() => _downloading = true);
    final error = await downloadTryOnImages(ref, {for (final v in views) v.angle: v.imageUrl!});
    if (!mounted) return;
    setState(() => _downloading = false);
    _snack(context, error ?? 'Saved to $savedImageLocation ✨');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final job = state.job!;
    final product = state.product;
    final controller = ref.read(tryOnControllerProvider.notifier);
    final done = job.finishedViews;
    final failed = job.views.where((v) => v.status == TryOnViewStatus.failed).toList();
    final frames = _showOriginal
        ? [
            for (final v in done)
              if (state.photos[v.angle] != null)
                TurntableFrame(image: MemoryImage(state.photos[v.angle]!), label: v.angle.label),
          ]
        : [for (final v in done) TurntableFrame(image: _remote(v.imageUrl!), label: v.angle.label)];

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, _navSpace(context) + 24),
      children: [
        if (job.isTestMode) ...[
          const NoticeBanner(
            tone: NoticeTone.warning,
            title: 'Test mode',
            message: 'The AI studio is not connected, so these are placeholder images, not a real try-on.',
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                done.length > 1 ? 'Your 360° try-on' : 'Your try-on',
                style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('After')),
                ButtonSegment(value: true, label: Text('Before')),
              ],
              selected: {_showOriginal},
              onSelectionChanged: (s) => setState(() => _showOriginal = s.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TurntableViewer(key: ValueKey(_showOriginal), frames: frames).animate().fadeIn(duration: 350.ms),
        for (final v in failed) ...[
          const SizedBox(height: 10),
          NoticeBanner(
            tone: NoticeTone.warning,
            title: '${v.angle.label} side not ready',
            message: v.message ?? 'This side could not be made.',
          ),
        ],
        if (job.fit != null) ...[const SizedBox(height: 12), _FitNote(fit: job.fit!)],
        // the cloth-warping step: garment -> fitted to the body -> final (21 Nov 2026)
        if (_fittingOf(done) case final fitting? when done.isNotEmpty) ...[
          const SizedBox(height: 12),
          _HowItWasFitted(state: state, fittingUrl: fitting, resultUrl: done.first.imageUrl!),
        ],
        const SizedBox(height: 12),
        _GarmentSummary(state: state),
        const SizedBox(height: 16),
        SFButton(
          label: done.length > 1 ? 'Download all ${done.length} images' : 'Download image',
          icon: Icons.download_rounded,
          variant: product == null ? SFButtonVariant.primary : SFButtonVariant.secondary,
          isLoading: _downloading,
          onPressed: job.isTestMode ? null : () => _download(done),
        ),
        const SizedBox(height: 10),
        if (product != null) ...[
          // SFR-032/033: how well this outfit (+ the chosen hairstyle) suits the user
          SFButton(
            label: 'Score this look',
            icon: Icons.stars_rounded,
            variant: SFButtonVariant.secondary,
            onPressed: () => context.push(RoutePaths.lookScore, extra: LookScoreArgs(product: product, fit: job.fit)),
          ),
          const SizedBox(height: 10),
          // SRDS 2.3.6 / SFR-029: hairstyles that go with this outfit, straight from the try-on
          SFButton(
            label: 'Find a matching hairstyle',
            icon: Icons.face_retouching_natural,
            variant: SFButtonVariant.secondary,
            onPressed: () {
              ref.read(hairstyleOutfitProvider.notifier).state = product;
              context.go(RoutePaths.hairstyle);
            },
          ),
          const SizedBox(height: 10),
          SFButton(
            label: state.savedToWardrobe ? 'Saved to wardrobe' : 'Save to wardrobe',
            icon: state.savedToWardrobe ? Icons.check_rounded : Icons.checkroom_rounded,
            onPressed: state.savedToWardrobe
                ? null
                : () {
                    var item = product.withTryOn(job.storagePaths);
                    // SFR-035: with the hairstyle chosen for this outfit, if there is one
                    final hair = ref.read(chosenHairstyleProvider);
                    if (hair != null && ref.read(hairstyleOutfitProvider)?.key == product.key) {
                      item = item.withHairstyle(hair.toWardrobeJson());
                    }
                    ref.read(wardrobeNotifierProvider.notifier).saveProduct(item);
                    controller.markSaved();
                    _snack(context, item.hasHairstyle ? 'Saved with your try-on and hairstyle ✨'
                        : 'Saved with your try-on ✨');
                  },
          ),
          const SizedBox(height: 10),
          SFButton(
            label: 'View on store',
            variant: SFButtonVariant.outline,
            icon: Icons.open_in_new_rounded,
            onPressed: () => openStoreLink(context, product.productUrl),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _PillButton(
                icon: Icons.photo_camera_back_rounded,
                label: 'New photos',
                onTap: controller.backToSetup,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Other clothes',
                filled: product == null,
                onTap: controller.clearProduct,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'AI-generated preview: colours, fit and the back of the garment are the AI\'s best guess from the photo.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Downloads the generated images (the real VTON output, full resolution) and
/// saves them for the user. Returns an error message, or null when all saved.
Future<String?> downloadTryOnImages(WidgetRef ref, Map<TryOnAngle, String> urls) async {
  final dio = ref.read(externalDioProvider); // signed URLs: no login token needed or sent
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
  try {
    for (final e in urls.entries) {
      final res = await dio.get<List<int>>(e.value, options: Options(responseType: ResponseType.bytes));
      final data = res.data;
      if (data == null || data.isEmpty) return "Couldn't download the image. Please try again.";
      await saveImageBytes(Uint8List.fromList(data), 'smartfit-tryon-${e.key.id}-$stamp');
    }
    return null;
  } on SaveImageException catch (e) {
    return e.message;
  } catch (_) {
    return "Couldn't download the image. Check your connection and try again.";
  }
}

class _DownloadButton extends ConsumerStatefulWidget {
  const _DownloadButton({required this.urls});

  final Map<TryOnAngle, String> urls;

  @override
  ConsumerState<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<_DownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    final error = await downloadTryOnImages(ref, widget.urls);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, error ?? 'Saved to $savedImageLocation ✨');
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    return SFButton(
      label: n > 1 ? 'Download all $n images' : 'Download image',
      icon: Icons.download_rounded,
      isLoading: _busy,
      onPressed: n == 0 ? null : _download,
    );
  }
}

class _FitNote extends StatelessWidget {
  const _FitNote({required this.fit});

  final TryOnFit fit;

  @override
  Widget build(BuildContext context) {
    final (colour, icon, title) = switch (fit.status) {
      TryOnFitStatus.fits => (
          Colors.green.shade600,
          Icons.verified_rounded,
          fit.size != null ? 'Fits you · size ${fit.size}' : 'Fits you',
        ),
      TryOnFitStatus.small => (Colors.red.shade600, Icons.straighten_rounded, 'This size is small for you'),
      TryOnFitStatus.big => (Colors.orange.shade700, Icons.straighten_rounded, 'This size is big for you'),
      TryOnFitStatus.unknown => (context.cs.onSurfaceVariant, Icons.info_outline_rounded, 'Fit not checked'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
                if (fit.note.isNotEmpty)
                  Text(
                    fit.note,
                    style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, height: 1.35),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── SFR-027: can't be tried on, and errors ───────────────────────────────────

class _UnavailableView extends ConsumerWidget {
  const _UnavailableView({required this.state});

  final TryOnState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = state.product;
    final controller = ref.read(tryOnControllerProvider.notifier);
    final f = state.failure;
    final reason = f is TryOnUnavailableFailure ? f.reason : null;
    final gone = reason == 'gone'; // the brand no longer sells it (or it's sold out)
    final title = switch (reason) {
      'garment_image' => "We couldn't load this item's photo",
      'gone' => 'No longer available',
      'gender' => 'Not for your profile',
      'size_sold_out' => 'Your size is sold out', // SFR-025
      _ => "This one can't be tried on",
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, _navSpace(context) + 24),
      children: [
        Icon(
          switch (reason) {
            'garment_image' => Icons.image_not_supported_outlined,
            'gone' => Icons.remove_shopping_cart_outlined,
            'gender' => Icons.wc_rounded,
            'size_sold_out' => Icons.straighten_rounded,
            _ => Icons.do_not_disturb_on_outlined,
          },
          size: 56,
          color: context.cs.primary,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSm.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(state.failure?.message ?? '', textAlign: TextAlign.center, style: AppTextStyles.bodyMd),
        const SizedBox(height: 20),
        if (product != null && !gone) ...[
          // Alternative viewing option (SFR-027): the store's own photo, zoomable, and the product page.
          TurntableViewer(
            frames: [TurntableFrame(image: _remote(product.imageUrl ?? ''), label: 'Store photo')],
            initialAutoSpin: false,
          ),
          const SizedBox(height: 16),
          SFButton(
            label: 'View on store',
            icon: Icons.open_in_new_rounded,
            onPressed: () => openStoreLink(context, product.productUrl),
          ),
          const SizedBox(height: 10),
        ],
        SFButton(
          label: product == null ? 'Change clothes or measurements' : 'Try something else',
          variant: product == null || gone ? SFButtonVariant.primary : SFButtonVariant.outline,
          onPressed: controller.clearProduct,
        ),
      ],
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.state});

  final TryOnState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(tryOnControllerProvider.notifier);
    final failure = state.failure;
    final notConnected = failure?.code == 'TRYON_NOT_CONNECTED';
    return _CenteredMessage(
      icon: notConnected ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
      title: notConnected ? 'The AI studio is offline' : "That didn't work",
      message: failure?.message ?? "We couldn't make your try-on this time.",
      actionLabel: 'Try again',
      onAction: controller.start,
      secondaryLabel: 'Change photos',
      onSecondary: controller.backToSetup,
    );
  }
}

// ── small pieces ─────────────────────────────────────────────────────────────

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(32, 16, 32, _navSpace(context) + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: context.cs.primary).animate().fadeIn().scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSm.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurfaceVariant, height: 1.45),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              SFButton(label: actionLabel!, onPressed: onAction),
            ],
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 4)],
          Text(
            text,
            style: AppTextStyles.labelSm.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Screenshot tests: a clothes photo already picked (and its type), since a
/// test can't open the gallery.
@visibleForTesting
(Uint8List, GarmentType?)? debugPickedClothes;

/// Screenshot tests swap the viewer's network images for local ones.
@visibleForTesting
ImageProvider Function(String url)? debugTryOnImageOverride;

ImageProvider _remote(String url) => debugTryOnImageOverride?.call(url) ?? NetworkImage(url);

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(20)),
  );
}
