import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';

/// Shown when the signed-in user's profile couldn't be loaded, so the app
/// can't yet tell whether onboarding is complete (SFR-006 / SFR-013).
/// Retrying reloads it; the router then moves the user on by itself.
class ProfileGateScreen extends ConsumerWidget {
  const ProfileGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sf = context.sf;
    final user = ref.watch(currentUserProvider);
    final loading = user != null && ref.watch(profileNotifierProvider(user.id)).isLoading;
    final email = user?.email;

    return SFScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.gutter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SFEntrance(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: sf.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      boxShadow: AppShadows.lg,
                    ),
                    child: Icon(Icons.cloud_off_rounded, size: 44, color: context.sf.onBrand),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                SFEntrance(
                  index: 1,
                  child: Semantics(
                    header: true,
                    child: Text(
                      "We couldn't load your profile",
                      textAlign: TextAlign.center,
                      style: context.tt.headlineLarge,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                SFEntrance(
                  index: 2,
                  child: Text(
                    'Check your internet connection and try again — we need it to know '
                    'whether your style profile is finished.',
                    textAlign: TextAlign.center,
                    style: context.tt.bodyLarge?.copyWith(color: sf.textMuted),
                  ),
                ),
                const SizedBox(height: AppSpace.xxl),
                SFEntrance(
                  index: 3,
                  child: SFButton(
                    label: AppStrings.tryAgain,
                    icon: Icons.refresh_rounded,
                    isLoading: loading,
                    onPressed: user == null ? null : () => ref.read(profileNotifierProvider(user.id).notifier).loadProfile(),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                SFEntrance(
                  index: 4,
                  child: TextButton(
                    onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
                    child: const Text('Log out'),
                  ),
                ),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('Signed in as $email', textAlign: TextAlign.center, style: context.tt.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
