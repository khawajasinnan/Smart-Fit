import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:smartfit/core/widgets/pose_overlay_painter.dart';


class CameraPreviewDialog extends StatefulWidget {
  final bool showPoseOverlay;
  const CameraPreviewDialog({super.key, this.showPoseOverlay = false});

  @override
  State<CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<CameraPreviewDialog> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  int _selectedCameraIdx = 0;
  
  PoseDetector? _poseDetector;
  List<Pose> _detectedPoses = [];
  bool _isProcessingFrame = false;
  bool _bodyDetected = false;

  @override
  void initState() {
    super.initState();
    if (widget.showPoseOverlay) {
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );
    }
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Prefer front camera if available
        _selectedCameraIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        if (_selectedCameraIdx == -1) _selectedCameraIdx = 0;
        
        await _setupCameraController();
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _setupCameraController() async {
    if (_cameras.isEmpty) return;
    
    final camera = _cameras[_selectedCameraIdx];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        if (widget.showPoseOverlay && _controller != null) {
          _controller!.startImageStream(_processFrame);
        }
      }
    } catch (e) {
      debugPrint("Camera controller error: $e");
    }
  }
  
  static final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessingFrame || _poseDetector == null || !_isInitialized) return;
    _isProcessingFrame = true;

    try {
      if (_cameras.isEmpty || _selectedCameraIdx >= _cameras.length) return;
      final camera = _cameras[_selectedCameraIdx];
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) return;

      final poses = await _poseDetector!.processImage(inputImage);
      if (mounted) {
        setState(() {
          _detectedPoses = poses;
          _bodyDetected = poses.isNotEmpty;
        });
      }
    } catch (e) {
      // Gracefully catch any frame-level conversion or detection errors
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    try {
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;
      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        final deviceOrientation = _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp;
        var rotationCompensation = _orientations[deviceOrientation] ?? 0;
        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }
      rotation ??= InputImageRotationValue.fromRawValue(sensorOrientation);
      if (rotation == null) return null;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      final fallbackFormat = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;

      // Concatenate all plane bytes (crucial for multi-plane YUV_420_888 on Android)
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format ?? fallbackFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isTakingPicture) return;
    
    setState(() => _isInitialized = false);
    await _controller?.dispose();
    
    _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    await _setupCameraController();
  }

  Future<void> _takePicture() async {
    if (!_isInitialized || _controller == null || _controller!.value.isTakingPicture) {
      return;
    }
    // Stop pose detection stream before capturing
    if (widget.showPoseOverlay) {
      await _controller!.stopImageStream();
    }

    setState(() => _isTakingPicture = true);
    try {
      final XFile file = await _controller!.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      if (mounted) {
        Navigator.pop(context, bytes);
      }
    } catch (e) {
      debugPrint("Error taking picture: $e");
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  @override
  void dispose() {
    _poseDetector?.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.electricPurple),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Camera Preview
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
            
            if (widget.showPoseOverlay && _detectedPoses.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: PoseOverlayPainter(
                    poses: _detectedPoses,
                    imageSize: Size(
                      _controller!.value.previewSize!.height,
                      _controller!.value.previewSize!.width,
                    ),
                    rotation: InputImageRotation.rotation0deg,
                    isFrontCamera: _cameras[_selectedCameraIdx].lensDirection == CameraLensDirection.front,
                  ),
                ),
              ),

            // Body detection status indicator
            if (widget.showPoseOverlay)
              Positioned(
                bottom: 110,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _bodyDetected 
                        ? Colors.green.withValues(alpha: 0.8)
                        : Colors.orange.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _bodyDetected ? Icons.check_circle : Icons.person_search,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _bodyDetected ? 'Body Detected ✓' : 'Position yourself in frame...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Top Controls
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  ),
                  if (_cameras.length > 1)
                    IconButton(
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 28),
                      style: IconButton.styleFrom(backgroundColor: Colors.black45),
                    ),
                ],
              ),
            ),

            // Bottom Controls
            Positioned(
              bottom: 32,
              child: _isTakingPicture
                  ? const CircularProgressIndicator(color: AppColors.electricPurple)
                  : GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
