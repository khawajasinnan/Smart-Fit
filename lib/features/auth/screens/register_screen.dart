import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/widgets/password_requirements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  // 6 individual OTP box controllers + focus nodes
  final List<TextEditingController> _otpBoxCtrls = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  DateTime? _selectedDob;
  bool _showVerification = false;
  Timer? _resendTimer;
  int _resendRemaining = 0;
  bool _isResending = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  AnimationController? _fadeCtrl;
  Animation<double> get _fadeAnim => _fadeCtrl != null
      ? CurvedAnimation(parent: _fadeCtrl!, curve: Curves.easeInOut)
      : const AlwaysStoppedAnimation(1.0);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeCtrl!.forward();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    for (final c in _otpBoxCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _fadeCtrl?.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _handleBack() {
    if (_showVerification) {
      _fadeCtrl?.reverse().then((_) {
        if (!mounted) return;
        setState(() => _showVerification = false);
        _fadeCtrl?.forward();
      });
      return;
    }

    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.login);
    }
  }

  void _syncOtpFromBoxes() {
    _otpCtrl.text = _otpBoxCtrls.map((c) => c.text).join();
  }

  // Age validation — minimum 15 years per claude.md SFR-001
  bool get _isOldEnough {
    if (_selectedDob == null) return false;
    final today = DateTime.now();
    final age = today.year - _selectedDob!.year;
    final hasBirthdayPassed =
        today.month > _selectedDob!.month ||
        (today.month == _selectedDob!.month && today.day >= _selectedDob!.day);
    return (hasBirthdayPassed ? age : age - 1) >= 15;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Select your date of birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            secondary: AppColors.secondaryContainer,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDob == null) {
      _showErr('Please select your date of birth.');
      return;
    }
    if (!_isOldEnough) {
      _showErr('You must be at least 15 years old to use SmartFit.');
      return;
    }

    // Registration must start from a clean auth session. Supabase can keep a
    // local session briefly after navigation, so clear it instead of blocking
    // the user with a stale "logout first" error.
    final supabase = Supabase.instance.client;
    final enteredEmail = _emailCtrl.text.trim().toLowerCase();
    if (supabase.auth.currentSession != null) {
      try {
        await ref.read(authNotifierProvider.notifier).signOut();
      } catch (_) {
        _showErr(
          'Could not clear the previous session. Please try logging out again.',
        );
        return;
      }
    }

    // Call provider to sign up and handle explicit results
    final result = await ref
        .read(authNotifierProvider.notifier)
        .signUpWithEmail(
          email: enteredEmail,
          password: _passwordCtrl.text.trim(),
          fullName: _fullNameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          dateOfBirth: _selectedDob!,
        );

    if (result == SignUpResult.alreadyRegistered) {
      _showErr(
        'This email address is already registered. Please login instead.',
      );
      return;
    }

    if (result == SignUpResult.failed) {
      final err =
          ref.read(authNotifierProvider).errorMessage ?? 'Registration failed';
      _showErr(err);
      return;
    }

    // Success — show OTP verification UI (user must verify email)
    if (mounted) {
      _fadeCtrl?.reverse().then((_) {
        setState(() => _showVerification = true);
        _fadeCtrl?.forward();
        _startResendTimer();
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.length != 6) {
      _showErr('Please enter a valid 6-digit OTP');
      return;
    }
    // Only verify OTP; do NOT set password or call reset flows here.
    try {
      final resp = await Supabase.instance.client.auth.verifyOTP(
        email: _emailCtrl.text.trim().toLowerCase(),
        token: _otpCtrl.text.trim(),
        type: OtpType.email,
      );
      if (resp.user != null && mounted) {
        context.go(RoutePaths.profileSetup);
      } else {
        _showErr('Verification failed');
      }
    } catch (e) {
      _showErr(e.toString());
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendRemaining = (_resendRemaining - 1).clamp(0, 999));
      if (_resendRemaining <= 0) t.cancel();
    });
  }

  Future<void> _resendOtp() async {
    if (_isResending) return;
    setState(() => _isResending = true);
    // Resending belongs to signup; clear any accidental active session first.
    final supabase = Supabase.instance.client;
    if (supabase.auth.currentSession != null) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }

    final success = await ref
        .read(authNotifierProvider.notifier)
        .sendRegisterOtp(email: _emailCtrl.text.trim());
    setState(() => _isResending = false);
    if (success && mounted) {
      _startResendTimer();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OTP resent')));
    }
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    ref.listen<AuthStateModel>(authNotifierProvider, (_, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        _showErr(next.errorMessage!);
        Future.microtask(
          () => ref.read(authNotifierProvider.notifier).clearError(),
        );
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // 3 ambient orbs: pink top-left, purple right, pink bottom-left
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
                      AppColors.secondaryFixedDim.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 200,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -60,
              child: Container(
                width: 300,
                height: 300,
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
            // Decorative blur element behind card
            Positioned(
              bottom: 100,
              right: -20,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer.withValues(alpha: 0.6),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: const SizedBox(),
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

            FadeTransition(
              opacity: _fadeAnim,
              child: _showVerification
                  ? _buildOtpScreen(isLoading)
                  : _buildRegistrationForm(isLoading),
            ),
          ],
        ),
      ),
    );
  }

  // OTP Verification Screen
  Widget _buildOtpScreen(bool isLoading) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.mark_email_read,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Check Your Email',
              style: AppTextStyles.headlineLg.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We sent a 6-digit code to ${_emailCtrl.text}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            // 6 individual OTP boxes — each accepts 1 digit, auto-advances
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                return Container(
                  width: 48,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _otpFocusNodes[i].hasFocus
                          ? AppColors.primary
                          : AppColors.outlineVariant.withValues(alpha: 0.5),
                      width: _otpFocusNodes[i].hasFocus ? 2 : 1,
                    ),
                    boxShadow: _otpFocusNodes[i].hasFocus
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              blurRadius: 15,
                            ),
                          ]
                        : null,
                  ),
                  child: TextFormField(
                    controller: _otpBoxCtrls[i],
                    focusNode: _otpFocusNodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: AppTextStyles.headlineMd.copyWith(
                      color: AppColors.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      _syncOtpFromBoxes();
                      if (val.isNotEmpty && i < 5) {
                        _otpFocusNodes[i + 1].requestFocus();
                      }
                      if (val.isEmpty && i > 0) {
                        _otpFocusNodes[i - 1].requestFocus();
                      }
                      setState(() {}); // rebuild to update border colors
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // Verify button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(9999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                onPressed: isLoading ? null : _verifyOtp,
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Verify & Continue',
                        style: AppTextStyles.headlineMd.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Didn't receive code? ",
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                _resendRemaining > 0
                    ? Text(
                        '${AppStrings.resendIn} ${_resendRemaining}s',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.primary,
                        ),
                      )
                    : TextButton(
                        onPressed: isLoading || _isResending
                            ? null
                            : _resendOtp,
                        child: Text(
                          'Resend',
                          style: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ],
            ),
            TextButton(
              onPressed: () => _fadeCtrl?.reverse().then((_) {
                setState(() => _showVerification = false);
                _fadeCtrl?.forward();
              }),
              child: Text(
                '← Back to Sign Up',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Registration Form — fields: Name, Email, DOB, Password, Confirm
  Widget _buildRegistrationForm(bool isLoading) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Center(
                child: Text(
                  'Join SmartFit',
                  style: AppTextStyles.displayXl.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.05, curve: Curves.easeOutCubic),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Create your account to get started',
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 50.ms).slideY(begin: -0.05, curve: Curves.easeOutCubic),
              const SizedBox(height: 32),

              // Glass Card — rounded-[32px] per design.md
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          blurRadius: 60,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildField(
                          label: 'FULL NAME',
                          hint: 'Enter your name',
                          icon: Icons.person_outlined,
                          controller: _fullNameCtrl,
                          validator: Validators.fullName,
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                          label: 'USERNAME',
                          hint: 'letters, numbers, underscore',
                          icon: Icons.alternate_email_rounded,
                          controller: _usernameCtrl,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          validator: (v) {
                            final value = v?.trim().toLowerCase() ?? '';
                            if (value.isEmpty) return 'Username is required';
                            if (RegExp(r'\s').hasMatch(v ?? '')) {
                              return 'Username cannot contain spaces';
                            }
                            if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(value)) {
                              return 'Use 3-24 letters, numbers, or underscore';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                          label: 'EMAIL',
                          hint: 'hello@example.com',
                          icon: Icons.mail_outlined,
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 20),
                        // DOB
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: Text(
                            'DATE OF BIRTH',
                            style: AppTextStyles.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _pickDob,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: _selectedDob != null && !_isOldEnough
                                    ? AppColors.error
                                    : AppColors.outlineVariant.withValues(
                                        alpha: 0.3,
                                      ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cake_outlined,
                                  color: AppColors.outline,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _selectedDob == null
                                        ? 'Select your date of birth'
                                        : DateFormat(
                                            'MMMM d, yyyy',
                                          ).format(_selectedDob!),
                                    style: AppTextStyles.bodyLg.copyWith(
                                      color: _selectedDob == null
                                          ? AppColors.outline.withValues(
                                              alpha: 0.6,
                                            )
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  color: AppColors.outline,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_selectedDob != null && !_isOldEnough)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 8),
                            child: Text(
                              'You must be at least 15 years old.',
                              style: AppTextStyles.labelSm.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        _buildField(
                          label: 'PASSWORD',
                          hint: 'At least 8 characters',
                          icon: Icons.lock_outlined,
                          controller: _passwordCtrl,
                          focusNode: _passwordFocusNode,
                          validator: Validators.password,
                          obscureText: _obscurePassword,
                          onChanged: (_) => setState(() {}),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.outline,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                          label: 'CONFIRM PASSWORD',
                          hint: 'Re-enter password',
                          icon: Icons.lock_outline,
                          controller: _confirmPasswordCtrl,
                          focusNode: _confirmPasswordFocusNode,
                          validator: (v) =>
                              Validators.confirmPassword(v, _passwordCtrl.text),
                          obscureText: _obscureConfirm,
                          onChanged: (_) => setState(() {}),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.outline,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                        if (_passwordCtrl.text.isNotEmpty ||
                            _confirmPasswordCtrl.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: PasswordRequirementsList(
                              password: _passwordCtrl.text,
                              confirmPassword: _confirmPasswordCtrl.text,
                            ),
                          ),
                        const SizedBox(height: 32),

                        // CTA — hot pink (secondary-container) per design.md
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9999),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.secondaryContainer,
                                AppColors.secondary,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary.withValues(
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
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9999),
                              ),
                            ),
                            onPressed: isLoading ? null : _register,
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Join SmartFit',
                                        style: AppTextStyles.headlineMd
                                            .copyWith(
                                              color: Colors.white,
                                              fontSize: 18,
                                            ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ).animate().scale(begin: const Offset(0.96, 0.96), duration: 300.ms, curve: Curves.easeOutBack),
                      ],
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms, delay: 100.ms)
                  .slideY(begin: 0.05, curve: Curves.easeOutCubic),
              const SizedBox(height: 32),

              // Footer — "Already have an account? Log In"
              Center(
                child: GestureDetector(
                  onTap: () => context.go(RoutePaths.login),
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Log In',
                          style: TextStyle(
                            color: AppColors.secondaryContainer,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.secondaryFixed,
                            decorationThickness: 2,
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
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
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
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            validator: validator,
            onChanged: onChanged,
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
}
