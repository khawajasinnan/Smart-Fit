import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/widgets/ai_chat_logo.dart';
import 'package:smartfit/core/widgets/camera_preview_dialog.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/chat/providers/chat_provider.dart';
import 'package:smartfit/features/chat/widgets/product_card_widget.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
      builder: (_) => const CameraPreviewDialog(showPoseOverlay: true),
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
          final sessions = notifier.sessions
              .where((s) => s.title != 'Style Session')
              .toList();
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
                      // Clear all sessions button
                      if (sessions.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: Text(
                                  'Clear All Chats',
                                  style: AppTextStyles.headlineMd.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                content: Text(
                                  'Delete all past chat sessions? This cannot be undone.',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: Text(
                                      'Cancel',
                                      style: AppTextStyles.bodyMd.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      Navigator.pop(dialogCtx);
                                      Navigator.pop(ctx);
                                      notifier.clearAllSessions();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            color: AppColors.onSurfaceVariant,
                          ),
                          tooltip: 'Clear all chats',
                        ),
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
                          return Dismissible(
                            key: Key(session.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: AppColors.error.withValues(alpha: 0.1),
                              child: const Icon(
                                Icons.delete_rounded,
                                color: AppColors.error,
                              ),
                            ),
                            onDismissed: (_) {
                              notifier.deleteSession(session.id);
                            },
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryContainer,
                                child: AiChatLogo(
                                  size: 28,
                                  padding: 4,
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
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                  size: 20,
                                ),
                                onPressed: () {
                                  notifier.deleteSession(session.id);
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                notifier.loadSession(session.id);
                              },
                            ),
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

          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.05,
              color: Color(0xFFFF2E93),
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
                        child: const AiChatLogo(
                          size: 28,
                          padding: 0,
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
                  itemCount:
                      messages.length +
                      (chatNotifier.isTyping ? 1 : 0) +
                      (chatNotifier.isSearching ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Typing / searching indicators at the end
                    if (index >= messages.length) {
                      final extraIndex = index - messages.length;
                      if (chatNotifier.isTyping && extraIndex == 0) {
                        return const _TypingIndicator();
                      }
                      return const _SearchingIndicator();
                    }

                    final msg = messages[index];

                    // ── Product carousel message ──
                    if (msg.hasProducts) {
                      return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.content.isNotEmpty)
                                _aiBubble(
                                  msg.content,
                                  showHeader:
                                      index == 0 ||
                                      messages[index - 1].role != 'assistant',
                                ),
                              ProductCarousel(products: msg.products),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .slideY(begin: 0.05, curve: Curves.easeOutQuad);
                    }

                    // ── Regular messages ──
                    return msg.role == 'user'
                        ? _userBubble(msg.content, '', imageUrls: msg.imageUrls)
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .slideX(begin: 0.05, curve: Curves.easeOutQuad)
                        : _aiBubble(
                                msg.content,
                                showHeader:
                                    index == 0 ||
                                    messages[index - 1].role != 'assistant',
                                isFirstMessage: index == 0,
                              )
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .slideX(begin: -0.05, curve: Curves.easeOutQuad);
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

  void _sendPrompt(String prompt) {
    _controller.text = prompt;
    _send();
  }

  // ── AI Bubble per design.md Screen 12 ──
  Widget _aiBubble(String text, {required bool showHeader, bool isFirstMessage = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E93).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const AiChatLogo(
                        size: 24,
                        padding: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI Stylist',
                    style: AppTextStyles.labelCaps.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2E93).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Style Advisor',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF2E93),
                      ),
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
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.92),
                        const Color(0xFFFFF0F7).withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: const Color(0xFFFF2E93).withValues(alpha: 0.22),
                      width: 1.2,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.onSurface,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Message action pills
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, size: 13, color: AppColors.onSurfaceVariant),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved to your Style Vault!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2E93).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFF2E93).withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.favorite_rounded, size: 13, color: Color(0xFFFF2E93)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Love Fit',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFF2E93),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // If welcome message, render interactive suggestion chips
          if (isFirstMessage) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'QUICK QUESTIONS / SAWAL POOCHEN',
                style: AppTextStyles.labelCaps.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  color: const Color(0xFFFF2E93),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _starterPromptChip('Fit check karwaen', 'Mera outfit check karein aur simple styling advice dein.'),
                _starterPromptChip('Casual daily wear', 'Mujhe daily routine ke liye comfortable aur stylish outfit suggest karein.'),
                _starterPromptChip('Party ya wedding dress', 'Kisi wedding ya party ke liye accha suit recommend karein.'),
                _starterPromptChip('Under 10k budget look', 'Mujhe 10,000 PKR ke andar best complete outfit dikhaen.'),
                _starterPromptChip('Traditional cultural suit', 'Mere cultural background ke mutabiq traditional outfit recommend karein.'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _starterPromptChip(String label, String prompt) {
    return GestureDetector(
      onTap: () => _sendPrompt(prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFF2E93).withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6C4CE0),
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
            child: const AiChatLogo(
              size: 28,
              padding: 0,
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

// ── Searching Indicator (shown while scraping Pakistani stores) ──
class _SearchingIndicator extends StatelessWidget {
  const _SearchingIndicator();
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
              Icons.shopping_bag_rounded,
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
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Searching Pakistani stores...',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
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
