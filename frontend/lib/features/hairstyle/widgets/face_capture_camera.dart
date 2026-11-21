import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_api_service.dart';
import 'package:smartfit/features/hairstyle/data/hairstyle_models.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';

/// Ready frames needed in a row before the photo is taken (the user is still).
const kReadyFramesNeeded = 2;

/// Counts "ready" answers in a row; true once the photo should be taken.
class AutoCapture {
  AutoCapture({this.needed = kReadyFramesNeeded});

  final int needed;
  int streak = 0;

  bool add(FaceCheck check) {
    streak = check.ready ? streak + 1 : 0;
    return streak >= needed;
  }
}

/// The guide circle in a [box] of the frame's size (what the painter draws).
Rect guideRect(Size box, GuideCircle c) =>
    Rect.fromCircle(center: Offset(c.cx * box.width, c.cy * box.height), radius: c.r * box.width);

/// Full-screen front camera with a head-shaped guide circle (SFR-029).
///
/// About twice a second a silent snapshot of the preview goes to the server,
/// which checks it with MediaPipe + dlib (face inside the circle, straight,
/// sharp, well lit) and answers with a hint. After [kReadyFramesNeeded] good
/// frames in a row, that frame is the photo: the camera closes and pops its
/// JPEG bytes. A manual button stays as a fallback. Pops null when closed.
///
/// Open with `showDialog<Uint8List>(builder: (_) => const FaceCaptureCamera())`.
class FaceCaptureCamera extends ConsumerStatefulWidget {
  const FaceCaptureCamera({super.key});

  @override
  ConsumerState<FaceCaptureCamera> createState() => _FaceCaptureCameraState();
}

class _FaceCaptureCameraState extends ConsumerState<FaceCaptureCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _fatalError;
  bool _done = false;
  bool _looping = false;
  final _auto = AutoCapture();
  FaceCheck? _last;
  String? _connection; // a problem reaching the server, shown instead of the hint
  int _failures = 0;

  bool get _ready => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      _fail(e);
      return;
    }
    if (_cameras.isEmpty) {
      if (mounted) setState(() => _fatalError = 'No camera found on this device.');
      return;
    }
    final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _cameraIndex = front == -1 ? 0 : front;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final controller = CameraController(_cameras[_cameraIndex], ResolutionPreset.veryHigh, enableAudio: false);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      unawaited(_loop());
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    final code = e is CameraException ? e.code : '';
    debugPrint('[FaceCaptureCamera] camera failed: ${e is CameraException ? '$code: ${e.description}' : e}');
    if (!mounted) return;
    final lower = code.toLowerCase();
    final denied = lower.contains('denied') || lower.contains('restricted') || lower.contains('notallowed');
    setState(() => _fatalError = denied
        ? (kIsWeb
            ? 'SmartFit needs camera access. Allow the camera for this site in your browser, then try again.'
            : 'SmartFit needs camera access. Allow it in your phone settings, then try again.')
        : "The camera couldn't start. Close other apps using the camera and try again.");
  }

  /// The frame's size the way it's shown (a phone's preview is rotated to portrait).
  Size? _box() {
    final size = _controller?.value.previewSize;
    if (size == null) return null;
    return kIsWeb ? size : Size(size.height, size.width);
  }

  Future<void> _loop() async {
    if (_looping) return;
    _looping = true;
    final api = ref.read(hairstyleApiServiceProvider);
    try {
      while (mounted && !_done) {
        final c = _controller, box = _box();
        if (c == null || box == null || !c.value.isInitialized || c.value.isTakingPicture) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        Uint8List frame;
        try {
          frame = await (await c.takePicture().timeout(const Duration(seconds: 8))).readAsBytes();
        } catch (e) {
          debugPrint('[FaceCaptureCamera] frame skipped: $e');
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        if (!mounted || _done) return;
        try {
          final check = await api.checkFrame(frame, GuideCircle.forFrame(box.width, box.height));
          if (!mounted || _done) return;
          _failures = 0;
          final take = _auto.add(check);
          setState(() {
            _last = check;
            _connection = null;
          });
          if (take) {
            _finish(frame);
            return;
          }
        } on Failure catch (f) {
          if (!mounted || _done) return;
          _failures++;
          _auto.streak = 0;
          setState(() => _connection = f is RateLimitedFailure
              ? 'Checking a bit slower…'
              : "Can't check the picture right now. You can take it yourself.");
          await Future<void>.delayed(Duration(milliseconds: 500 * math.min(_failures, 6)));
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _looping = false;
    }
  }

  void _finish(Uint8List photo) {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop<Uint8List>(photo);
  }

  Future<void> _takeNow() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _done) return;
    try {
      // a snapshot may be in flight: wait for it, then take ours
      for (var i = 0; i < 20 && c.value.isTakingPicture; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final photo = await (await c.takePicture().timeout(const Duration(seconds: 10))).readAsBytes();
      if (mounted) _finish(photo);
    } catch (e) {
      debugPrint('[FaceCaptureCamera] capture failed: $e');
      if (mounted) setState(() => _connection = "Couldn't take the photo. Hold still and try again.");
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _done) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _last = null;
      _auto.streak = 0;
    });
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera();
  }

  @override
  void dispose() {
    _done = true;
    WidgetsBinding.instance.removeObserver(this);
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_fatalError != null)
            _CameraMessage(message: _fatalError!)
          else if (!_ready)
            const Center(child: SFLoader(label: 'Starting camera…'))
          else
            _preview(),
          _topBar(),
          if (_fatalError == null && _ready) _bottomPanel(),
        ],
      ),
    );
  }

  Widget _preview() {
    final c = _controller!;
    final box = _box();
    if (box == null) return CameraPreview(c);
    final state = _last == null
        ? GuideState.searching
        : (_last!.ready ? GuideState.ready : GuideState.adjust);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(c),
              CustomPaint(
                painter: GuidePainter(
                  circle: GuideCircle.forFrame(box.width, box.height),
                  state: state,
                  progress: _auto.streak / kReadyFramesNeeded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
              const Spacer(),
              const SFLogoMark(size: 26),
              const SizedBox(width: 8),
              const Text('Face photo',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              if (_cameras.length > 1 && _fatalError == null)
                IconButton(
                  tooltip: 'Switch camera',
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 26),
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    final hint = _connection ?? _last?.message ?? 'Put your face inside the circle.';
    final ready = _connection == null && (_last?.ready ?? false);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: (ready ? kBrandLime : const Color(0xFFFFC857)).withValues(alpha: 0.8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ready ? Icons.check_circle_rounded : Icons.face_retouching_natural_rounded,
                            size: 18, color: ready ? kBrandLime : const Color(0xFFFFC857)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The photo is taken automatically when everything looks good.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: 'Take the photo now',
                  child: GestureDetector(
                    onTap: _takeNow,
                    child: Container(
                      width: 66,
                      height: 66,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                        child: Icon(Icons.camera_alt_rounded, color: Colors.white),
                      ),
                    ),
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

enum GuideState { searching, adjust, ready }

/// Darkens everything outside the guide circle and rings it: white while
/// searching, amber while the user adjusts, green (with progress) when ready.
class GuidePainter extends CustomPainter {
  GuidePainter({required this.circle, required this.state, required this.progress});

  final GuideCircle circle;
  final GuideState state;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = guideRect(size, circle);
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(rect);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    final colour = switch (state) {
      GuideState.searching => Colors.white,
      GuideState.adjust => const Color(0xFFFFC857),
      GuideState.ready => kBrandLime,
    };
    final width = size.shortestSide * 0.012;
    canvas.drawOval(rect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = colour.withValues(alpha: state == GuideState.searching ? 0.7 : 1));
    if (state == GuideState.ready && progress > 0) {
      canvas.drawArc(
        rect.inflate(width * 2),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 1.6
          ..color = kBrandLime,
      );
    }
  }

  @override
  bool shouldRepaint(GuidePainter old) => old.state != state || old.progress != progress || old.circle != circle;
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
