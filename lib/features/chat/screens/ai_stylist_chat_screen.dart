import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/widgets/camera_preview_dialog.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/chat/providers/chat_provider.dart';

class AiStylistChatScreen extends ConsumerStatefulWidget {
  const AiStylistChatScreen({super.key});
  @override
  ConsumerState<AiStylistChatScreen> createState() =>
      _AiStylistChatScreenState();
}

class _AiStylistChatScreenState extends ConsumerState<AiStylistChatScreen>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final List<_PickedChatImage> _pendingImages = [];
  bool _initialized = false;
  bool _isListening = false;
  bool _speechReady = false;
  late AnimationController _quoteCtrl;
  late Animation<double> _quoteFade;

  @override
  void initState() {
    super.initState();
    _quoteCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _quoteFade = CurvedAnimation(parent: _quoteCtrl, curve: Curves.easeIn);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _quoteCtrl.forward();
    });
    _initSpeech();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _quoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice input stopped: ${error.errorMsg}')),
          );
        },
      );
      if (mounted) setState(() => _speechReady = ready);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    final images = _pendingImages
        .map(
          (image) => PendingChatImage(
            bytes: image.bytes,
            extension: image.extension,
            mimeType: image.mimeType,
          ),
        )
        .toList();
    _controller.clear();
    setState(() => _pendingImages.clear());
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref
        .read(chatNotifierProvider(user.id).notifier)
        .sendMessage(text, images: images);
    _scrollToBottom();
  }

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.secondaryContainer,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    if (source == ImageSource.camera) {
      await _takeLivePhoto();
    } else {
      await _pickImagesFromGallery();
    }
  }

  Future<void> _takeLivePhoto() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CameraPreviewDialog(),
    );
    if (bytes == null) return;
    if (mounted) {
      setState(
        () => _pendingImages.add(
          _PickedChatImage(
            bytes: bytes,
            extension: 'jpg',
            mimeType: 'image/jpeg',
          ),
        ),
      );
    }
  }

  Future<void> _pickImagesFromGallery() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1400,
      imageQuality: 82,
    );
    if (files.isEmpty) return;
    final selected = <_PickedChatImage>[];
    for (final file in files.take(4)) {
      final bytes = await file.readAsBytes();
      final extension = _extensionFromName(file.name);
      selected.add(
        _PickedChatImage(
          bytes: bytes,
          extension: extension,
          mimeType: _mimeTypeForExtension(extension),
        ),
      );
    }
    if (mounted) setState(() => _pendingImages.addAll(selected));
  }

  Future<void> _toggleVoice() async {
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is not available on this device yet.'),
          ),
        );
        return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 4),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        if (result.finalResult && mounted) setState(() => _isListening = false);
      },
    );
  }

  void _showHistory(ChatNotifier chatNotifier) {
    chatNotifier.loadSessions();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final user = ref.watch(currentUserProvider);
          if (user == null) return const SizedBox.shrink();
          final notifier = ref.read(chatNotifierProvider(user.id).notifier);
          ref.watch(chatNotifierProvider(user.id));
          final sessions = notifier.sessions;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Past Style Chats',
                        style: AppTextStyles.headlineMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          notifier.startSession(fresh: true);
                        },
                        icon: const Icon(
                          Icons.add_comment_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (notifier.isLoadingSessions)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No past chats yet.',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final session = sessions[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.primaryContainer,
                              child: Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              session.title ?? 'Style Session',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              DateFormat(
                                'MMM d, h:mm a',
                              ).format(session.updatedAt),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              notifier.loadSession(session.id);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _extensionFromName(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'jpg';
    return parts.last.toLowerCase();
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final messages = ref.watch(chatNotifierProvider(user.id));
    final chatNotifier = ref.read(chatNotifierProvider(user.id).notifier);
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatNotifier.startSession(),
      );
    }
    _scrollToBottom();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient orbs per design.md Screen 12
          Positioned(
            top: 100,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondaryFixedDim.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go(RoutePaths.home),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer.withValues(
                              alpha: 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: AppColors.onSurface,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryContainer.withValues(
                            alpha: 0.2,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: AppColors.secondaryContainer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Stylist',
                        style: AppTextStyles.headlineMd.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'History',
                        icon: const Icon(
                          Icons.history_rounded,
                          color: AppColors.primary,
                        ),
                        onPressed: () => _showHistory(chatNotifier),
                      ),
                      IconButton(
                        tooltip: 'New chat',
                        icon: const Icon(
                          Icons.add_comment_rounded,
                          color: AppColors.primary,
                        ),
                        onPressed: () => chatNotifier.startSession(fresh: true),
                      ),
                    ],
                  ),
                ),
              ),

              // Chat area
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: 120,
                  ),
                  itemCount: messages.isEmpty
                      ? 5
                      : messages.length + (chatNotifier.isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (messages.isEmpty) {
                      if (index == 0) {
                        return _quoteBlock();
                      }
                      if (index == 1) {
                        return _userBubble(
                          'I need a cool jacket for a night out in the city. Something edgy but clean.',
                          '2:14 PM',
                        );
                      }
                      if (index == 2) {
                        return _aiBubble(
                          'I found this for you. It\'s a premium leather-look bomber with a modern fit that perfectly matches your vibe.',
                          showHeader: true,
                        );
                      }
                      if (index == 3) {
                        return _productCard();
                      }
                      if (index == 4) {
                        return _aiBubble(
                          'Would you like to see how this looks with your silver jewelry?',
                          showHeader: false,
                        );
                      }
                      return const SizedBox();
                    }
                    if (index == messages.length && chatNotifier.isTyping) {
                      return const _TypingIndicator();
                    }
                    final msg = messages[index];
                    return msg.role == 'user'
                        ? _userBubble(msg.content, '', imageUrls: msg.imageUrls)
                        : _aiBubble(
                            msg.content,
                            showHeader:
                                index == 0 ||
                                messages[index - 1].role != 'assistant',
                          );
                  },
                ),
              ),
            ],
          ),

          // Input bar — glassmorphic per design.md
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingImages.isNotEmpty) _pendingImageStrip(),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.add_photo_alternate_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              onPressed: _chooseImageSource,
                            ),
                            IconButton(
                              icon: Icon(
                                _isListening
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _isListening
                                    ? AppColors.secondary
                                    : AppColors.primary,
                                size: 22,
                              ),
                              onPressed: _toggleVoice,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: AppTextStyles.bodyLg.copyWith(
                                  color: AppColors.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: _isListening
                                      ? 'Listening...'
                                      : 'Ask your stylist...',
                                  hintStyle: AppTextStyles.bodyLg.copyWith(
                                    color: AppColors.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 14,
                                  ),
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: GestureDetector(
                                onTap: _send,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.arrow_upward,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quote Block per design.md Screen 12 ──
  Widget _quoteBlock() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: FadeTransition(
        opacity: _quoteFade,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(32),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary,
                    AppColors.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  '"Style is a conversation.\nWhat are we wearing today?"',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.quoteVibrant.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── User Bubble per design.md Screen 12 ──
  Widget _pendingImageStrip() {
    return Container(
      height: 74,
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final image = _pendingImages[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  image.bytes,
                  width: 74,
                  height: 74,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _userBubble(
    String text,
    String time, {
    List<String> imageUrls = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imageUrls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: imageUrls
                      .map(
                        (url) => ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SafeNetworkImage(
                            imageUrl: url,
                            width: 120,
                            height: 140,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(8),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  text,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
            if (time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  time,
                  style: AppTextStyles.labelCaps.copyWith(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── AI Bubble per design.md Screen 12 ──
  Widget _aiBubble(String text, {required bool showHeader}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer.withValues(
                        alpha: 0.2,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.secondaryContainer,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI Stylist',
                    style: AppTextStyles.labelCaps.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Product Card per design.md Screen 12 ──
  Widget _productCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Stack(
              children: [
                // White gradient overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                Column(
                  children: [
                    // Image
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: Stack(
                          children: [
                            SafeNetworkImage(
                              imageUrl:
                                  'https://images.unsplash.com/photo-1551028719-01c1eb562110?q=80&w=600&auto=format&fit=crop',
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                            // Match badge
                            Positioned(
                              top: 16,
                              right: 16,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9999),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 12,
                                    sigmaY: 12,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(9999),
                                    ),
                                    child: Text(
                                      '95% Match',
                                      style: AppTextStyles.labelCaps.copyWith(
                                        color: AppColors.primary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Details
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Midnight Urban Bomber',
                                  style: AppTextStyles.headlineMd.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '\$189',
                                style: AppTextStyles.headlineMd.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SUSTAINABLE VEGAN LEATHER',
                            style: AppTextStyles.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // CTA
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(9999),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                              ),
                              icon: const Icon(Icons.checkroom, size: 20),
                              label: Text(
                                'TRY ON',
                                style: AppTextStyles.labelCaps.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              onPressed: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Typing Indicator ──
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppColors.secondaryContainer,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _Dot(delay: i * 200),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickedChatImage {
  final Uint8List bytes;
  final String extension;
  final String mimeType;

  const _PickedChatImage({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.3 + _ctrl.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
