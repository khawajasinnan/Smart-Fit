import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:smartfit/core/constants/app_colors.dart';

class CameraPreviewDialog extends StatefulWidget {
  const CameraPreviewDialog({super.key});

  @override
  State<CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<CameraPreviewDialog> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  int _selectedCameraIdx = 0;

  @override
  void initState() {
    super.initState();
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
      }
    } catch (e) {
      debugPrint("Camera controller error: $e");
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
