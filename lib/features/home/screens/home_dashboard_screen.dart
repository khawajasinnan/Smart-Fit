import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/camera_preview_dialog.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/core/widgets/sf_bottom_nav_bar.dart';
import 'package:smartfit/core/widgets/sf_transition_loader.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/cv_analysis_result.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});
  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  final int _navIndex = 0;
  int _quoteShuffleIndex = 0;
  String _dailyMood = 'Chill Streetwear';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  void _shuffleQuote() {
    HapticFeedback.lightImpact();
    setState(() {
      _quoteShuffleIndex = (_quoteShuffleIndex + 1) % _quotes.length;
    });
  }

  void _openMoodSelector() {
    HapticFeedback.selectionClick();
    final moods = [
      'Chill Streetwear',
      'Cyber Y2K',
      'Soft Glam & Coquette',
      'Desi Fusion',
      'Retro Blokecore',
      'Clean Luxury',
      'Baggy Skater Core',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Select Today\'s Outfit Mood',
              style: AppTextStyles.headlineMd.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sets the style tone for your recommendations & fits.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: moods.map((m) {
                final isSelected = _dailyMood == m;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _dailyMood = m);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Outfit vibe set to $m!'),
                        backgroundColor: AppColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF2E93) : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF2E93) : Colors.black12,
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF2E93).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      m,
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }



  void _startBodyScan(UserProfileModel? profile) async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CameraPreviewDialog(showPoseOverlay: true),
    );

    if (bytes == null || !mounted) return;

    // Show analyzing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 20),
              Text(
                'Analyzing Body Scan...',
                style: AppTextStyles.headlineMd.copyWith(
                  color: AppColors.onSurface,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'MediaPipe AI is extracting 33 body landmarks, body proportions, and size estimates.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final base64Image = base64Encode(bytes);
      final service = CvAnalysisApiService();
      final result = await service.analyzeBody(
        imageBase64: base64Image,
        gender: profile?.gender,
        heightCm: profile?.heightCm,
        weightKg: profile?.weightKg,
        profile: profile,
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      if (result.success) {
        _showCvResultsSheet(result, profile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'CV analysis failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Body scan error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showCvResultsSheet(CvAnalysisResult result, UserProfileModel? profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.15),
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
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CV Body Analysis',
                        style: AppTextStyles.headlineMd.copyWith(
                          color: AppColors.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'MediaPipe 33-Landmark Pose Detection',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.primary,
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
                    value: result.estimatedChestCm != null
                        ? '${result.estimatedChestCm!.toStringAsFixed(1)} cm'
                        : '--',
                    subtitle: 'Circumference',
                    icon: Icons.checkroom_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _cvMetricCard(
                    title: 'Waist Estimate',
                    value: result.estimatedWaistCm != null
                        ? '${result.estimatedWaistCm!.toStringAsFixed(1)} cm'
                        : '--',
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
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
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
                              color: AppColors.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            result.skinTone!.fitzpatrickType,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
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
                onPressed: () {
                  Navigator.pop(ctx);
                  if (profile != null) {
                    final updated = profile.copyWith(
                      bodyType: result.bodyShape ?? profile.bodyType,
                      chestCm: result.estimatedChestCm ?? profile.chestCm,
                      waistCm: result.estimatedWaistCm ?? profile.waistCm,
                      hipCm: result.estimatedHipCm ?? profile.hipCm,
                      skinTone: result.skinTone?.toneLabel ?? profile.skinTone,
                    );
                    ref
                        .read(profileNotifierProvider(profile.id).notifier)
                        .updateProfile(updated);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Profile updated with CV scan measurements! ✨'),
                        backgroundColor: AppColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.all(20),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                label: const Text(
                  'Apply Measurements to Profile',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
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
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
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
              color: AppColors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.primary,
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final currentNotifState = ref.watch(notificationNotifierProvider);
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF6C4CE0), Color(0xFFFF2E93)],
                        ).createShader(bounds),
                        child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text('Notifications', style: AppTextStyles.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                      const Spacer(),
                      if (currentNotifState.isEnabled && currentNotifState.unreadCount > 0)
                        TextButton(
                          onPressed: () {
                            ref.read(notificationNotifierProvider.notifier).markAllAsRead();
                          },
                          child: const Text(
                            'Mark all read',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF2E93),
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
                                color: const Color(0xFFFF2E93).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_off_outlined,
                                size: 32,
                                color: Color(0xFFFF2E93),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Notifications Disabled in Settings 🔕',
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enable notifications from the Settings page to get live style alerts, Gen-Z trend drops, and virtual try-on reminders on your app.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                height: 1.4,
                                color: AppColors.onSurfaceVariant.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push(RoutePaths.settings);
                              },
                              icon: const Icon(Icons.settings_outlined, size: 18),
                              label: const Text(
                                'Open Settings',
                                style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
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
                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
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
                              context.push(RoutePaths.chat);
                            } else if (item.category == 'chat') {
                              Navigator.pop(ctx);
                              context.push(RoutePaths.chat);
                            } else if (item.category == 'wardrobe') {
                              Navigator.pop(ctx);
                              context.push(RoutePaths.wardrobe);
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
        color: isNew ? const Color(0xFF6C4CE0).withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isNew ? const Color(0xFF6C4CE0).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isNew
                    ? [const Color(0xFF6C4CE0), const Color(0xFFFF2E93)]
                    : [AppColors.onSurfaceVariant.withValues(alpha: 0.1), AppColors.onSurfaceVariant.withValues(alpha: 0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isNew ? Colors.white : AppColors.onSurfaceVariant, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontFamily: 'Inter', fontSize: 14,
                  fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.onSurface,
                )),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(
                  fontFamily: 'Inter', fontSize: 12,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.3,
                )),
                const SizedBox(height: 6),
                Text(time, style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isNew ? const Color(0xFF6C4CE0) : AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                )),
              ],
            ),
          ),
          if (isNew)
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)]),
              ),
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
      backgroundColor: AppColors.background,
      extendBody: true,
      bottomNavigationBar: SFBottomNavBar(currentIndex: _navIndex),
      body: Stack(
        children: [
          // ── Ambient Background Orbs ──
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondaryFixedDim.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Pink Clothing Icons Low-Opacity Background ──
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.055,
              color: Color(0xFFFF2E93),
            ),
          ),

          // ── Main Scrollable Content ──
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: 120,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══════════════════════════════════════
                  // HEADER: Welcome + Mood + Notification + Search
                  // ═══════════════════════════════════════
                  _buildHeader(displayName, photoUrl),
                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // INSPIRATION QUOTE CARD (REDESIGNED CHIC CARD)
                  // ═══════════════════════════════════════
                  _buildInspirationCard(user?.id)
                      .animate()
                      .fadeIn(duration: 650.ms)
                      .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                  const SizedBox(height: 24),

                  // ═══════════════════════════════════════
                  // BODY SCAN HERO CARD
                  // ═══════════════════════════════════════
                  _buildBodyScanCard(profile)
                      .animate()
                      .fadeIn(duration: 700.ms, delay: 150.ms)
                      .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                  const SizedBox(height: 24),

                  // ═══════════════════════════════════════
                  // ACTION BUTTONS ROW
                  // ═══════════════════════════════════════
                  _buildActionButtonsRow()
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 250.ms)
                      .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                ],
              ),
            ),
          ),
        ],
      ),

    );
  }

  // ═══════════════════════════════════════════════════════════
  // DYNAMIC QUOTES SYSTEM — different quote per user per day + shuffle
  // ═══════════════════════════════════════════════════════════
  static const _quotes = [
    {'text': 'Style is a way to say who you are without having to speak.', 'author': 'Rachel Zoe'},
    {'text': 'Fashion is the armor to survive the reality of everyday life.', 'author': 'Bill Cunningham'},
    {'text': 'In a world full of trends, remain a classic.', 'author': 'SmartFit'},
    {'text': 'Dress how you want to be addressed.', 'author': 'Fashion Motto'},
    {'text': 'Your culture is your crown — wear it with pride.', 'author': 'SmartFit'},
    {'text': 'Elegance is when the inside is as beautiful as the outside.', 'author': 'Coco Chanel'},
    {'text': 'Life is too short to wear boring clothes.', 'author': 'Streetwear Codex'},
    {'text': 'Be yourself; everyone else is already taken.', 'author': 'Oscar Wilde'},
    {'text': 'Fashion is about dressing according to what\'s fashionable. Style is more about being yourself.', 'author': 'Oscar de la Renta'},
    {'text': 'What you wear is how you present yourself to the world.', 'author': 'Miuccia Prada'},
    {'text': 'Clothes mean nothing until someone lives in them.', 'author': 'Marc Jacobs'},
    {'text': 'Fashion fades, only style remains the same.', 'author': 'Coco Chanel'},
    {'text': 'Simplicity is the keynote of all true elegance.', 'author': 'Coco Chanel'},
    {'text': 'The best color in the whole world is the one that looks good on you.', 'author': 'Coco Chanel'},
    {'text': 'People will stare. Make it worth their while.', 'author': 'Harry Winston'},
    {'text': 'You can have anything you want if you dress for it.', 'author': 'Edith Head'},
    {'text': 'Style is knowing who you are and what you want to say.', 'author': 'Orson Welles'},
    {'text': 'Fashion is what you buy; style is what you do with it.', 'author': 'SmartFit'},
    {'text': 'The joy of dressing is an art.', 'author': 'John Galliano'},
    {'text': 'A man should look as if he has bought his clothes with intelligence.', 'author': 'Hardy Amies'},
  ];

  Map<String, String> _getQuoteForUser(String? userId) {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final hash = (userId?.hashCode ?? 0).abs();
    final index = (hash + dayOfYear + _quoteShuffleIndex) % _quotes.length;
    return {'text': _quotes[index]['text']!, 'author': _quotes[index]['author']!};
  }

  // ═══════════════════════════════════════════════════════════
  // INTERACTIVE HEADER SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildHeader(String displayName, String? photoUrl) {
    final notifState = ref.watch(notificationNotifierProvider);
    final unreadCount = notifState.unreadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: User Avatar/Name + Mood Chip + Notif Bell + SmartFit pill
        Row(
          children: [
            // Clickable Avatar
            GestureDetector(
              onTap: () => context.push(RoutePaths.settings),
              child: Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E93).withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? SafeNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              width: 44,
                              height: 44,
                            )
                          : Container(
                              color: AppColors.surfaceContainerLow,
                              child: const Icon(
                                Icons.person_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
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
                onTap: () => context.push(RoutePaths.settings),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hey, $displayName!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Interactive Mood Selector Pill
            GestureDetector(
              onTap: _openMoodSelector,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFF2E93).withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.palette_outlined,
                      size: 15,
                      color: Color(0xFFFF2E93),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        _dailyMood,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF2E93),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Color(0xFFFF2E93),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
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
                      color: AppColors.surfaceContainerLow,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      notifState.isEnabled
                          ? Icons.notifications_outlined
                          : Icons.notifications_off_outlined,
                      color: notifState.isEnabled
                          ? AppColors.onSurfaceVariant
                          : AppColors.outline,
                      size: 21,
                    ),
                  ),
                  if (notifState.isEnabled && unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF2E93), Color(0xFF6C4CE0)],
                          ),
                        ),
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
  // LUXURY-EDITORIAL QUOTES WIDGET (HAUTE COUTURE GEN-Z CARD)
  // ═══════════════════════════════════════════════════════════
  Widget _buildInspirationCard(String? userId) {
    final quote = _getQuoteForUser(userId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.95),
                const Color(0xFFFFF6FA).withValues(alpha: 0.92),
                Colors.white.withValues(alpha: 0.94),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFFF2E93).withValues(alpha: 0.22),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2E93).withValues(alpha: 0.10),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: const Color(0xFF6C4CE0).withValues(alpha: 0.08),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Stylized Haute-Couture Watermark in the Top-Right
              Positioned(
                top: -14,
                right: 18,
                child: Text(
                  '“',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 110,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: const Color(0xFFFF2E93).withValues(alpha: 0.07),
                  ),
                ),
              ),

              // Card Inner Padding & Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: Capsule Pill + Shuffle & Copy
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF2E93), Color(0xFF8A2BE2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF2E93).withValues(alpha: 0.28),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'DAILY STYLE INSPIRATION',
                                style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // Interactive Shuffle Button with Haptics
                        GestureDetector(
                          onTap: _shuffleQuote,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF6C4CE0).withValues(alpha: 0.22),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C4CE0).withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.autorenew_rounded,
                                  size: 14,
                                  color: Color(0xFF6C4CE0),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Shuffle',
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6C4CE0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Interactive Copy Button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Clipboard.setData(
                              ClipboardData(text: '"${quote['text']}" — ${quote['author']}'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Quote copied to clipboard! ✨',
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                backgroundColor: const Color(0xFF1E1425),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.10),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Quote Text
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '“',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFF2E93),
                            height: 0.85,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            quote['text']!,
                            style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              height: 1.42,
                              letterSpacing: -0.2,
                              color: Color(0xFF1B1425),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Author Footer Row with Jeweled Divider
                    if (quote['author']!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const SizedBox(width: 22),
                          Container(
                            width: 22,
                            height: 2.5,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF2E93), Color(0xFF8A2BE2)],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            quote['author']!,
                            style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6C4CE0),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'SmartFit Couture',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BODY SCAN HERO CARD
  // ═══════════════════════════════════════════════════════════
  Widget _buildBodyScanCard(UserProfileModel? profile) {
    return GestureDetector(
      onTap: () => _startBodyScan(profile),
      child: Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.12),
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
                        AppColors.primary.withValues(alpha: 0.15),
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
                            'Get your 3D digital twin in seconds',
                            style: AppTextStyles.bodySm.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Yellow Scan Button matching the stitch design exactly
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, child) {
                        final scale = 1.0 + (_pulseCtrl.value * 0.08);
                        return Transform.scale(
                          scale: scale,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFEA00), // Vibrant yellow
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.accessibility_new_rounded,
                          color: Colors.black,
                          size: 24,
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
            imagePath: 'assets/images/backgrounds/fashion_hero_tryon.png',
            gradientColors: [
              const Color(0xFF6C4CE0),
              const Color(0xFF9B85F0),
            ],
            onTap: () {
              HapticFeedback.lightImpact();
              SFNavHelper.navigateWithLoader(
                context,
                RoutePaths.tryOn,
                title: 'Virtual Try-On',
                subtitle: 'Calibrating high-precision fitting room...',
              );
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _glassFeatureCard(
            title: 'AI\nHairstyle',
            subtitle: 'Complete your look',
            icon: Icons.face_retouching_natural_rounded,
            imagePath: 'assets/images/backgrounds/fashion_hero_hair.png',
            gradientColors: [
              const Color(0xFFFF2E93),
              const Color(0xFFFF6FB5),
            ],
            onTap: () {
              HapticFeedback.lightImpact();
              SFNavHelper.navigateWithLoader(
                context,
                RoutePaths.hairstyle,
                title: 'AI Hairstyle Studio',
                subtitle: 'Generating hair & facial aesthetics...',
              );
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
    required String imagePath,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.20),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fashion photography background
              Image.asset(
                imagePath,
                fit: BoxFit.cover,
              ),

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
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
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
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 20,
                            ),
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
                    gradient: RadialGradient(
                      colors: [
                        gradientColors[1].withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
