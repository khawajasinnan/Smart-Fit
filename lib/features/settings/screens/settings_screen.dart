import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isLoading = false;
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final enabled = ref.read(notificationNotifierProvider).isEnabled;
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      });
    }
  }

  Future<void> _setNotifications(bool value) async {
    HapticFeedback.lightImpact();
    await ref.read(notificationNotifierProvider.notifier).setEnabled(value);
    if (mounted) {
      setState(() => _notificationsEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Notifications enabled! You will receive daily trends & fit check alerts ✨'
                : 'Notifications paused.',
            style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600),
          ),
          backgroundColor: value ? AppColors.primary : AppColors.onSurfaceVariant,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _setDarkMode(bool value) async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode_enabled', value);
    if (mounted) setState(() => _darkModeEnabled = value);
  }

  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log Out', style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out?', style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
      if (mounted) context.go(RoutePaths.login);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditNameDialog(String userId, UserProfileModel? profile, String currentName) async {
    _nameCtrl.text = currentName;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Edit Name', style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Your name',
            filled: true,
            fillColor: AppColors.secondaryFixed.withValues(alpha: 0.45),
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.secondaryContainer, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, _nameCtrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.length < 2) {
      if (newName != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your full name.')),
        );
      }
      return;
    }
    final authUpdated = await ref.read(authNotifierProvider.notifier).updateAccountName(newName);
    if (!authUpdated) return;
    if (profile != null) {
      await ref.read(profileNotifierProvider(userId).notifier).updateProfile(profile.copyWith(fullName: newName));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Name updated successfully! ✨'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authNotifierProvider).user;
    final userId = authUser?.id;
    final profileAsync = userId == null
        ? const AsyncValue<UserProfileModel?>.data(null)
        : ref.watch(profileNotifierProvider(userId));
    final profile = profileAsync.valueOrNull;
    final photoUrl = profile?.photoUrl ?? authUser?.avatarUrl;
    final currentName = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : authUser?.fullName?.trim().isNotEmpty == true
            ? authUser!.fullName!.trim()
            : 'Your Profile';
    final email = authUser?.email ?? '';
    final isAdmin = email.toLowerCase() == ApiEndpoints.adminEmail.toLowerCase();

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Ambient Orbs ──
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 60, left: -80,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.secondaryFixedDim.withValues(alpha: 0.10),
                  Colors.transparent,
                ]),
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

          // ── Main Content ──
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Custom App Bar ──
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (context.canPop()) { context.pop(); } else { context.go(RoutePaths.home); }
                        },
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text('Settings', style: AppTextStyles.headlineMd.copyWith(
                          fontWeight: FontWeight.w800, color: AppColors.primary,
                        )),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text('SmartFit', style: AppTextStyles.labelSm.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700,
                            )),
                          ],
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1),
                  const SizedBox(height: 28),

                  // ═══════════════════════════════════
                  // PROFILE HERO CARD
                  // ═══════════════════════════════════
                  _buildProfileHeroCard(photoUrl, currentName, email, userId, profile)
                      .animate().fadeIn(duration: 600.ms).slideY(begin: 0.06),
                  const SizedBox(height: 28),

                  // ═══════════════════════════════════
                  // PREFERENCES SECTION
                  // ═══════════════════════════════════
                  _sectionLabel('PREFERENCES', Icons.tune_rounded),
                  const SizedBox(height: 14),
                  _glassSettingTile(
                    icon: Icons.notifications_active_outlined,
                    iconGradient: [const Color(0xFFFF2E93), const Color(0xFFFF6FB5)],
                    title: 'Outfit Notifications',
                    subtitle: 'Alert when recommendations are ready',
                    trailing: _buildCustomSwitch(_notificationsEnabled, _setNotifications),
                    onTap: () => _setNotifications(!_notificationsEnabled),
                    delay: 0,
                  ),
                  _glassSettingTile(
                    icon: Icons.dark_mode_outlined,
                    iconGradient: [const Color(0xFF6C4CE0), const Color(0xFF9B85F0)],
                    title: 'Dark Mode',
                    subtitle: 'Coming soon — toggle dark theme',
                    trailing: _buildCustomSwitch(_darkModeEnabled, _setDarkMode),
                    onTap: () => _setDarkMode(!_darkModeEnabled),
                    delay: 50,
                  ),
                  _glassSettingTile(
                    icon: Icons.language_rounded,
                    iconGradient: [const Color(0xFF4C9BE0), const Color(0xFF6CB8FF)],
                    title: 'Language',
                    subtitle: 'English (US)',
                    onTap: () {},
                    delay: 100,
                  ),
                  const SizedBox(height: 24),

                  // ═══════════════════════════════════
                  // ACCOUNT SECTION
                  // ═══════════════════════════════════
                  _sectionLabel('ACCOUNT', Icons.person_outline_rounded),
                  const SizedBox(height: 14),
                  _glassSettingTile(
                    icon: Icons.lock_outline_rounded,
                    iconGradient: [const Color(0xFF2FD98A), const Color(0xFF4AE8A0)],
                    title: 'Privacy & Security',
                    subtitle: 'Manage your data and permissions',
                    onTap: () {},
                    delay: 0,
                  ),
                  _glassSettingTile(
                    icon: Icons.help_outline_rounded,
                    iconGradient: [const Color(0xFFF5A524), const Color(0xFFFFBE4D)],
                    title: 'Help & Support',
                    subtitle: 'FAQs, contact us, report a bug',
                    onTap: () {},
                    delay: 50,
                  ),
                  _glassSettingTile(
                    icon: Icons.info_outline_rounded,
                    iconGradient: [const Color(0xFF8B85A0), const Color(0xFFABA5BF)],
                    title: 'About SmartFit',
                    subtitle: 'Version 1.0.0 • Built with ❤️',
                    onTap: () {},
                    delay: 100,
                  ),
                  if (isAdmin)
                    _glassSettingTile(
                      icon: Icons.admin_panel_settings_outlined,
                      iconGradient: [const Color(0xFFFF2E93), const Color(0xFF6C4CE0)],
                      title: 'Admin Panel',
                      subtitle: 'Manage users, bans, analytics',
                      onTap: () => context.push(RoutePaths.admin),
                      delay: 150,
                    ),
                  const SizedBox(height: 32),

                  // ═══════════════════════════════════
                  // LOGOUT BUTTON
                  // ═══════════════════════════════════
                  _buildLogoutButton()
                      .animate().fadeIn(duration: 500.ms, delay: 400.ms).slideY(begin: 0.1),
                  const SizedBox(height: 20),

                  // ── App version footer ──
                  Center(
                    child: Text(
                      'SmartFit v1.0.0 • Made in Pakistan 🇵🇰',
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 12,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PROFILE HERO CARD — gradient border + glass interior
  // ═══════════════════════════════════════════════════════════
  Widget _buildProfileHeroCard(
    String? photoUrl, String name, String email,
    String? userId, UserProfileModel? profile,
  ) {
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF6C4CE0), Color(0xFFFF2E93), Color(0xFF9B85F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                // Profile avatar with gradient ring
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C4CE0), Color(0xFFFF2E93)],
                    ),
                  ),
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasPhoto
                        ? SafeNetworkImage(imageUrl: photoUrl.trim(), fit: BoxFit.cover, width: 64, height: 64)
                        : const Icon(Icons.person, color: AppColors.primary, size: 32),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(
                        fontFamily: 'SpaceGrotesk', fontSize: 20,
                        fontWeight: FontWeight.w800, color: AppColors.onSurface,
                      )),
                      const SizedBox(height: 2),
                      Text(email, style: TextStyle(
                        fontFamily: 'Inter', fontSize: 13,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                      )),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          _miniActionChip('Edit Profile', Icons.edit_outlined,
                            () => context.push(RoutePaths.profileSetup)),
                          if (userId != null)
                            _miniActionChip('Rename', Icons.badge_outlined,
                              () => _showEditNameDialog(userId, profile, name)),
                        ],
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

  Widget _miniActionChip(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(
              fontFamily: 'Inter', fontSize: 12,
              fontWeight: FontWeight.w600, color: AppColors.primary,
            )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION LABEL
  // ═══════════════════════════════════════════════════════════
  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(
          fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
        )),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  // ═══════════════════════════════════════════════════════════
  // GLASS SETTING TILE
  // ═══════════════════════════════════════════════════════════
  Widget _glassSettingTile({
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
    int delay = 0,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C4CE0).withValues(alpha: 0.04),
              blurRadius: 16, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Gradient icon container
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: iconGradient,
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: iconGradient[0].withValues(alpha: 0.25),
                    blurRadius: 8, offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 15,
                    fontWeight: FontWeight.w600, color: AppColors.onSurface,
                  )),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                    )),
                  ],
                ],
              ),
            ),
            trailing ?? Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
              size: 22,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: Duration(milliseconds: 200 + delay)).slideX(begin: 0.04);
  }

  // ═══════════════════════════════════════════════════════════
  // CUSTOM SWITCH
  // ═══════════════════════════════════════════════════════════
  Widget _buildCustomSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 52, height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: value
              ? const LinearGradient(colors: [Color(0xFF6C4CE0), Color(0xFFFF2E93)])
              : null,
          color: value ? null : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4, offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LOGOUT BUTTON — gradient border danger style
  // ═══════════════════════════════════════════════════════════
  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleLogout,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.error.withValues(alpha: 0.06),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: _isLoading
            ? const Center(
                child: SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text('Log Out', style: TextStyle(
                    fontFamily: 'SpaceGrotesk', fontSize: 16,
                    fontWeight: FontWeight.w700, color: AppColors.error,
                  )),
                ],
              ),
      ),
    );
  }
}
