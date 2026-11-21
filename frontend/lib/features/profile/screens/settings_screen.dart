import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/providers/theme_provider.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/screens/skin_tone_analyzer_screen.dart';
import 'package:smartfit/features/profile/widgets/settings_widgets.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// Profile tab: account, appearance, notifications and support (SFR-007, SFR-008).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingOut = false;
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? context.cs.error : null,
        ),
      );
  }

  Future<void> _setNotifications(bool value) async {
    HapticFeedback.lightImpact();
    final granted = await ref.read(notificationNotifierProvider.notifier).setEnabled(value);
    if (!value) {
      _snack('Notifications are off.');
    } else if (!granted) {
      _snack('Allow notifications for SmartFit in your phone settings to receive them.');
    } else {
      _snack("Notifications are on. We'll let you know when your looks are ready ✨");
    }
  }

  Future<void> _pickReminderTime(TimeOfDay current) async {
    final picked = await showTimePicker(context: context, initialTime: current, helpText: 'Daily style reminder');
    if (picked == null) return;
    await ref.read(notificationNotifierProvider.notifier).setReminderTime(picked);
    if (mounted) _snack('Reminder set for ${picked.format(context)} every day.');
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
      if (mounted) context.go(RoutePaths.login);
    } catch (_) {
      _snack("Couldn't log out. Check your connection and try again.", error: true);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  /// The skin tone analyzer; its result (shade + undertone) is saved to the profile.
  Future<void> _analyzeSkin(String userId, UserProfileModel? profile) async {
    final choice = await Navigator.of(context).push<SkinToneChoice>(
      MaterialPageRoute(builder: (_) => SkinToneAnalyzerScreen(profilePhotoUrl: profile?.photoUrl)),
    );
    if (choice == null || profile == null || !mounted) return;
    try {
      await ref
          .read(profileNotifierProvider(userId).notifier)
          .updateProfile(profile.copyWith(skinTone: choice.skinTone, skinUndertone: choice.undertone));
      _snack('Saved: ${choice.skinTone}${choice.undertone == null ? '' : ', ${choice.undertone} undertone'}.');
    } catch (_) {
      _snack("Couldn't save your skin tone. Please try again.", error: true);
    }
  }

  Future<void> _rename(String userId, UserProfileModel? profile, String currentName) async {
    _nameCtrl.text = currentName == 'Your profile' ? '' : currentName;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: _nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, _nameCtrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null) return;
    if (newName.length < 2) {
      _snack('Please enter your full name.', error: true);
      return;
    }
    final ok = await ref.read(authNotifierProvider.notifier).updateAccountName(newName);
    if (!ok) {
      _snack("Couldn't save your name. Please try again.", error: true);
      return;
    }
    if (profile != null) {
      try {
        await ref.read(profileNotifierProvider(userId).notifier).updateProfile(profile.copyWith(fullName: newName));
      } catch (_) {
        _snack("Couldn't save your name. Please try again.", error: true);
        return;
      }
    }
    _snack('Name updated ✨');
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authNotifierProvider).user;
    final userId = authUser?.id;
    final profile = userId == null ? null : ref.watch(profileNotifierProvider(userId)).valueOrNull;
    final photoUrl = profile?.photoUrl ?? authUser?.avatarUrl;
    final name = (profile?.fullName?.trim().isNotEmpty ?? false)
        ? profile!.fullName!.trim()
        : (authUser?.fullName?.trim().isNotEmpty ?? false)
        ? authUser!.fullName!.trim()
        : 'Your profile';
    final email = authUser?.email ?? '';
    final isAdmin = email.toLowerCase() == ApiEndpoints.adminEmail.toLowerCase();
    final themeMode = ref.watch(themeProvider);
    final notif = ref.watch(notificationNotifierProvider);

    return SFScaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.md,
          AppSpace.gutter,
          MediaQuery.paddingOf(context).bottom + AppSpace.xl,
        ),
        children: [
          SFEntrance(
            child: Row(
              children: [
                Expanded(
                  child: Semantics(header: true, child: Text('Profile', style: context.tt.headlineLarge)),
                ),
                const SFLogoMark(size: 34),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          SFEntrance(
            index: 1,
            child: _ProfileCard(
              name: name,
              email: email,
              photoUrl: photoUrl,
              onEdit: () => context.push(RoutePaths.profileSetup),
              onRename: userId == null ? null : () => _rename(userId, profile, name),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SFEntrance(
            index: 2,
            child: _StyleProfileCard(profile: profile, onEdit: () => context.push(RoutePaths.profileSetup)),
          ),
          const SizedBox(height: AppSpace.md),
          SettingsSection(
            title: 'Your colours',
            index: 3,
            children: [
              SettingsTile(
                icon: Icons.face_retouching_natural_rounded,
                tint: context.sf.accentText,
                title: 'Skin tone analyzer',
                subtitle: 'Your shade, undertone and best colours',
                onTap: userId == null ? null : () => _analyzeSkin(userId, profile),
              ),
            ],
          ),
          SettingsSection(
            title: 'Appearance',
            index: 3,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.phone_android_rounded),
                        label: Text('Auto'),
                      ),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      HapticFeedback.selectionClick();
                      ref.read(themeProvider.notifier).setThemeMode(s.first);
                    },
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Notifications',
            index: 4,
            children: [
              SettingsTile(
                icon: Icons.notifications_active_outlined,
                tint: context.sf.accentText,
                title: 'Notifications',
                subtitle: 'Outfits ready, body analysis done, try-on results',
                trailing: Switch.adaptive(value: notif.isEnabled, onChanged: _setNotifications),
                onTap: () => _setNotifications(!notif.isEnabled),
              ),
              SettingsTile(
                icon: Icons.auto_awesome_rounded,
                tint: context.cs.primary,
                title: "Zayn's fun, roasts & chill",
                subtitle: notif.funEnabled ? '3 a day. Your 1-tap answers train your picks.' : 'Off',
                trailing: Switch.adaptive(
                  value: notif.funEnabled && notif.isEnabled,
                  onChanged: notif.isEnabled
                      ? (v) => ref.read(notificationNotifierProvider.notifier).setFunEnabled(v)
                      : null,
                ),
              ),
              SettingsTile(
                icon: Icons.wb_sunny_outlined,
                tint: context.sf.warning,
                title: 'Daily style reminder',
                subtitle: !notif.dailyReminder
                    ? 'Off'
                    : notif.funEnabled
                    ? "Zayn's morning nudge covers it"
                    : 'Every day at ${notif.reminderTime.format(context)}',
                trailing: Switch.adaptive(
                  value: notif.dailyReminder && notif.isEnabled,
                  onChanged: notif.isEnabled
                      ? (v) => ref.read(notificationNotifierProvider.notifier).setDailyReminder(v)
                      : null,
                ),
              ),
              if ((notif.dailyReminder || notif.funEnabled) && notif.isEnabled)
                SettingsTile(
                  icon: Icons.schedule_rounded,
                  title: 'Morning time',
                  subtitle: notif.reminderTime.format(context),
                  onTap: () => _pickReminderTime(notif.reminderTime),
                ),
            ],
          ),
          if (notif.isEnabled && notif.permissionDenied)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.lg),
              child: Semantics(
                button: true,
                label: 'Open notification settings',
                child: GestureDetector(
                  onTap: () => NotificationService.instance.openSystemSettings(),
                  child: const NoticeBanner(
                    tone: NoticeTone.warning,
                    title: 'Notifications are blocked',
                    message: 'Your phone is blocking SmartFit notifications. Tap here to allow them.',
                  ),
                ),
              ),
            ),
          SettingsSection(
            title: 'Account',
            index: 5,
            children: [
              SettingsTile(
                icon: Icons.lock_outline_rounded,
                tint: context.sf.success,
                title: 'Privacy & security',
                subtitle: 'Password, your data, deactivate or delete',
                onTap: () => context.push(RoutePaths.privacy),
              ),
              SettingsTile(
                icon: Icons.help_outline_rounded,
                tint: context.sf.info,
                title: 'Help & support',
                subtitle: 'FAQs, contact us, report a bug',
                onTap: () => context.push(RoutePaths.help),
              ),
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'About SmartFit',
                subtitle: 'Version, credits and licences',
                onTap: () => context.push(RoutePaths.about),
              ),
              if (isAdmin)
                SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  tint: context.sf.accentText,
                  title: 'Admin tools',
                  subtitle: 'Quick moderation on the phone',
                  onTap: () => context.push(RoutePaths.admin),
                ),
            ],
          ),
          SFEntrance(
            index: 6,
            child: SFButton(
              label: _signingOut ? 'Logging out…' : 'Log out',
              icon: Icons.logout_rounded,
              variant: SFButtonVariant.danger,
              isLoading: _signingOut,
              onPressed: _signingOut ? null : _logout,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const Center(child: SFTagline(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Photo, name, email and the edit actions.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.onEdit,
    required this.onRename,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final VoidCallback onEdit;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    return SFGlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.hotPink),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: context.cs.surface,
                  child: ClipOval(
                    child: hasPhoto
                        ? SafeNetworkImage(imageUrl: photoUrl!.trim(), width: 64, height: 64, fit: BoxFit.cover)
                        : Icon(Icons.person_rounded, size: 32, color: context.cs.primary),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: context.tt.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onRename != null)
                IconButton(
                  tooltip: 'Change your name',
                  onPressed: onRename,
                  icon: Icon(Icons.edit_outlined, color: context.sf.textMuted),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          SFButton(label: 'Edit profile', icon: Icons.tune_rounded, height: 48, onPressed: onEdit),
        ],
      ),
    );
  }
}

/// What SmartFit knows about the user's body and taste: the inputs behind
/// every recommendation, look score and try-on size check.
class _StyleProfileCard extends StatelessWidget {
  const _StyleProfileCard({required this.profile, required this.onEdit});

  final UserProfileModel? profile;
  final VoidCallback onEdit;

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// "Medium · warm undertone" once the analyzer (or the user) set the undertone.
  static String? _skinWithUndertone(UserProfileModel? p) {
    final tone = p?.skinTone;
    if (tone == null || tone.trim().isEmpty) return null;
    final under = p?.skinUndertone;
    return (under == null || under.isEmpty) ? tone : '$tone · $under undertone';
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    String? num(double? v, String unit) => (v == null || v <= 0) ? null : '${v.round()} $unit';
    final size = [num(p?.heightCm, 'cm'), num(p?.weightKg, 'kg')].whereType<String>().join(' · ');
    final facts = <(IconData, String, String?)>[
      (Icons.wc_rounded, 'Gender', p?.gender == null || p!.gender!.trim().isEmpty ? null : _cap(p.gender!.trim())),
      (Icons.straighten_rounded, 'Height · weight', size.isEmpty ? null : size),
      (Icons.accessibility_new_rounded, 'Body type', p?.bodyType),
      (Icons.palette_outlined, 'Skin tone', _skinWithUndertone(p)),
    ];
    final known =
        facts.where((f) => f.$3 != null && f.$3!.trim().isNotEmpty).length +
        ((p?.stylePreferences.isNotEmpty ?? false) ? 1 : 0);
    final total = facts.length + 1;
    final swatch = p?.skinTone == null ? null : AppColors.skinToneSwatches[p!.skinTone];

    return SFGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your style profile', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('$known/$total', style: context.tt.labelMedium?.copyWith(color: context.sf.accentText)),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          // its own node: otherwise the whole card was read as one progress bar (E2E run, 20 Nov 2026)
          Semantics(
            container: true,
            child: ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: LinearProgressIndicator(
                value: known / total,
                minHeight: 6,
                backgroundColor: context.sf.surfaceSunken,
                color: AppColors.neonGreen,
                semanticsLabel: 'Style profile filled in', // the value is read as a percentage (must be a number)
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            known == total
                ? 'Complete: every pick, look score and size check uses this.'
                : 'The more you fill in, the better your picks and size checks.',
            style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          for (final (icon, label, value) in facts)
            _FactRow(
              icon: icon,
              label: label,
              value: value,
              leading: label == 'Skin tone' && swatch != null
                  ? Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.sf.divider),
                      ),
                    )
                  : null,
              onAdd: onEdit,
            ),
          const SizedBox(height: AppSpace.xs),
          Text('Styles you love', style: context.tt.labelMedium?.copyWith(color: context.sf.textMuted)),
          const SizedBox(height: AppSpace.xs),
          if (p?.stylePreferences.isNotEmpty ?? false)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in p!.stylePreferences.take(8))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.hotPink.withValues(alpha: 0.10),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(s, style: context.tt.labelMedium?.copyWith(color: context.sf.accentText)),
                  ),
              ],
            )
          else
            TextButton(onPressed: onEdit, child: const Text('Add the styles you love')),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, required this.value, required this.onAdd, this.leading});

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onAdd;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.sf.textMuted),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(label, style: context.tt.bodyMedium)),
          if (has) ...[
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(value!, style: context.tt.titleSmall),
          ] else
            InkWell(
              onTap: onAdd,
              borderRadius: AppRadius.pillAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('Add', style: context.tt.labelLarge?.copyWith(color: context.sf.accentText)),
              ),
            ),
        ],
      ),
    );
  }
}
