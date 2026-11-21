import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_images.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/features/body_scan/screens/body_scan_camera.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/tilt_card.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smartfit/features/home/widgets/home_cards.dart';
import 'package:smartfit/features/home/widgets/culture_style_card.dart';
import 'package:smartfit/features/home/widgets/home_peekers.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});
  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  final _peekers = PeekersController();
  DateTime _lastScrollReaction = DateTime(2000);

  /// The eyes react to how the page is scrolled: a fast fling makes them
  /// dizzy, pulling down past the top makes them jump (at most every 5 s).
  bool _onScroll(ScrollUpdateNotification n) {
    final delta = n.scrollDelta ?? 0;
    final now = DateTime.now();
    if (now.difference(_lastScrollReaction) < const Duration(seconds: 5)) return false;
    if (n.metrics.pixels < -70) {
      _lastScrollReaction = now;
      _peekers.react('jump');
    } else if (delta.abs() > 70) {
      _lastScrollReaction = now;
      _peekers.react('dizzy');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _peekers.dispose();
    super.dispose();
  }

  void _startBodyScan(UserProfileModel? profile) async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BodyScanCamera(),
    );

    if (bytes == null || !mounted) return;

    // Show analyzing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SFLoader(),
              const SizedBox(height: 20),
              Text(
                'Analyzing Body Scan...',
                style: AppTextStyles.headlineMd.copyWith(color: context.cs.onSurface, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'MediaPipe is finding 33 body landmarks to estimate your proportions and size.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final base64Image = base64Encode(bytes);
      final service = ref.read(cvAnalysisApiServiceProvider);
      final result = await service.analyzeBody(
        imageBase64: base64Image,
        gender: profile?.gender,
        heightCm: profile?.heightCm,
        weightKg: profile?.weightKg,
        profile: profile,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog

      if (result.success) {
        final details = [
          if (result.bodyShape != null) 'Body type: ${result.bodyShape}',
          if (result.estimatedSize != null) 'Size: ${result.estimatedSize}',
        ].join(' · ');
        ref
            .read(notificationNotifierProvider.notifier)
            .notify(
              NotificationKind.analysisDone,
              title: 'Your body analysis is ready ✨',
              body: details.isEmpty ? 'Open SmartFit to see your results.' : details,
              route: '/home',
            );
        _showCvResultsSheet(result, profile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'CV analysis failed. Please try again.'),
            backgroundColor: context.cs.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Body scan error: $e'), backgroundColor: context.cs.error));
      }
    }
  }

  void _showCvResultsSheet(CvAnalysisResult result, UserProfileModel? profile) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: context.cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: context.sf.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 30,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: context.cs.outlineVariant, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.sf.highlight.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.accessibility_new_rounded, color: context.sf.highlight, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CV Body Analysis',
                        style: AppTextStyles.headlineMd.copyWith(
                          color: context.cs.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'MediaPipe 33-Landmark Pose Detection',
                        style: AppTextStyles.bodySm.copyWith(
                          color: context.sf.highlight,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Metric Cards Row
            Row(
              children: [
                Expanded(
                  child: _cvMetricCard(
                    title: 'Body Shape',
                    value: result.bodyShape ?? 'Athletic',
                    subtitle: result.bodyShapeConfidence > 0
                        ? '${(result.bodyShapeConfidence * 100).toStringAsFixed(0)}% Match'
                        : 'Calibrated',
                    icon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _cvMetricCard(
                    title: 'Recommended Size',
                    value: result.estimatedSize ?? 'M',
                    subtitle: 'Ready-to-Wear',
                    icon: Icons.straighten_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _cvMetricCard(
                    title: 'Chest Estimate',
                    value: result.estimatedChestCm != null ? '${result.estimatedChestCm!.toStringAsFixed(1)} cm' : '--',
                    subtitle: 'Circumference',
                    icon: Icons.checkroom_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _cvMetricCard(
                    title: 'Waist Estimate',
                    value: result.estimatedWaistCm != null ? '${result.estimatedWaistCm!.toStringAsFixed(1)} cm' : '--',
                    subtitle: 'Circumference',
                    icon: Icons.aspect_ratio_rounded,
                  ),
                ),
              ],
            ),
            if (result.skinTone != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _parseHexColor(result.skinTone!.dominantHex),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skin Tone: ${result.skinTone!.toneLabel}',
                            style: AppTextStyles.titleMd.copyWith(
                              color: context.cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            result.skinTone!.fitzpatrickType,
                            style: AppTextStyles.bodySm.copyWith(color: context.cs.onSurfaceVariant, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (profile != null) {
                    final updated = profile.copyWith(
                      bodyType: result.bodyShape ?? profile.bodyType,
                      chestCm: result.estimatedChestCm ?? profile.chestCm,
                      waistCm: result.estimatedWaistCm ?? profile.waistCm,
                      hipCm: result.estimatedHipCm ?? profile.hipCm,
                      skinTone: result.skinTone?.toneLabel ?? profile.skinTone,
                    );
                    try {
                      await ref.read(profileNotifierProvider(profile.id).notifier).updateProfile(updated);
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Couldn't save your measurements. Please try again.")),
                      );
                      return;
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Profile updated with CV scan measurements! ✨'),
                        backgroundColor: context.cs.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(20),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text(
                  'Apply Measurements to Profile',
                  style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cvMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: context.sf.highlight),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.bodySm.copyWith(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headlineMd.copyWith(
              color: context.cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyles.bodySm.copyWith(
              color: context.sf.highlight,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('0xFF$clean'));
      }
      return const Color(0xFFC49A6C);
    } catch (_) {
      return const Color(0xFFC49A6C);
    }
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final currentNotifState = ref.watch(notificationNotifierProvider);
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
            decoration: BoxDecoration(
              color: context.cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: context.sf.glassBorder),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.cs.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            LinearGradient(colors: [context.sf.highlight, AppColors.accent600]).createShader(bounds),
                        child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text('Notifications', style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (currentNotifState.isEnabled && currentNotifState.unreadCount > 0)
                        TextButton(
                          onPressed: () {
                            ref.read(notificationNotifierProvider.notifier).markAllAsRead();
                          },
                          child: Text(
                            'Mark all read',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontWeight: FontWeight.w600,
                              color: context.sf.highlight,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!currentNotifState.isEnabled)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: context.sf.highlight.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.notifications_off_outlined, size: 32, color: context.sf.highlight),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Notifications Disabled in Settings 🔕',
                              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enable notifications from the Settings page to get live style alerts, Gen-Z trend drops, and virtual try-on reminders on your app.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                height: 1.4,
                                color: context.cs.onSurfaceVariant.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.go(RoutePaths.profile);
                              },
                              icon: const Icon(Icons.settings_outlined, size: 18),
                              label: const Text(
                                'Open Settings',
                                style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.cs.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (currentNotifState.items.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No notifications yet.',
                        style: AppTextStyles.bodyMd.copyWith(color: context.cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: currentNotifState.items.length,
                      itemBuilder: (context, idx) {
                        final item = currentNotifState.items[idx];
                        return GestureDetector(
                          onTap: () {
                            ref.read(notificationNotifierProvider.notifier).markAsRead(item.id);
                            if (item.category == 'trends') {
                              Navigator.pop(ctx);
                              context.go(RoutePaths.chat);
                            } else if (item.category == 'chat') {
                              Navigator.pop(ctx);
                              context.go(RoutePaths.chat);
                            } else if (item.category == 'wardrobe') {
                              Navigator.pop(ctx);
                              context.go(RoutePaths.wardrobe);
                            }
                          },
                          child: _notificationItem(
                            icon: item.icon,
                            title: item.title,
                            subtitle: item.subtitle,
                            time: item.time,
                            isNew: item.isNew,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _notificationItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
    required bool isNew,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isNew ? context.sf.highlight.withValues(alpha: 0.06) : context.sf.glassFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isNew ? context.sf.highlight.withValues(alpha: 0.3) : context.sf.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: isNew
                  ? context.sf.brandGradient
                  : LinearGradient(
                      colors: [
                        context.cs.onSurfaceVariant.withValues(alpha: 0.1),
                        context.cs.onSurfaceVariant.withValues(alpha: 0.05),
                      ],
                    ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isNew ? context.sf.onBrand : context.cs.onSurfaceVariant, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                    color: context.cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  time,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isNew ? context.sf.highlight : context.cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (isNew)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: context.sf.highlight),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final profileAsync = user == null
        ? const AsyncValue<UserProfileModel?>.data(null)
        : ref.watch(profileNotifierProvider(user.id));
    final profile = profileAsync.valueOrNull;
    final photoUrl = profile?.photoUrl ?? user?.avatarUrl;
    final displayName = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim().split(' ').first
        : 'there';

    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Stack(
        children: [
          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(child: ClothingPatternBackground()),

          // ── Main Scrollable Content ── (taps anywhere: the header eyes look there)
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) => _peekers.lookAt(e.position),
            child: PeekersScope(
              controller: _peekers,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                child: SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ═══════════════════════════════════════
                        // HEADER: Welcome + Mood + Notification + Search
                        // ═══════════════════════════════════════
                        _buildHeader(displayName, photoUrl),
                        const SizedBox(height: 20),

                        // Zayn's tip of the day, the style streak, trending picks (spec §23.19)
                        _entrance(const ZaynTipCard(), 0),
                        const SizedBox(height: 18),
                        _entrance(const StyleStreakCard(), 1),
                        const SizedBox(height: 24),
                        _entrance(const TrendingPicks(), 2),
                        const SizedBox(height: 8),
                        // the profile's culture: its outfits for the user's gender (21 Nov 2026)
                        _entrance(const CultureStyleCard(), 2),

                        // ═══════════════════════════════════════
                        // BODY SCAN HERO CARD
                        // ═══════════════════════════════════════
                        _entrance(_buildBodyScanCard(profile), 3),
                        const SizedBox(height: 24),

                        // ═══════════════════════════════════════
                        // ACTION BUTTONS ROW
                        // ═══════════════════════════════════════
                        _entrance(_buildActionButtonsRow(), 4),
                      ],
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

  /// Cards slide up one after another when Home opens (none with reduce motion).
  Widget _entrance(Widget child, int index) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return child
        .animate(delay: (90 * index + 120).ms)
        .fadeIn(duration: 520.ms)
        .slideY(begin: 0.08, curve: Curves.easeOutCubic)
        .scale(begin: const Offset(0.97, 0.97), curve: Curves.easeOutCubic);
  }

  /// "Good morning" etc. under the name.
  static String greeting(DateTime now) => switch (now.hour) {
    < 5 => "Up late? Let's plan a fit",
    < 12 => 'Good morning ☀️',
    < 17 => 'Good afternoon ✨',
    < 21 => 'Good evening 🌙',
    _ => 'Late-night outfit planning? Respect',
  };

  // ═══════════════════════════════════════════════════════════
  // INTERACTIVE HEADER SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildHeader(String displayName, String? photoUrl) {
    final notifState = ref.watch(notificationNotifierProvider);
    final unreadCount = notifState.unreadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand + the peeking eyes buddy (spec §23.16)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SFBrandLockup(markSize: 30, fontSize: 19),
            const Spacer(),
            HomePeekers(controller: _peekers),
          ],
        ),
        const SizedBox(height: 10),
        // Top Row: User Avatar/Name + Mood Chip + Notif Bell + SmartFit pill
        Row(
          children: [
            // Clickable Avatar
            GestureDetector(
              onTap: () => context.go(RoutePaths.profile),
              child: Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: context.sf.brandGradient,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.transparent,
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? SafeNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, width: 44, height: 44)
                          : Container(
                              color: context.cs.surfaceContainerLow,
                              child: Icon(Icons.person_rounded, color: context.sf.highlight, size: 24),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // User Greeting & Rank
            Expanded(
              child: GestureDetector(
                onTap: () => context.go(RoutePaths.profile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hey, $displayName!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineMd.copyWith(
                        color: context.cs.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      greeting(DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(color: context.sf.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            // Interactive Notification Bell
            GestureDetector(
              onTap: _showNotificationsSheet,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.cs.surfaceContainerLow,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.cs.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      notifState.isEnabled ? Icons.notifications_outlined : Icons.notifications_off_outlined,
                      color: notifState.isEnabled ? context.cs.onSurfaceVariant : context.cs.outline,
                      size: 21,
                    ),
                  ),
                  if (notifState.isEnabled && unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.hotPink),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Center(
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'SpaceGrotesk',
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic);
  }

  // ═══════════════════════════════════════════════════════════
  // BODY SCAN HERO CARD
  // ═══════════════════════════════════════════════════════════
  Widget _buildBodyScanCard(UserProfileModel? profile) {
    return TiltCard(
      child: GestureDetector(
        onTap: () => _startBodyScan(profile),
        child: Container(
          height: 280,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background Image
                SafeNetworkImage(
                  imageUrl:
                      'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?q=80&w=800&auto=format&fit=crop',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 280,
                ),

                // Gradient overlay
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),

                // Subtle purple gradient accent on the edges
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.sf.highlight.withValues(alpha: 0.15),
                          Colors.transparent,
                          AppColors.secondaryContainer.withValues(alpha: 0.10),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),
                ),

                // Content at the bottom
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Body Scan',
                              style: AppTextStyles.headlineLg.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 26,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Body type, size and skin tone in seconds',
                              style: AppTextStyles.bodySm.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Scan button: the brand neon, like every main action
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseCtrl.value * 0.08);
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(color: AppColors.neonGreen, shape: BoxShape.circle),
                          child: const Icon(Icons.accessibility_new_rounded, color: AppColors.ink900, size: 24),
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
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SPLINE-STYLE GLASS HOVER CARDS
  // ═══════════════════════════════════════════════════════════
  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: _glassFeatureCard(
            title: 'Virtual\nTry-On',
            subtitle: 'See it on you',
            icon: Icons.checkroom_rounded,
            imageUrl: AppImages.tryOnHero,
            // dark: deep green under white text, with a lime glow
            gradientColors: context.isDark
                ? const [Color(0xFF2B3A06), AppColors.neonLime]
                : [AppColors.greenDeep, AppColors.primary400],
            onTap: () {
              HapticFeedback.lightImpact();
              context.go(RoutePaths.tryOn);
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _glassFeatureCard(
            title: 'AI\nHairstyle',
            subtitle: 'Complete your look',
            icon: Icons.face_retouching_natural_rounded,
            imageUrl: AppImages.hairstyleHero,
            gradientColors: [AppColors.neonGreen, AppColors.primary400],
            onTap: () {
              HapticFeedback.lightImpact();
              context.go(RoutePaths.hairstyle);
            },
          ),
        ),
      ],
    );
  }

  Widget _glassFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String imageUrl,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return TiltCard(
      maxTiltDegrees: 10,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: gradientColors[0].withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 12)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 40, offset: const Offset(0, 20)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fashion photography background
                SafeNetworkImage(imageUrl: imageUrl),

                // Dark gradient overlay for readability
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.85),
                        gradientColors[0].withValues(alpha: 0.4),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),

                // Glassmorphic frosted overlay at the bottom
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white.withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: 'SpaceGrotesk',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Icon(icon, color: Colors.white, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Top-right glow orb (Spline-style)
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [gradientColors[1].withValues(alpha: 0.3), Colors.transparent]),
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
