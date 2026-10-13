import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/sf_loading_overlay.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _rememberMeKey = 'remember_me_enabled';
  static const _savedIdentifierKey = 'saved_login_identifier';

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
    final identifier = prefs.getString(_savedIdentifierKey);
    if (!mounted) return;
    if (rememberMe && identifier != null && identifier.trim().isNotEmpty) {
      _identifierController.text = identifier;
      setState(() => _rememberMe = rememberMe);
    } else {
      setState(() => _rememberMe = false);
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    final identifier = _identifierController.text.trim();
    final success = await ref
        .read(authNotifierProvider.notifier)
        .signInWithIdentifier(
          identifier: identifier,
          password: _passwordController.text,
        );
    if (success && mounted) {
      if (_rememberMe) {
        await prefs.setBool(_rememberMeKey, true);
        await prefs.setString(_savedIdentifierKey, identifier);
      } else {
        await prefs.setBool(_rememberMeKey, false);
        await prefs.remove(_savedIdentifierKey);
      }

      // Mark onboarding as seen (user already has an account)
      await prefs.setBool('has_seen_onboarding', true);

      final user = ref.read(authNotifierProvider).user;
      if (user == null) {
        if (mounted) context.go(RoutePaths.home);
        return;
      }
      if (user.email.toLowerCase() == ApiEndpoints.adminEmail.toLowerCase()) {
        if (mounted) context.go(RoutePaths.admin);
        return;
      }

      // Try to check profile — if anything fails, default to /home
      try {
        final isComplete = await ref
            .read(profileRepositoryProvider)
            .isProfileComplete(user.id);
        if (!mounted) return;
        context.go(isComplete ? RoutePaths.home : RoutePaths.profileSetup);
      } catch (_) {
        // DB error (missing column, network, etc.) → just go home
        if (mounted) context.go(RoutePaths.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    ref.listen<AuthStateModel>(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.error,
          ),
        );
        ref.read(authNotifierProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient orbs — top-left primary, bottom-right secondary
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondaryFixedDim.withValues(alpha: 0.2),
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

          SFLoadingOverlay(
            isLoading: isLoading,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

                      // Hero Image Card with overlay
                      Container(
                        width: double.infinity,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF8B5CF6,
                              ).withValues(alpha: 0.15),
                              blurRadius: 40,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: SafeNetworkImage(
                                imageUrl:
                                    'https://images.unsplash.com/photo-1509631179647-0177331693ae?q=80&w=800&auto=format&fit=crop',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      AppColors.background.withValues(
                                        alpha: 0.8,
                                      ),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 24,
                              left: 24,
                              right: 24,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.appName,
                                    style: AppTextStyles.headlineLg.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppStrings.appTagline,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: -0.05, curve: Curves.easeOutCubic),
                      const SizedBox(height: 32),

                      // Glassmorphic Form Card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withValues(alpha: 0.1),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Email Field
                                _buildInputField(
                                  controller: _identifierController,
                                  label: 'EMAIL OR USERNAME',
                                  hint: 'hello@example.com or yourname',
                                  icon: Icons.alternate_email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Email or username is required'
                                      : null,
                                ),
                                const SizedBox(height: 20),
                                // Password Field
                                _buildInputField(
                                  controller: _passwordController,
                                  label: 'PASSWORD',
                                  hint: '••••••••',
                                  icon: Icons.lock_outlined,
                                  obscureText: _obscurePassword,
                                  validator: (v) => v == null || v.isEmpty
                                      ? AppStrings.passwordRequired
                                      : null,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: AppColors.outline,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) => setState(
                                              () => _rememberMe = v ?? false,
                                            ),
                                            activeColor: AppColors.primary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Remember me',
                                          style: AppTextStyles.bodySm.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          context.go(RoutePaths.forgotPassword),
                                      child: Text(
                                        'Forgot?',
                                        style: AppTextStyles.bodySm.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ).animate().scale(begin: const Offset(0.96, 0.96), duration: 300.ms, curve: Curves.easeOutBack),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Login Button — primary pill with glow
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9999),
                                    color: AppColors.primary,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 30,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          9999,
                                        ),
                                      ),
                                    ),
                                    onPressed: isLoading ? null : _login,
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            'Log In',
                                            style: AppTextStyles.headlineMd
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // divider removed per request

                                // OAuth buttons removed
                              ],
                            ),
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 100.ms)
                          .slideY(begin: 0.05, curve: Curves.easeOutCubic),
                      const SizedBox(height: 32),

                      // Footer — "New here? Join"
                      Center(
                        child: GestureDetector(
                          onTap: () => context.go(RoutePaths.register),
                          child: RichText(
                            text: TextSpan(
                              style: AppTextStyles.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                              children: [
                                const TextSpan(text: 'New here? '),
                                TextSpan(
                                  text: 'Join',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
                      const SizedBox(height: 40),
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

  /// Input field matching design.md — pill-shaped with bg-surface-container-low, outline icon
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            label,
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: AppColors.surfaceContainerLow,
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            validator: validator,
            style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.bodyLg.copyWith(
                color: AppColors.outline.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(icon, color: AppColors.outline, size: 22),
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: AppColors.secondaryFixed.withValues(alpha: 0.16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(
                  color: AppColors.secondaryContainer,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(
                  color: AppColors.secondaryContainer,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
              errorStyle: AppTextStyles.labelSm.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // No OAuth buttons shown — helper removed
}
