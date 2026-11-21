import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/features/chatbot/data/models/app_screen_link.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:smartfit/core/network/network_providers.dart';
import 'package:dio/dio.dart';
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
import 'package:smartfit/shared_widgets/zayn_avatar.dart';
import 'package:smartfit/features/body_scan/scan_summary.dart';
import 'package:smartfit/features/body_scan/screens/body_scan_camera.dart';
import 'package:smartfit/features/body_scan/screens/scan_analysis_screen.dart';
import 'package:smartfit/features/body_scan/widgets/body_scan_card.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_hero.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_mood.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_voice.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/features/chatbot/data/models/chat_message_model.dart';
import 'package:smartfit/features/chatbot/providers/chat_provider.dart';
import 'package:smartfit/features/recommendation/widgets/product_card_widget.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AiStylistChatScreen extends ConsumerStatefulWidget {
  const AiStylistChatScreen({super.key});
  @override
  ConsumerState<AiStylistChatScreen> createState() => _AiStylistChatScreenState();
}

class _AiStylistChatScreenState extends ConsumerState<AiStylistChatScreen> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final List<_PickedChatImage> _pendingImages = [];
  bool _initialized = false;
  bool _isListening = false;
  bool _speechReady = false;
  bool _sending = false;
  late final ZaynVoice _voice;

  /// The AI stylist accepts up to 4 photos per message (backend limit).
  static const int _maxImages = 4;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(zaynVoiceProvider.notifier);
    _initSpeech();
    _controller.addListener(_onDraftChanged);
  }

  /// Zayn listens while the user types (spec §23.14).
  void _onDraftChanged() {
    if (_controller.text.trim().isEmpty || _sending) return;
    ref.read(zaynProvider.notifier).listening();
    if (ref.read(zaynVoiceProvider).speaking) _voice.stop(); // he stops talking when you do
  }

  /// "Hello [first name]! ..." using the name from profile onboarding.
  String _greeting(String userId) {
    final profileName = ref.read(profileNotifierProvider(userId)).valueOrNull?.fullName;
    final meta = ref.read(currentUserProvider)?.userMetadata;
    final name = [
      profileName,
      meta?['full_name'],
      meta?['name'],
    ].whereType<String>().map((n) => n.trim()).firstWhere((n) => n.isNotEmpty, orElse: () => '');
    return zaynGreeting(name);
  }

  /// Open (or restart) the chat: Zayn waves and says hello by name, aloud.
  Future<void> _startAndGreet(ChatNotifier chatNotifier, String userId, {bool fresh = false}) async {
    // Opened from a Zayn notification answer? Her reaction is the opener.
    final intro = ref.read(zaynProvider.notifier).takePendingIntro();
    final greeting = intro?.quip ?? _greeting(userId);
    ref
        .read(zaynProvider.notifier)
        .react(intro?.mood ?? ZaynMood.hello, quip: greeting, hold: const Duration(seconds: 8));
    _voice.say(greeting);
    await chatNotifier.startSession(fresh: fresh, announce: false);
  }

  @override
  void dispose() {
    // Stop the microphone and Zayn's voice if the user leaves.
    _speech.stop();
    _voice.stop();
    _controller.removeListener(_onDraftChanged);
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice input stopped: ${error.errorMsg}')));
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
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    // One message at a time: wait for the stylist's reply or product search.
    final notifier = ref.read(chatNotifierProvider(user.id).notifier);
    if (_sending || notifier.isTyping || notifier.isSearching) return;
    final images = _pendingImages
        .map((image) => PendingChatImage(bytes: image.bytes, extension: image.extension, mimeType: image.mimeType))
        .toList();
    _controller.clear();
    setState(() {
      _pendingImages.clear();
      _sending = true;
    });
    try {
      await notifier.sendMessage(text, images: images);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  void _showImageLimit() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You can attach up to 4 photos per message.')));
  }

  Future<void> _chooseImageSource() async {
    final choice = await showModalBottomSheet<ChatAttachChoice>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => const ChatAttachSheet(maxImages: _maxImages),
    );
    switch (choice) {
      case null:
        return;
      case ChatAttachChoice.scanCamera:
        await _takeLivePhoto();
      case ChatAttachChoice.scanGallery:
        await _scanGalleryPhoto();
      case ChatAttachChoice.scanProfile:
        await _scanProfilePhoto();
      case ChatAttachChoice.outfitGallery:
        await _pickImagesFromGallery();
    }
  }

  /// Live body & face scan: camera with on-device overlay, then the backend
  /// analysis (MediaPipe + HRNet). The results card goes into the chat and
  /// the photo is attached for the stylist.
  Future<void> _takeLivePhoto() async {
    if (_pendingImages.length >= _maxImages) {
      _showImageLimit();
      return;
    }
    while (true) {
      if (!mounted) return;
      final bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        useSafeArea: false,
        builder: (_) => const BodyScanCamera(),
      );
      if (bytes == null || !mounted) return;
      if (await _analyseForChat(bytes) != _ScanResult.retake) return;
    }
  }

  /// SFR-016: a photo of the user from the gallery, analysed like the camera scan.
  Future<void> _scanGalleryPhoto() async {
    if (_pendingImages.length >= _maxImages) {
      _showImageLimit();
      return;
    }
    while (mounted) {
      final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (await _analyseForChat(bytes) != _ScanResult.retake) return;
    }
  }

  /// SFR-017: the user's existing profile photo as this chat's analysis photo, no new upload.
  Future<void> _scanProfilePhoto() async {
    if (_pendingImages.length >= _maxImages) {
      _showImageLimit();
      return;
    }
    final uid = ref.read(currentUserProvider)?.id;
    final url = uid == null ? null : ref.read(profileNotifierProvider(uid)).valueOrNull?.photoUrl;
    if (url == null || url.trim().isEmpty) {
      _snack('You have no profile photo yet. Take a photo or choose one instead.');
      return;
    }
    Uint8List bytes;
    try {
      final res = await ref
          .read(externalDioProvider)
          .get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final data = res.data;
      if (data == null || data.isEmpty) throw StateError('empty');
      bytes = Uint8List.fromList(data);
    } catch (_) {
      if (mounted) _snack("Couldn't load your profile photo. Please take or choose a photo instead.");
      return;
    }
    if (!mounted) return;
    if (await _analyseForChat(bytes) == _ScanResult.retake && mounted) {
      await _takeLivePhoto(); // "Retake" on the profile photo means: take a new one
    }
  }

  /// The body & face analysis of [bytes]; its card goes into the chat (the stylist
  /// is briefed with it) and the photo is attached for the stylist.
  Future<_ScanResult> _analyseForChat(Uint8List bytes) async {
    final outcome = await Navigator.of(context, rootNavigator: true).push<BodyScanOutcome>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanAnalysisScreen(bytes: bytes)),
    );
    if (outcome == null || !mounted) return _ScanResult.cancelled;
    if (outcome.retake) return _ScanResult.retake;
    final analysis = outcome.analysis;
    final user = ref.read(currentUserProvider);
    if (analysis != null && user != null) {
      await ref.read(chatNotifierProvider(user.id).notifier).addBodyScan(ScanSummary.fromResult(analysis));
    }
    if (!mounted) return _ScanResult.done;
    setState(
      () =>
          _pendingImages.add(_PickedChatImage(bytes: outcome.bytes ?? bytes, extension: 'jpg', mimeType: 'image/jpeg')),
    );
    return _ScanResult.done;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImagesFromGallery() async {
    final files = await _picker.pickMultiImage(maxWidth: 1400, imageQuality: 82);
    if (files.isEmpty) return;
    final room = _maxImages - _pendingImages.length;
    if (room <= 0 || files.length > room) {
      if (mounted) _showImageLimit();
      if (room <= 0) return;
    }
    final selected = <_PickedChatImage>[];
    for (final file in files.take(room)) {
      final bytes = await file.readAsBytes();
      final extension = _extensionFromName(file.name);
      selected.add(_PickedChatImage(bytes: bytes, extension: extension, mimeType: _mimeTypeForExtension(extension)));
    }
    if (mounted) setState(() => _pendingImages.addAll(selected));
  }

  Future<void> _toggleVoice() async {
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Voice input is not available on this device yet.')));
        return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    await _voice.stop(); // don't dictate Zayn's own voice
    if (!mounted) return;
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
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        if (result.finalResult && mounted) setState(() => _isListening = false);
      },
    );
  }

  void _showHistory(ChatNotifier chatNotifier) {
    chatNotifier.loadSessions();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final user = ref.watch(currentUserProvider);
          if (user == null) return const SizedBox.shrink();
          final notifier = ref.read(chatNotifierProvider(user.id).notifier);
          ref.watch(chatNotifierProvider(user.id));
          final sessions = notifier.sessions.where((s) => s.title != 'Style Session').toList();
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
                      color: context.cs.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Past Style Chats', style: AppTextStyles.headlineMd.copyWith(color: context.cs.onSurface)),
                      const Spacer(),
                      // Clear all sessions button
                      if (sessions.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                backgroundColor: context.cs.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: Text(
                                  'Clear All Chats',
                                  style: AppTextStyles.headlineMd.copyWith(color: context.cs.onSurface),
                                ),
                                content: Text(
                                  'Delete all past chat sessions? This cannot be undone.',
                                  style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurfaceVariant),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: Text(
                                      'Cancel',
                                      style: AppTextStyles.bodyMd.copyWith(color: context.cs.primary),
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      Navigator.pop(dialogCtx);
                                      Navigator.pop(ctx);
                                      notifier.clearAllSessions();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: context.cs.error,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: Icon(Icons.delete_sweep_rounded, color: context.cs.onSurfaceVariant),
                          tooltip: 'Clear all chats',
                        ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final uid = ref.read(currentUserProvider)?.id;
                          if (uid != null) _startAndGreet(notifier, uid, fresh: true);
                        },
                        icon: Icon(Icons.add_comment_rounded, color: context.cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (notifier.isLoadingSessions)
                    const Padding(padding: EdgeInsets.all(24), child: SFLoader(size: 56))
                  else if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No past chats yet.',
                        style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurfaceVariant),
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
                              color: context.cs.error.withValues(alpha: 0.1),
                              child: Icon(Icons.delete_rounded, color: context.cs.error),
                            ),
                            onDismissed: (_) {
                              notifier.deleteSession(session.id);
                            },
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const ZaynAvatar(size: 40),
                              title: Text(
                                session.title ?? 'Style Session',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(DateFormat('MMM d, h:mm a').format(session.updatedAt)),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAndGreet(chatNotifier, user.id));
    }
    // Scroll only when a message is added — not on every rebuild, which
    // used to yank the list down while the user was reading history.
    ref.listen<List<ChatMessageModel>>(chatNotifierProvider(user.id), (prev, next) {
      if (prev == null || next.length != prev.length) _scrollToBottom();
      // Zayn reads each new reply aloud (not history loads or the welcome text).
      if (prev != null && prev.isNotEmpty && next.length == prev.length + 1) {
        final m = next.last;
        if (m.role == 'assistant' && m.metadata?['type'] != ScanSummary.metadataType) _voice.say(m.content);
      }
    });
    final muted = ref.watch(zaynVoiceProvider.select((v) => v.muted));

    return Scaffold(
      backgroundColor: context.cs.surface,
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
                gradient: RadialGradient(colors: [context.cs.primary.withValues(alpha: 0.12), Colors.transparent]),
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
                  colors: [AppColors.secondaryFixedDim.withValues(alpha: 0.15), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(child: ClothingPatternBackground()),

          Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.canPop() ? context.pop() : context.go(RoutePaths.home),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.cs.surfaceContainer.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.arrow_back, color: context.cs.onSurface, size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const ZaynAvatar(size: 40),
                      const SizedBox(width: 10),
                      Text('Zayn', style: AppTextStyles.headlineMd.copyWith(color: context.cs.primary)),
                      const Spacer(),
                      IconButton(
                        tooltip: muted ? "Unmute Zayn's voice" : "Mute Zayn's voice",
                        icon: Icon(
                          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: context.cs.primary,
                        ),
                        onPressed: () => _voice.setMuted(!muted),
                      ),
                      IconButton(
                        tooltip: 'History',
                        icon: Icon(Icons.history_rounded, color: context.cs.primary),
                        onPressed: () => _showHistory(chatNotifier),
                      ),
                      IconButton(
                        tooltip: 'New chat',
                        icon: Icon(Icons.add_comment_rounded, color: context.cs.primary),
                        onPressed: () => _startAndGreet(chatNotifier, user.id, fresh: true),
                      ),
                    ],
                  ),
                ),
              ),

              // Zayn, the AI stylist mascot: big on a new chat, compact after
              ZaynHero(compact: messages.length > 1),

              // Chat area
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
                  itemCount: messages.length + (chatNotifier.isTyping ? 1 : 0) + (chatNotifier.isSearching ? 1 : 0),
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

                    // ── Body & face scan results ──
                    if (msg.metadata?['type'] == ScanSummary.metadataType) {
                      return BodyScanCard(
                        summary: ScanSummary.fromMap(msg.metadata!),
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, curve: Curves.easeOutQuad);
                    }

                    // ── Product carousel message ──
                    if (msg.hasProducts) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.content.isNotEmpty)
                            _aiBubble(msg.content, showHeader: index == 0 || messages[index - 1].role != 'assistant'),
                          ProductCarousel(products: msg.products),
                        ],
                      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.05, curve: Curves.easeOutQuad);
                    }

                    // ── Regular messages ──
                    return msg.role == 'user'
                        ? _userBubble(
                            msg.content,
                            '',
                            imageUrls: msg.imageUrls,
                          ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05, curve: Curves.easeOutQuad)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _aiBubble(
                                msg.content,
                                showHeader: index == 0 || messages[index - 1].role != 'assistant',
                                isFirstMessage: index == 0,
                              ),
                              // App-help answers: a button to the screen Zayn explained.
                              if (AppScreenLink.fromKey(msg.metadata?[AppScreenLink.metadataKey] as String?)
                                  case final link?)
                                OpenScreenButton(link: link),
                            ],
                          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05, curve: Curves.easeOutQuad);
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
                  color: context.cs.surface.withValues(alpha: 0.8),
                  padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingImages.isNotEmpty) _pendingImageStrip(),
                      Container(
                        decoration: BoxDecoration(
                          color: context.cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.3)),
                          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 20, offset: const Offset(0, 4))],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Add a photo',
                              icon: Icon(Icons.add_photo_alternate_rounded, color: context.cs.primary, size: 22),
                              onPressed: _chooseImageSource,
                            ),
                            IconButton(
                              tooltip: _isListening ? 'Stop listening' : 'Speak your message',
                              icon: Icon(
                                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                color: _isListening ? context.sf.accentText : context.cs.primary,
                                size: 22,
                              ),
                              onPressed: _toggleVoice,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: AppTextStyles.bodyLg.copyWith(color: context.cs.onSurface),
                                decoration: InputDecoration(
                                  hintText: _isListening ? 'Listening...' : 'Ask your stylist...',
                                  hintStyle: AppTextStyles.bodyLg.copyWith(
                                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Semantics(
                                button: true,
                                label: 'Send message',
                                excludeSemantics: true,
                                child: GestureDetector(
                                  onTap: _send,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: AppColors.neonGreen, shape: BoxShape.circle),
                                    child: const Icon(Icons.arrow_upward, color: AppColors.ink900, size: 20),
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
                child: Image.memory(image.bytes, width: 74, height: 74, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Semantics(
                  button: true,
                  label: 'Remove photo',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingImages.removeAt(index)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
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

  Widget _userBubble(String text, String time, {List<String> imageUrls = const []}) {
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
                          child: SafeNetworkImage(imageUrl: url, width: 120, height: 140, fit: BoxFit.cover),
                        ),
                      )
                      .toList(),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(8),
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text(text, style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurface)),
              ),
            ),
            if (time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  time,
                  style: AppTextStyles.labelCaps.copyWith(
                    fontSize: 10,
                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
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
                      gradient: context.sf.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.transparent, blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const ZaynAvatar(size: 30),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Zayn',
                    style: AppTextStyles.labelCaps.copyWith(color: context.cs.primary, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.hotPink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Style Advisor',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.sf.accentText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
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
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        context.sf.surfaceElevated.withValues(alpha: 0.92),
                        context.sf.surfaceSunken.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: context.sf.highlight.withValues(alpha: 0.22), width: 1.2),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 28, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurface, height: 1.45)),
                      const SizedBox(height: 12),
                      // Message action pills
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied to clipboard!'), duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.cs.onSurface.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.cs.outlineVariant),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, size: 13, color: context.cs.onSurfaceVariant),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.cs.onSurfaceVariant,
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
                  color: context.sf.accentText,
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
                _starterPromptChip(
                  'Casual daily wear',
                  'Mujhe daily routine ke liye comfortable aur stylish outfit suggest karein.',
                ),
                _starterPromptChip(
                  'Party ya wedding dress',
                  'Kisi wedding ya party ke liye accha suit recommend karein.',
                ),
                _starterPromptChip('Under 10k budget look', 'Mujhe 10,000 PKR ke andar best complete outfit dikhaen.'),
                _starterPromptChip(
                  'Traditional cultural suit',
                  'Mere cultural background ke mutabiq traditional outfit recommend karein.',
                ),
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
          color: context.sf.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.sf.highlight.withValues(alpha: 0.35), width: 1.2),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: context.cs.primary,
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
            child: const ZaynAvatar(size: 28),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: context.cs.surface.withValues(alpha: 0.8),
                  border: Border.all(color: context.sf.glassBorder),
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
            child: const Icon(Icons.shopping_bag_rounded, color: AppColors.secondaryContainer, size: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: context.cs.surface.withValues(alpha: 0.8),
                  border: Border.all(color: context.sf.glassBorder),
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
                    const SFLoader.small(),
                    const SizedBox(width: 10),
                    Text(
                      'Searching Pakistani stores...',
                      style: AppTextStyles.bodySm.copyWith(color: context.cs.primary, fontWeight: FontWeight.w600),
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

  const _PickedChatImage({required this.bytes, required this.extension, required this.mimeType});
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
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
          color: context.cs.primary.withValues(alpha: 0.3 + _ctrl.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// "Open Virtual Try-On" etc. under an app-help answer from Zayn.
class OpenScreenButton extends StatelessWidget {
  const OpenScreenButton({super.key, required this.link});

  final AppScreenLink link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: OutlinedButton.icon(
        onPressed: () => link.open(context),
        icon: Icon(link.icon, size: 18),
        label: Text(link.label),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.sf.ink,
          side: BorderSide(color: AppColors.hotPink.withValues(alpha: 0.6), width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: context.tt.labelLarge,
        ),
      ),
    );
  }
}

/// What the chat's attach sheet was asked for.
enum ChatAttachChoice { scanCamera, scanGallery, scanProfile, outfitGallery }

/// The chat's "+" sheet: analyse a photo of me for this chat (SFR-016: camera
/// or gallery; SFR-017: my profile photo, no new upload), or show Zayn an
/// outfit picture. Pops the chosen [ChatAttachChoice].
class ChatAttachSheet extends StatelessWidget {
  const ChatAttachSheet({super.key, required this.maxImages});

  final int maxImages;

  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String title, String subtitle, ChatAttachChoice choice, {Color? colour}) => ListTile(
      leading: Icon(icon, color: colour ?? context.cs.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.pop(context, choice),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: context.cs.outlineVariant, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Analyse me for this chat', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
            option(
              Icons.photo_camera_rounded,
              'Take a photo of me',
              'Live body & face scan',
              ChatAttachChoice.scanCamera,
            ),
            option(
              Icons.image_search_rounded,
              'Choose a photo of me',
              'A full-body photo from your gallery',
              ChatAttachChoice.scanGallery,
            ),
            option(
              Icons.account_circle_rounded,
              'Use my profile photo',
              'No new photo needed',
              ChatAttachChoice.scanProfile,
            ),
            const Divider(height: 20),
            Text('Show Zayn a picture', style: AppTextStyles.titleSm.copyWith(fontWeight: FontWeight.w700)),
            option(
              Icons.photo_library_rounded,
              'Outfit photos from gallery',
              'Up to $maxImages, e.g. a look you like',
              ChatAttachChoice.outfitGallery,
              colour: AppColors.secondaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ScanResult { done, retake, cancelled }
