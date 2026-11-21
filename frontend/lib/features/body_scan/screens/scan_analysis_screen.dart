import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/body_scan/widgets/scan_result_painter.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// "Analyzing" step after a scan photo: sends it to the CV service (MediaPipe
/// pose + face mesh, HRNet), animates while it runs, then draws both
/// skeletons, the face mesh and the measurement lines over the photo and
/// lists the results. Pops with a [BodyScanOutcome] (or null if closed).
class ScanAnalysisScreen extends ConsumerStatefulWidget {
  const ScanAnalysisScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  ConsumerState<ScanAnalysisScreen> createState() => _ScanAnalysisScreenState();
}

class _ScanAnalysisScreenState extends ConsumerState<ScanAnalysisScreen> with TickerProviderStateMixin {
  static const _steps = [
    ('Detecting 33 body landmarks', 'MediaPipe Pose'),
    ('Cross-checking joints', 'HRNet'),
    ('Measuring your shoulders', 'MediaPipe + HRNet'),
    ('Mapping 468 face points', 'MediaPipe Face Mesh'),
    ('Body type, skin tone & size', 'SmartFit analysis'),
  ];

  CvAnalysisResult? _result;
  String? _failure; // server unreachable / scan failed
  bool _loading = true;
  int _activeStep = 0;
  Timer? _stepTimer;
  double? _aspect; // photo width / height

  late final AnimationController _beam = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  // Created in initState: it is first used after the first frame, and a lazy
  // controller touched only in dispose() would be created mid-teardown.
  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _decodeAspect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _beam.stop();
    } else if (_loading && !_beam.isAnimating) {
      _beam.repeat();
    }
  }

  Future<void> _decodeAspect() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _aspect = frame.image.width / frame.image.height);
      frame.image.dispose();
    } catch (_) {
      if (mounted) setState(() => _aspect = 3 / 4);
    }
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _failure = null;
      _result = null;
      _activeStep = 0;
    });
    _reveal.value = 0;
    if (!MediaQuery.of(context).disableAnimations) _beam.repeat();
    // The steps are what the server runs; they tick along while it works and
    // are only marked done once it has answered.
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted || _activeStep >= _steps.length - 1) return t.cancel();
      setState(() => _activeStep++);
    });

    final user = ref.read(currentUserProvider);
    final profile = user == null ? null : ref.read(profileNotifierProvider(user.id)).valueOrNull;
    final result = await ref.read(cvAnalysisApiServiceProvider).analyzeBody(
          imageBase64: base64Encode(widget.bytes),
          profile: profile,
          detailed: true,
        );
    if (!mounted) return;
    _stepTimer?.cancel();
    _beam.stop();
    setState(() {
      _loading = false;
      _activeStep = _steps.length;
      if (result.success) {
        _result = result;
      } else {
        _failure = result.error ?? "The scan didn't work. Please try again.";
      }
    });
    if (result.success) {
      MediaQuery.of(context).disableAnimations ? _reveal.value = 1 : _reveal.forward();
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _beam.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _finish({required bool withAnalysis}) {
    Navigator.of(context).pop(BodyScanOutcome(bytes: widget.bytes, analysis: withAnalysis ? _result : null));
  }

  @override
  Widget build(BuildContext context) {
    final title = _loading ? 'Analyzing your scan' : (_failure != null ? 'Scan not finished' : 'Your scan results');
    return SFScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.gutter, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const SFLogoMark(size: 28),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.lg),
                children: [
                  _photo(),
                  if (_result != null) ...[const SizedBox(height: AppSpace.sm), const _Legend()],
                  const SizedBox(height: AppSpace.lg),
                  if (_failure != null)
                    NoticeBanner(tone: NoticeTone.error, title: "Couldn't analyze the photo", message: _failure!)
                  else if (_result == null)
                    _stepList()
                  else
                    _ResultsView(result: _result!),
                ],
              ),
            ),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _photo() {
    final aspect = _aspect;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.48;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: aspect == null
            ? SizedBox(height: maxHeight, child: const Center(child: SFLoader()))
            : AspectRatio(
                aspectRatio: aspect,
                child: ClipRRect(
                  borderRadius: AppRadius.lgAll,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                      if (_loading)
                        AnimatedBuilder(
                          animation: _beam,
                          builder: (_, _) => CustomPaint(painter: _BeamPainter(_beam.value)),
                        ),
                      if (_result != null)
                        AnimatedBuilder(
                          animation: _reveal,
                          builder: (_, _) => CustomPaint(
                            painter: ScanResultPainter(result: _result!, progress: _reveal.value),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _stepList() {
    return SFGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            _StepRow(
              title: _steps[i].$1,
              model: _steps[i].$2,
              state: i < _activeStep && !_loading
                  ? _StepState.done
                  : (i <= _activeStep ? _StepState.running : _StepState.waiting),
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    final done = !_loading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.md),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _failure != null
                ? SFButton(
                    label: 'Photo only',
                    icon: Icons.image_outlined,
                    variant: SFButtonVariant.outline,
                    onPressed: () => _finish(withAnalysis: false),
                  )
                : SFButton(
                    label: 'Retake',
                    icon: Icons.camera_alt_outlined,
                    variant: SFButtonVariant.outline,
                    onPressed: () => Navigator.of(context).pop(const BodyScanOutcome.retake()),
                  ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 3,
            child: _failure != null
                ? SFButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _run)
                : SFButton(
                    label: 'Send to stylist',
                    icon: Icons.auto_awesome_rounded,
                    isLoading: !done,
                    onPressed: done ? () => _finish(withAnalysis: true) : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A light band sweeping down the photo while the server works.
class _BeamPainter extends CustomPainter {
  _BeamPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (t < 0.5 ? t * 2 : 2 - t * 2);
    final band = Rect.fromLTWH(0, y - 60, size.width, 120);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.primary600.withValues(alpha: 0.28),
            Colors.transparent,
          ],
        ).createShader(band),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 2
        ..color = kBrandLime,
    );
    // faint grid: "measuring"
    final grid = Paint()
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.12);
    for (var gx = size.width / 6; gx < size.width; gx += size.width / 6) {
      canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), grid);
    }
    for (var gy = size.height / 8; gy < size.height; gy += size.height / 8) {
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.t != t;
}

enum _StepState { waiting, running, done }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.title, required this.model, required this.state});

  final String title;
  final String model;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: switch (state) {
              _StepState.done => const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
              _StepState.running => const Center(child: SFLoader.small()),
              _StepState.waiting => Icon(Icons.radio_button_unchecked_rounded, color: sf.textMuted, size: 20),
            },
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: state == _StepState.waiting ? sf.textMuted : sf.ink,
                  ),
                ),
                Text(model, style: tt.labelSmall?.copyWith(color: sf.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpace.md,
      runSpacing: AppSpace.xxs,
      children: [
        item(kMediaPipeColor, 'MediaPipe'),
        item(kHrnetColor, 'HRNet'),
        item(kFaceMeshColor, 'Face mesh'),
        item(kBrandLime, 'Measurements'),
      ],
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.result});

  final CvAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final s = ScanSummary.fromResult(result);
    final agreement = result.modelAgreement;
    final face = result.face;
    final tt = Theme.of(context).textTheme;
    final sf = context.sf;
    final tiles = [
      _ResultTile(icon: Icons.accessibility_new_rounded, label: 'Body shape', value: s.bodyShape ?? 'Not measured'),
      _ResultTile(icon: Icons.straighten_rounded, label: 'Shoulders', value: s.shoulderText ?? 'Not measured'),
      _ResultTile(
        icon: Icons.face_retouching_natural_rounded,
        label: 'Face shape',
        value: s.faceShape ?? 'Not measured',
        caption: face?.note,
      ),
      _ResultTile(
        icon: Icons.palette_outlined,
        label: 'Skin tone',
        value: s.skinTone ?? 'Not measured',
        swatch: _hex(s.skinHex),
      ),
      if (s.size != null) _ResultTile(icon: Icons.checkroom_rounded, label: 'Estimated size', value: s.size!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.error != null) ...[
          NoticeBanner(tone: NoticeTone.info, title: 'Partly measured', message: result.error!),
          const SizedBox(height: AppSpace.md),
        ],
        for (var i = 0; i < tiles.length; i++) SFEntrance(index: i, child: tiles[i]),
        if (agreement != null)
          SFEntrance(
            index: tiles.length,
            child: _ResultTile(
              icon: Icons.compare_arrows_rounded,
              label: 'MediaPipe vs HRNet',
              value: '${agreement.agreement} agreement',
              caption: 'Matching joints are ${agreement.meanOffsetPct.toStringAsFixed(0)}% of your shoulder width '
                  'apart (${agreement.comparedPoints} joints).',
            ),
          ),
        const SizedBox(height: AppSpace.sm),
        Text(
          [
            if (result.modelsUsed.isNotEmpty) result.modelsUsed.join(' · '),
            if (result.processingTimeMs != null) '${(result.processingTimeMs! / 1000).toStringAsFixed(1)} s',
          ].join('  ·  '),
          textAlign: TextAlign.center,
          style: tt.labelSmall?.copyWith(color: sf.textMuted),
        ),
      ],
    );
  }

  static Color? _hex(String? hex) {
    if (hex == null || !RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(int.parse(hex.replaceFirst('#', ''), radix: 16) | 0xFF000000);
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.icon, required this.label, required this.value, this.caption, this.swatch});

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: SFGlassCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch ?? AppColors.primary600.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: swatch == null
                  ? Icon(icon, color: context.sf.highlight, size: 22)
                  : null,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: tt.labelMedium?.copyWith(color: sf.textMuted)),
                  Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (caption != null && caption!.isNotEmpty)
                    Text(caption!, style: tt.bodySmall?.copyWith(color: sf.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
