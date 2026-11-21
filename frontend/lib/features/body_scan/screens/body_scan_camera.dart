import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/features/body_scan/widgets/live_scan_painter.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';

/// Full-screen camera with a live body + face scan overlay.
///
/// ML Kit runs on-device on the preview frames: Pose Detection (MediaPipe's
/// BlazePose model) draws the skeleton and shoulder line, Face Detection
/// draws the face contours. Pops with the captured JPEG bytes, or null.
///
/// ML Kit only exists on Android and iOS: in a browser (flutter run -d chrome)
/// the camera and capture still work, without the live overlay; the photo is
/// still analysed by the backend afterwards. No dart:io here (it throws on web).
///
/// Open with `showDialog<Uint8List>(builder: (_) => const BodyScanCamera())`.
class BodyScanCamera extends StatefulWidget {
  const BodyScanCamera({super.key, this.title = 'Body & face scan'});

  final String title;

  @override
  State<BodyScanCamera> createState() => _BodyScanCameraState();
}

class _BodyScanCameraState extends State<BodyScanCamera> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _fatalError; // camera can't be used at all
  String? _captureError; // last capture failed; the user can try again
  bool _capturing = false;

  /// On-device tracking is available (Android / iOS app, not the browser).
  static final bool _liveTracking = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  final PoseDetector? _poseDetector = _liveTracking
      ? PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base))
      : null;
  final FaceDetector? _faceDetector = _liveTracking
      ? FaceDetector(
          options: FaceDetectorOptions(enableContours: true, performanceMode: FaceDetectorMode.fast, minFaceSize: 0.12),
        )
      : null;
  bool _busy = false;
  int _frame = 0;
  List<Pose> _poses = const [];
  List<Face> _faces = const [];
  Size _imageSize = Size.zero;

  // Created in initState, not lazily: a lazy controller first touched in
  // dispose() would be created while the screen is being torn down.
  late final AnimationController _pulse;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool get _ready => _controller?.value.isInitialized ?? false;
  bool get _frontCamera =>
      _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) _pulse.stop();
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
      setState(() => _fatalError = 'No camera found on this device.');
      return;
    }
    final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _cameraIndex = front == -1 ? 0 : front;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      // ML Kit only accepts NV21 (Android) / BGRA8888 (iOS) frames.
      imageFormatGroup: !_liveTracking ? null : (_android ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      if (_liveTracking) await controller.startImageStream(_onFrame);
      setState(() {});
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    final code = e is CameraException ? e.code : '';
    debugPrint('[BodyScanCamera] camera failed: ${e is CameraException ? '$code: ${e.description}' : e}');
    if (!mounted) return;
    final lower = code.toLowerCase();
    final denied = lower.contains('denied') || lower.contains('restricted') || lower.contains('notallowed');
    setState(() => _fatalError = denied
        ? (kIsWeb
            ? 'SmartFit needs camera access. Allow the camera for this site in your browser, then try again.'
            : 'SmartFit needs camera access. Allow it in your phone settings, then try again.')
        : "The camera couldn't start. Close other apps using the camera and try again.");
  }

  Future<void> _onFrame(CameraImage image) async {
    final poseDetector = _poseDetector, faceDetector = _faceDetector;
    if (_busy || _capturing || !mounted || poseDetector == null || faceDetector == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      // Pose every frame, face every other frame: keeps the overlay smooth on mid-range phones.
      final poses = await poseDetector.processImage(input);
      final faces = (_frame++).isEven ? await faceDetector.processImage(input) : _faces;
      final rotated = input.metadata!.rotation == InputImageRotation.rotation90deg ||
          input.metadata!.rotation == InputImageRotation.rotation270deg;
      if (!mounted) return;
      setState(() {
        _poses = poses;
        _faces = faces;
        _imageSize = rotated ? Size(image.height.toDouble(), image.width.toDouble()) : Size(
            image.width.toDouble(), image.height.toDouble());
      });
    } catch (e) {
      debugPrint('[BodyScanCamera] frame skipped: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _cameras[_cameraIndex];
    InputImageRotation? rotation;
    if (!_android) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else {
      var compensation = _orientations[_controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp] ?? 0;
      compensation = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + compensation) % 360
          : (camera.sensorOrientation - compensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(compensation);
    }
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) return null;
    if (format != (_android ? InputImageFormat.nv21 : InputImageFormat.bgra8888)) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _poses = const [];
      _faces = const [];
    });
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing || c.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _capturing = true;
      _captureError = null;
    });
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream().timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      final file = await c.takePicture().timeout(const Duration(seconds: 10));
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      debugPrint('[BodyScanCamera] capture failed: $e');
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _captureError = "Couldn't take the photo. Hold still and tap again.";
      });
      if (_liveTracking && !c.value.isStreamingImages) {
        try {
          await c.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    final c = _controller;
    _controller = null;
    c?.dispose();
    _poseDetector?.close();
    _faceDetector?.close();
    super.dispose();
  }

  // ── Live checks shown as chips ──

  List<(_Check, String)> _checks() {
    if (!_liveTracking) {
      return const [(_Check.info, 'Live tracking runs in the phone app. Your photo is still analyzed.')];
    }
    final pose = _poses.isEmpty ? null : _poses.first;
    final tilt = pose == null ? null : shoulderTiltDeg(pose);
    final face = _faces.isEmpty ? null : _faces.first;
    final turn = face?.headEulerAngleY?.abs();
    return [
      if (pose == null) (_Check.waiting, 'Finding your body…') else (_Check.ok, 'Body tracked'),
      if (tilt == null)
        (_Check.waiting, 'Show both shoulders')
      else if (tilt.abs() < 3)
        (_Check.ok, 'Shoulders level')
      else
        (_Check.info, 'Shoulders tilted ${tilt.abs().toStringAsFixed(0)}°'),
      if (face == null)
        (_Check.waiting, 'Finding your face…')
      else if (turn != null && turn > 15)
        (_Check.info, 'Look at the camera')
      else
        (_Check.ok, 'Face mapped'),
    ];
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
    final previewSize = c.value.previewSize;
    if (previewSize == null) return CameraPreview(c);
    // Phone in portrait: the preview is previewSize rotated (a browser webcam
    // isn't). Overlay and preview share one box, so they stay aligned however
    // the box is scaled to the screen.
    final box = kIsWeb ? previewSize : Size(previewSize.height, previewSize.width);
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
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => CustomPaint(
                  painter: LiveScanPainter(
                    poses: _poses,
                    faces: _faces,
                    imageSize: _imageSize,
                    mirror: _frontCamera,
                    pulse: _pulse.value,
                  ),
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
              Text(
                widget.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
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
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final (state, text) in _checks()) _CheckChip(state: state, text: text)],
                ),
                if (_captureError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _captureError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFFB4C8), fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 18),
                Semantics(
                  button: true,
                  label: 'Take photo',
                  child: GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: _capturing
                          ? const SFLoader.small(color: Colors.white)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [AppColors.primary600, AppColors.accent600]),
                              ),
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

enum _Check { ok, info, waiting }

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.state, required this.text});

  final _Check state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      _Check.ok => (Icons.check_circle_rounded, kBrandLime),
      _Check.info => (Icons.info_rounded, const Color(0xFFFFC857)),
      _Check.waiting => (Icons.radar_rounded, Colors.white70),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
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
