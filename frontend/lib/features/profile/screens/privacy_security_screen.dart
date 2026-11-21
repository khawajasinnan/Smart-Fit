import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/chatbot/providers/chat_provider.dart';
import 'package:smartfit/features/profile/data/services/account_api_service.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/widgets/settings_widgets.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// Password, your data, deactivation and deletion (SFR-008, SRDS §4.2).
class PrivacySecurityScreen extends ConsumerStatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  ConsumerState<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends ConsumerState<PrivacySecurityScreen> {
  bool _busy = false;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? context.cs.error : null,
      ));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── password ──────────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    final formKey = GlobalKey<FormState>();
    final pass = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pass,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'New password'),
                validator: Validators.password,
              ),
              const SizedBox(height: AppSpace.sm),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
                validator: (v) => Validators.confirmPassword(v, pass.text),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'At least 8 characters with upper- and lower-case letters, a number and a symbol.',
                style: ctx.tt.bodySmall?.copyWith(color: ctx.sf.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newPassword = pass.text;
    pass.dispose();
    confirm.dispose();
    if (ok != true) return;
    await _run(() async {
      try {
        await ref.read(authNotifierProvider.notifier).changePassword(newPassword);
        _snack('Password changed 🔒');
      } catch (e) {
        _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    });
  }

  // ── your data ────────────────────────────────────────────────────────────

  Future<void> _showMyData() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;
    await _run(() async {
      final profile = ref.read(profileNotifierProvider(user.id)).valueOrNull;
      List<Map<String, dynamic>> sessions = const [];
      try {
        final list = await ref.read(chatRepositoryProvider).getSessions(user.id);
        sessions = [
          for (final s in list) {'title': s.title, 'created_at': s.createdAt.toIso8601String()},
        ];
      } catch (_) {}
      final data = {
        'account': {'id': user.id, 'email': user.email, 'name': user.fullName},
        'profile': profile?.toJson(),
        'chat_sessions': sessions,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
      };
      final text = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (ctx, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your SmartFit data', style: ctx.tt.titleLarge),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  'Everything SmartFit stores about you. Photos stay in private storage and are listed in your profile.',
                  style: ctx.tt.bodySmall?.copyWith(color: ctx.sf.textMuted),
                ),
                const SizedBox(height: AppSpace.md),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: ctx.sf.surfaceSunken, borderRadius: AppRadius.mdAll),
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: SelectableText(text, style: ctx.tt.bodySmall?.copyWith(fontFamily: 'monospace')),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy to clipboard'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Your data was copied.');
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> _clearChats() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;
    final ok = await _confirm(
      title: 'Clear chat history?',
      body: 'All your AI stylist conversations are deleted. Saved outfits in your wardrobe stay.',
      action: 'Clear history',
    );
    if (!ok) return;
    await _run(() async {
      try {
        await ref.read(chatRepositoryProvider).deleteAllSessions(user.id);
        ref.invalidate(chatNotifierProvider(user.id));
        _snack('Chat history cleared.');
      } catch (_) {
        _snack("Couldn't clear your chats. Check your connection and try again.", error: true);
      }
    });
  }

  // ── SFR-008 ──────────────────────────────────────────────────────────────

  Future<void> _deactivate() async {
    final ok = await _confirm(
      title: 'Deactivate your account?',
      body: "You'll be signed out on all your devices and your profile is hidden. Nothing is deleted: "
          'sign in again any time and choose Reactivate to pick up where you left off.',
      action: 'Deactivate',
      destructive: true,
    );
    if (!ok) return;
    await _run(() async {
      try {
        await ref.read(authNotifierProvider.notifier).deactivateAccount();
        if (mounted) context.go(RoutePaths.login);
      } catch (_) {
        _snack("Couldn't deactivate your account right now. Please try again later.", error: true);
      }
    });
  }

  Future<void> _delete() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: ctx.cs.error),
          title: const Text('Delete your account forever?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account, profile, photos, chats, wardrobe and feedback. '
                "It can't be undone.",
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: typed,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError),
              onPressed: typed.text.trim() == AccountApiService.confirmation ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true) return;
    await _run(() async {
      try {
        await ref.read(authNotifierProvider.notifier).deleteAccount(ref.read(accountApiServiceProvider));
        if (mounted) context.go(RoutePaths.login);
      } on Failure catch (f) {
        _snack(f.message, error: true);
      } catch (_) {
        _snack("Couldn't delete your account right now. Please try again later.", error: true);
      }
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return SFScaffold(
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxxl),
            children: [
              const SettingsPageHeader(title: 'Privacy & security', subtitle: 'Your password, data and account'),
              SettingsSection(
                title: 'Security',
                children: [
                  SettingsTile(
                    icon: Icons.password_rounded,
                    title: 'Change password',
                    subtitle: 'For signing in with your email',
                    onTap: _changePassword,
                  ),
                ],
              ),
              SettingsSection(
                title: 'Your data',
                index: 1,
                children: [
                  SettingsTile(
                    icon: Icons.download_rounded,
                    tint: context.sf.info,
                    title: 'View & copy my data',
                    subtitle: 'Your account, profile and chat sessions',
                    onTap: _showMyData,
                  ),
                  SettingsTile(
                    icon: Icons.forum_outlined,
                    tint: context.sf.warning,
                    title: 'Clear chat history',
                    subtitle: 'Delete all AI stylist conversations',
                    onTap: _clearChats,
                  ),
                ],
              ),
              SettingsSection(
                title: 'Your photos',
                index: 2,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Text(
                      'Photos you send in chat are kept in private storage. Your profile photo is stored under '
                      'your account and used by the app only. Photos are used for body analysis and virtual '
                      'try-on, are never shown to other users, and are deleted with your account.',
                      style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: 'Account',
                index: 3,
                children: [
                  SettingsTile(
                    icon: Icons.pause_circle_outline_rounded,
                    tint: context.sf.warning,
                    title: 'Deactivate account',
                    subtitle: 'Hide it for now; sign in again to come back',
                    onTap: _deactivate,
                  ),
                  SettingsTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    subtitle: 'Permanently remove your account and data',
                    destructive: true,
                    onTap: _delete,
                  ),
                ],
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: context.cs.scrim.withValues(alpha: 0.25),
                child: const Center(child: SFLoader()),
              ),
            ),
        ],
      ),
    );
  }
}
