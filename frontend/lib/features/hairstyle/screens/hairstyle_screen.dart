import 'package:smartfit/features/scoring/data/look_score_models.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/image_saver.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_api_service.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';
import 'package:smartfit/features/hairstyle/providers/hairstyle_provider.dart';
import 'package:smartfit/features/hairstyle/widgets/face_capture_camera.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/pressable.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// Test hook: a photo instead of opening the camera / gallery.
@visibleForTesting
Uint8List? debugHairstylePhoto;

/// AI hairstyles (SRDS SFR-029..031, SF-UC-07):
///   1. a face photo: the camera with a head circle takes it automatically
///      once the face is centred, straight, sharp and well lit (or upload one);
///   2. the face shape is measured from the face mesh;
///   3. the best-suited hairstyles are shown on the user's own face, the best
///      match first, with before/after and a download.
class HairstyleScreen extends ConsumerWidget {
  const HairstyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hairstyleControllerProvider);
    // keyed per phase: each view starts scrolled to the top (the lists would otherwise share a position)
    final body = KeyedSubtree(
      key: ValueKey(state.phase),
      child: switch (state.phase) {
        HairstylePhase.intro => const _IntroView(),
        HairstylePhase.analysing => _AnalysingView(photo: state.photo),
        HairstylePhase.result => _ResultView(state: state),
        HairstylePhase.error => _ErrorView(state: state),
      },
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SFScaffold(
      body: Column(
        children: [
          const _Header(),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
              child: KeyedSubtree(key: ValueKey(state.phase), child: body),
            ),
          ),
        ],
      ),
    );
  }
}

/// Space under scrolling content for the floating nav bar (the tab Scaffold
/// extends its body behind the bar and reports it as bottom padding).
double _navSpace(BuildContext context) => MediaQuery.paddingOf(context).bottom;

/// Opens the camera (or the gallery) and analyses the photo.
Future<void> _getPhoto(BuildContext context, WidgetRef ref, {required bool camera}) async {
  Uint8List? photo = debugHairstylePhoto;
  if (photo == null) {
    if (camera) {
      photo = await showDialog<Uint8List>(
        context: context,
        useSafeArea: false,
        builder: (_) => const FaceCaptureCamera(),
      );
    } else {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 92);
      photo = await file?.readAsBytes();
    }
  }
  if (photo == null || !context.mounted) return;
  final uid = ref.read(currentUserProvider)?.id;
  final gender = uid == null ? null : ref.read(profileNotifierProvider(uid)).valueOrNull?.gender;
  await ref.read(hairstyleControllerProvider.notifier).analyse(photo, gender: catalogGender(gender));
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Row(
        children: [
          Expanded(
            // one line on every phone: shrinks rather than wrapping
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('AI Hairstyle', maxLines: 1, style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(gradient: context.sf.brandGradient, borderRadius: BorderRadius.circular(20)),
            child: Text(
              'AI preview',
              style: AppTextStyles.labelSm.copyWith(color: context.sf.onBrand, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 1. intro ─────────────────────────────────────────────────────────────────

class _IntroView extends ConsumerWidget {
  const _IntroView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, _navSpace(context) + 32),
      children: [
        SFEntrance(
          index: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(gradient: context.sf.brandGradient, shape: BoxShape.circle),
                      child: Icon(Icons.face_retouching_natural_rounded, color: context.sf.onBrand, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Find the hairstyle that suits your face',
                        style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _Step(
                  number: 1,
                  icon: Icons.photo_camera_front_rounded,
                  text: 'Take a face photo inside the circle',
                ),
                const _Step(number: 2, icon: Icons.straighten_rounded, text: 'We measure your face shape'),
                const _Step(number: 3, icon: Icons.auto_awesome_rounded, text: 'See the best styles on your own face'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SFEntrance(
          index: 1,
          child: Text(
            'For the best result',
            style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ),
        const SizedBox(height: 8),
        const SFEntrance(
          index: 2,
          child: _Tip(icon: Icons.wb_sunny_outlined, text: 'Face a window or a lamp: even light, no strong shadows.'),
        ),
        const SFEntrance(
          index: 3,
          child: _Tip(icon: Icons.face_rounded, text: 'Look straight at the camera with your head level.'),
        ),
        const SFEntrance(
          index: 4,
          child: _Tip(
            icon: Icons.content_cut_rounded,
            text: 'Leave your hair as it is: SmartFit replaces it with each style.',
          ),
        ),
        const SizedBox(height: 16),
        const SFEntrance(index: 5, child: _Choices()),
        const SizedBox(height: 24),
        SFEntrance(
          index: 5,
          child: SFButton(
            label: 'Open camera',
            icon: Icons.photo_camera_front_rounded,
            onPressed: () => _getPhoto(context, ref, camera: true),
          ),
        ),
        const SizedBox(height: 12),
        SFEntrance(
          index: 6,
          child: SFButton(
            label: 'Upload a photo',
            icon: Icons.photo_library_outlined,
            variant: SFButtonVariant.secondary,
            onPressed: () => _getPhoto(context, ref, camera: false),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Your photo is only used to make the previews. It isn't stored.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text});

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: cs.primary.withValues(alpha: 0.12),
            child: Text(
              '$number',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTextStyles.bodyMd.copyWith(color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.sf.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

// ── 2. analysing ─────────────────────────────────────────────────────────────

class _AnalysingView extends StatelessWidget {
  const _AnalysingView({this.photo});

  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photo != null)
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.cs.primary, width: 3),
                  image: DecorationImage(image: MemoryImage(photo!), fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 28),
            const SFLoader(label: 'Measuring your face shape and styling your hair…'),
            const SizedBox(height: 12),
            Text(
              'The first look can take up to a minute while the AI stylist warms up.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3. result ────────────────────────────────────────────────────────────────

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.state});

  final HairstyleState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.result!;
    final current = state.current!;
    final controller = ref.read(hairstyleControllerProvider.notifier);
    final cs = context.cs;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, _navSpace(context) + 32),
      children: [
        SFEntrance(index: 0, child: _FaceShapeCard(shape: result.faceShape)),
        const SizedBox(height: 10),
        SFEntrance(index: 0, child: _YourHairCard(result: result)),
        if (result.note.isNotEmpty) ...[
          const SizedBox(height: 10),
          NoticeBanner(message: result.note),
        ],
        const SizedBox(height: 16),
        SFEntrance(
          index: 1,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
                    child: Image.memory(
                      state.showOriginal ? result.original : current.image,
                      key: ValueKey(state.showOriginal ? 'original' : current.id),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      semanticLabel: state.showOriginal ? 'Your photo' : 'You with ${current.name}',
                    ),
                  ),
                  if (state.selected == 0 && !state.showOriginal)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: context.sf.brandGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Best match',
                          style: TextStyle(color: context.sf.onBrand, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Before')),
                          ButtonSegment(value: false, label: Text('After')),
                        ],
                        selected: {state.showOriginal},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => controller.toggleOriginal(s.first),
                        style: SegmentedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                          foregroundColor: Colors.white,
                          selectedBackgroundColor: Colors.white,
                          selectedForegroundColor: Colors.black,
                          side: const BorderSide(color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          current.name,
          style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 18, color: context.sf.accentText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(current.reason, style: AppTextStyles.bodyMd.copyWith(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${result.styles.length} styles for you',
          style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: result.styles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final thumb = _Thumb(
                preview: result.styles[i],
                selected: i == state.selected,
                best: i == 0,
                onTap: () => controller.select(i),
              );
              if (context.reduceMotion) return thumb;
              // each style pops in just after the one before it
              return thumb
                  .animate(delay: (60 * i + 120).ms)
                  .fadeIn(duration: 320.ms)
                  .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack);
            },
          ),
        ),
        const SizedBox(height: 18),
        const _Choices(),
        const SizedBox(height: 20),
        _SaveWithOutfit(preview: current, faceShape: result.faceShape),
        Row(
          children: [
            Expanded(child: _DownloadButton(preview: current)),
            const SizedBox(width: 12),
            Expanded(
              child: SFButton(
                label: 'New photo',
                icon: Icons.refresh_rounded,
                variant: SFButtonVariant.secondary,
                onPressed: controller.reset,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          result.isAi
              ? 'AI preview: your own hair redrawn in this style (HairFastGAN). Use it as a guide for your stylist.'
              : 'Quick 2D preview: a real hairstyle photo fitted to your face. Use it as a guide for your stylist.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// SFR-035: keep the hairstyle on show with the outfit it was chosen for, in the
/// wardrobe (the saved item keeps its try-on; an unsaved outfit is saved now).
class _SaveWithOutfit extends ConsumerWidget {
  const _SaveWithOutfit({required this.preview, required this.faceShape});

  final HairstylePreview preview;
  final String faceShape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outfit = ref.watch(hairstyleOutfitProvider);
    if (outfit == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SFButton(
        label: 'Save this hairstyle with ${outfit.title}',
        icon: Icons.bookmark_add_rounded,
        onPressed: () async {
          final hair = ChosenHairstyle(
            id: preview.id,
            name: preview.name,
            score: preview.score,
            faceShape: faceShape,
            thumbBase64: preview.thumbBase64,
          ).toWardrobeJson();
          final wardrobe = ref.read(wardrobeNotifierProvider.notifier);
          final attached = await wardrobe.attachHairstyle(outfit.key, hair);
          if (!attached) await wardrobe.saveProduct(outfit.withHairstyle(hair));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${preview.name} saved with ${outfit.title} in your wardrobe ✨')),
            );
          }
        },
      ),
    );
  }
}

/// What SmartFit measured about the user's own hair (spec §23.27).
class _YourHairCard extends StatelessWidget {
  const _YourHairCard({required this.result});

  final HairstyleResult result;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.content_cut_rounded, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your hair now', style: AppTextStyles.labelSm.copyWith(color: cs.onSurfaceVariant)),
                Text(result.hairSummary, style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _occasions = ['casual', 'office', 'eid', 'mehndi', 'nikah', 'wedding', 'party'];

/// Occasion + the user's own hair texture: both optional, both change the suggestions.
class _Choices extends ConsumerWidget {
  const _Choices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hairstyleControllerProvider);
    final controller = ref.read(hairstyleControllerProvider.notifier);
    final cs = context.cs;
    final busy = state.phase == HairstylePhase.analysing;
    String label(String s) => s[0].toUpperCase() + s.substring(1);
    final outfit = ref.watch(hairstyleOutfitProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (outfit != null) ...[
          // SFR-029: suggestions that go with the outfit chosen in the try-on
          InputChip(
            avatar: const Icon(Icons.checkroom_rounded, size: 18),
            label: Text('Matching your outfit: ${outfit.title}', overflow: TextOverflow.ellipsis),
            onDeleted: busy ? null : () => ref.read(hairstyleOutfitProvider.notifier).state = null,
            deleteButtonTooltipMessage: 'Not for this outfit',
          ),
          const SizedBox(height: 14),
        ],
        Text('Occasion (optional)', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in _occasions)
              ChoiceChip(
                label: Text(label(o)),
                selected: state.occasion == o,
                onSelected: busy ? null : (on) => controller.setOccasion(on ? o : null),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text('My hair is', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (value, text) in const [('straight', 'Straight'), ('wavy', 'Wavy'), (null, 'Not sure')])
              ChoiceChip(
                label: Text(text),
                selected: state.hairTexture == value,
                onSelected: busy ? null : (_) => controller.setHairTexture(value),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Styles you can wear with your own hair rank higher.',
          style: AppTextStyles.bodySm.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FaceShapeCard extends StatelessWidget {
  const _FaceShapeCard({required this.shape});

  final String shape;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.face_rounded, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your face shape', style: AppTextStyles.labelSm.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  shape,
                  style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
                if (kFaceShapeMeaning[shape] case final meaning?)
                  Text(meaning, style: AppTextStyles.bodySm.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.preview, required this.selected, required this.best, required this.onTap});

  final HairstylePreview preview;
  final bool selected;
  final bool best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: best ? '${preview.name}, best match' : preview.name,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.93,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: selected ? 98 : 90,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: selected ? context.sf.brandGradient : null,
            color: selected ? null : context.cs.outlineVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(preview.image, fit: BoxFit.cover, gaplessPlayback: true),
                if (best)
                  const Positioned(top: 4, right: 4, child: Icon(Icons.star_rounded, color: Colors.amber, size: 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({required this.preview});

  final HairstylePreview preview;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    String message;
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      await saveImageBytes(widget.preview.image, 'smartfit-hairstyle-$stamp');
      message = 'Saved to $savedImageLocation ✨';
    } on SaveImageException catch (e) {
      message = e.message;
    } catch (_) {
      message = "Couldn't save the image. Please try again.";
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return SFButton(
      label: 'Download',
      icon: Icons.download_rounded,
      variant: SFButtonVariant.outline,
      isLoading: _busy,
      onPressed: _save,
    );
  }
}

// ── error ────────────────────────────────────────────────────────────────────

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.state});

  final HairstyleState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final photoProblem = state.photoProblem;
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, _navSpace(context) + 32),
      children: [
        Icon(photoProblem ? Icons.no_photography_outlined : Icons.cloud_off_rounded, size: 56, color: cs.primary),
        const SizedBox(height: 16),
        Text(
          photoProblem ? "Let's retake that photo" : 'Something went wrong',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleLg.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          state.failure?.message ?? 'Please try again.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (!photoProblem && state.photo != null) ...[
          SFButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: () async {
              final uid = ref.read(currentUserProvider)?.id;
              final gender = uid == null ? null : ref.read(profileNotifierProvider(uid)).valueOrNull?.gender;
              await ref.read(hairstyleControllerProvider.notifier).analyse(state.photo!, gender: catalogGender(gender));
            },
          ),
          const SizedBox(height: 12),
        ],
        SFButton(
          label: 'Open camera',
          icon: Icons.photo_camera_front_rounded,
          variant: photoProblem ? SFButtonVariant.primary : SFButtonVariant.secondary,
          onPressed: () => _getPhoto(context, ref, camera: true),
        ),
        const SizedBox(height: 12),
        SFButton(
          label: 'Upload a photo',
          icon: Icons.photo_library_outlined,
          variant: SFButtonVariant.secondary,
          onPressed: () => _getPhoto(context, ref, camera: false),
        ),
      ],
    );
  }
}
