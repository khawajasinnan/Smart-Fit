import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/profile/data/services/skin_tone_api_service.dart';
import 'package:smartfit/features/profile/widgets/settings_widgets.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// What the user chose on the analyzer: one of the app's skin swatches and an undertone.
class SkinToneChoice {
  const SkinToneChoice(this.skinTone, this.undertone);

  final String skinTone;
  final String? undertone; // warm | cool | neutral
}

/// Skin tone analyzer (21 Nov 2026, the user's request: "analyze the skin tone of the user
/// closely and suggest them according to their things"). A face photo gives the skin's
/// depth (Monk 10-shade scale and the app's six swatches) and a first reading of the
/// undertone; two standard questions confirm the undertone; the advice (best colours, what
/// to keep away from the face, which white, gold or silver, outfit ideas) follows the
/// result. Opened from onboarding and from Profile; returns a [SkinToneChoice].
class SkinToneAnalyzerScreen extends ConsumerStatefulWidget {
  const SkinToneAnalyzerScreen({super.key, this.profilePhotoUrl, this.profilePhotoBytes});

  /// The user's profile photo, offered as "Use my profile photo" when there is one: the
  /// saved photo's address, or the one just picked in onboarding (not uploaded yet).
  final String? profilePhotoUrl;
  final Uint8List? profilePhotoBytes;

  bool get hasProfilePhoto => profilePhotoBytes != null || (profilePhotoUrl ?? '').trim().isNotEmpty;

  @override
  ConsumerState<SkinToneAnalyzerScreen> createState() => _SkinToneAnalyzerScreenState();
}

class _SkinToneAnalyzerScreenState extends ConsumerState<SkinToneAnalyzerScreen> {
  bool _busy = false;
  String? _error;
  SkinAnalysis? _analysis;
  SkinPalette? _palette;
  String? _veins; // the two questions' answers: warm | cool | neutral
  String? _metal;

  /// The photo's reading until the questions are answered, then the vote of all three.
  String? get _undertone {
    final a = _analysis;
    if (a == null) return null;
    if (_veins == null && _metal == null) return a.undertone;
    return combineUndertone(photo: a.undertone, photoSure: a.undertoneSure, veins: _veins, metal: _metal);
  }

  Future<void> _fromPicker(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1400,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.front,
    );
    final bytes = await file?.readAsBytes();
    if (bytes == null || !mounted) return;
    await _analyze(() => ref.read(skinToneApiServiceProvider).analyze(imageBase64: base64Encode(bytes)));
  }

  Future<void> _fromProfilePhoto() => _analyze(() {
    final api = ref.read(skinToneApiServiceProvider);
    final bytes = widget.profilePhotoBytes;
    return bytes != null
        ? api.analyze(imageBase64: base64Encode(bytes))
        : api.analyze(imageUrl: widget.profilePhotoUrl);
  });

  Future<void> _analyze(Future<SkinAnalysis> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final analysis = await call();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _analysis = analysis;
        _palette = analysis.palette;
        _veins = null;
        _metal = null;
        _busy = false;
      });
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't analyse that photo. Please try again.";
        });
      }
    }
  }

  /// An answer changed: refresh the advice when the undertone it gives changed.
  Future<void> _answer(void Function() change) async {
    final before = _undertone;
    setState(change);
    final after = _undertone;
    if (after == before || _analysis == null) return;
    try {
      final palette = await ref.read(skinToneApiServiceProvider).palette(_analysis!.skinTone, after);
      if (mounted) setState(() => _palette = palette);
    } catch (_) {
      // keep the advice on screen; the saved undertone is still the new one
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return SFScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxxl),
        children: [
          const SettingsPageHeader(title: 'Skin tone analyzer', subtitle: 'Your shade, undertone and best colours'),
          if (_error != null) ...[
            NoticeBanner(tone: NoticeTone.error, message: _error!, onClose: () => setState(() => _error = null)),
            const SizedBox(height: AppSpace.md),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xxl),
              child: Center(child: SFLoader(label: 'Reading your skin tone…')),
            )
          else if (analysis == null)
            _intro(context)
          else ...[
            _shadeCard(context, analysis),
            const SizedBox(height: AppSpace.md),
            _undertoneCard(context, analysis),
            if (_palette != null) ...[const SizedBox(height: AppSpace.md), _adviceCard(context, _palette!)],
            const SizedBox(height: AppSpace.lg),
            SFButton(
              label: 'Use these results',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(SkinToneChoice(analysis.skinTone, _undertone)),
            ),
            const SizedBox(height: AppSpace.sm),
            SFButton(
              label: 'Try another photo',
              variant: SFButtonVariant.outline,
              onPressed: () => setState(() => _analysis = null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return SFGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('A clear photo of your face', style: context.tt.titleMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Face a window in daylight, no filters or make-up base if you can, and nothing on your face. '
            'A white or grey wall behind you helps us correct the light.',
            style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted),
          ),
          const SizedBox(height: AppSpace.lg),
          SFButton(
            label: 'Take a selfie',
            icon: Icons.photo_camera_front_rounded,
            onPressed: () => _fromPicker(ImageSource.camera),
          ),
          const SizedBox(height: AppSpace.sm),
          SFButton(
            label: 'Choose a photo',
            icon: Icons.photo_library_outlined,
            variant: SFButtonVariant.outline,
            onPressed: () => _fromPicker(ImageSource.gallery),
          ),
          if (widget.hasProfilePhoto) ...[
            const SizedBox(height: AppSpace.sm),
            SFButton(
              label: 'Use my profile photo',
              icon: Icons.account_circle_outlined,
              variant: SFButtonVariant.outline,
              onPressed: _fromProfilePhoto,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(
            'Your photo is only used for this reading; it is not saved.',
            style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _shadeCard(BuildContext context, SkinAnalysis a) {
    return SFGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(hex: a.measuredHex, size: 56),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.skinTone, style: context.tt.headlineSmall),
                    Text('Shade ${a.monkLevel} of 10 on the Monk skin tone scale', style: context.tt.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            label: 'Monk scale, your shade is ${a.monkLevel} of 10',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 0; i < monkScaleHex.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _Dot(hex: monkScaleHex[i], size: 24, ringed: i + 1 == a.monkLevel),
                    ),
                  ),
              ],
            ),
          ),
          if (a.note.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(a.note, style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _undertoneCard(BuildContext context, SkinAnalysis a) {
    final tone = _undertone ?? a.undertone;
    final answered = _veins != null || _metal != null;
    return SFGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_undertoneTitle(tone, answered || a.undertoneSure), style: context.tt.titleMedium),
          Text(
            answered ? 'From your photo and your answers' : 'From your photo. Two quick questions make it sure:',
            style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          _Question(
            question: 'In daylight, the veins on your inner wrist look…',
            options: const [('Greenish', 'warm'), ('Blue or purple', 'cool'), ('Hard to tell', 'neutral')],
            value: _veins,
            onChanged: (v) => _answer(() => _veins = v),
          ),
          const SizedBox(height: AppSpace.sm),
          _Question(
            question: 'Which jewellery makes your skin glow?',
            options: const [('Gold', 'warm'), ('Silver', 'cool'), ('Both', 'neutral')],
            value: _metal,
            onChanged: (v) => _answer(() => _metal = v),
          ),
        ],
      ),
    );
  }

  Widget _adviceCard(BuildContext context, SkinPalette p) {
    return SFGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your colours', style: context.tt.titleMedium),
          const SizedBox(height: AppSpace.xxs),
          Text(p.summary, style: context.tt.bodyMedium),
          const SizedBox(height: AppSpace.md),
          Text('Colours that flatter you', style: context.tt.labelLarge),
          const SizedBox(height: AppSpace.xs),
          _ColourChips(colours: p.best),
          if (p.avoid.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('Keep away from your face', style: context.tt.labelLarge),
            const SizedBox(height: AppSpace.xs),
            _ColourChips(colours: p.avoid),
          ],
          const SizedBox(height: AppSpace.md),
          _Fact(icon: Icons.brightness_7_outlined, label: 'Your white', text: p.white),
          _Fact(icon: Icons.diamond_outlined, label: 'Jewellery and embroidery', text: p.metal),
          const SizedBox(height: AppSpace.sm),
          Text('Outfit ideas', style: context.tt.labelLarge),
          const SizedBox(height: AppSpace.xxs),
          for (final idea in p.outfits)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: context.cs.primary),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(idea, style: context.tt.bodyMedium)),
                ],
              ),
            ),
          if (p.avoidTip.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(p.avoidTip, style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// "Undertone: Warm", or "Undertone: Likely warm" while it rests on an unsure photo alone.
String _undertoneTitle(String tone, bool sure) =>
    sure ? 'Undertone: ${tone[0].toUpperCase()}${tone.substring(1)}' : 'Undertone: Likely $tone';

Color _color(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

class _Dot extends StatelessWidget {
  const _Dot({required this.hex, required this.size, this.ringed = false});

  final String hex;
  final double size;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: _color(hex),
        shape: BoxShape.circle,
        border: Border.all(color: ringed ? context.cs.primary : context.sf.divider, width: ringed ? 3 : 1),
      ),
    );
  }
}

class _ColourChips extends StatelessWidget {
  const _ColourChips({required this.colours});

  final List<SkinColour> colours;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        for (final c in colours)
          Chip(
            avatar: _Dot(hex: c.hex, size: 16),
            label: Text(c.name[0].toUpperCase() + c.name.substring(1)),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.cs.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: context.tt.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.question, required this.options, required this.value, required this.onChanged});

  final String question;
  final List<(String, String)> options; // (label, undertone)
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question, style: context.tt.bodyMedium),
        const SizedBox(height: AppSpace.xxs),
        Wrap(
          spacing: AppSpace.xs,
          children: [
            for (final (label, tone) in options)
              ChoiceChip(label: Text(label), selected: value == tone, onSelected: (_) => onChanged(tone)),
          ],
        ),
      ],
    );
  }
}
