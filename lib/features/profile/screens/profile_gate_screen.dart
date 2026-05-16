import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/widgets/sf_button.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';

class ProfileGateScreen extends ConsumerWidget {
  const ProfileGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go(RoutePaths.login),
      );
      return const SizedBox.shrink();
    }

    final profileAsync = ref.watch(profileNotifierProvider(user.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error loading profile', style: AppTextStyles.titleMd),
              const SizedBox(height: 8),
              SFButton(
                label: AppStrings.tryAgain,
                width: 200,
                onPressed: () => ref
                    .read(profileNotifierProvider(user.id).notifier)
                    .loadProfile(),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        final isComplete = profile?.isProfileComplete ?? false;
        if (isComplete) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.go(RoutePaths.home),
          );
          return const SizedBox.shrink();
        }
        // Profile not complete — show gate
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    AppStrings.profileSetupTitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMd.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurface
                          : AppColors.lightOnSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.profileSetupSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SFButton(
                    label: 'Set Up Profile',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.go(RoutePaths.profileSetup),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This is required to use SmartFit',
                    style: AppTextStyles.labelMd.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
