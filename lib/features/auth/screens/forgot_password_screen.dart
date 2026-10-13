import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/core/widgets/sf_button.dart';
import 'package:smartfit/core/widgets/sf_text_field.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  int _step = 1; // 1: enter email, 2: enter otp, 3: set new password
  final List<TextEditingController> _otpBoxCtrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _enteredOtp;

  void _syncOtpFromBoxes() {
    _enteredOtp = _otpBoxCtrls.map((c) => c.text).join();
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _otpBoxCtrls) {
      c.dispose();
    }
    for (final n in _otpFocusNodes) {
      n.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) { t.cancel(); setState(() => _countdown = 0); }
      else { setState(() => _countdown--); }
    });
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();
    final success = await ref.read(authNotifierProvider.notifier).sendPasswordResetOtp(email: email);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We sent a password reset code to your email.')));
      setState(() { _step = 2; });
      _startCountdown();
    } else if (mounted) {
      final error = ref.read(authNotifierProvider).errorMessage ?? 'Unable to send password reset email.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _onOtpComplete(String code) async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your email first')));
      return;
    }
    final success = await ref.read(authNotifierProvider.notifier).verifyRecoveryCode(email: email, otp: code);
    if (success && mounted) {
      setState(() {
        _enteredOtp = code;
        _step = 3;
      });
    } else if (mounted) {
      final error = ref.read(authNotifierProvider).errorMessage ?? 'Invalid or expired reset code.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      // clear boxes so user can re-enter
      for (final c in _otpBoxCtrls) { c.clear(); }
      _otpFocusNodes[0].requestFocus();
      setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.go(RoutePaths.login), tooltip: 'Back')),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ClothingPatternBackground(
              opacity: 0.055,
              color: Color(0xFFFF2E93),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(isDark, isLoading),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark, bool isLoading) {
    if (_step == 1) return _buildEmailInputView(isDark, isLoading);
    if (_step == 2) return _buildOtpInputView(isDark);
    return _buildSetPasswordView(isDark, isLoading);
  }

  Widget _buildEmailInputView(bool isDark, bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.electricPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.lock_reset_rounded, size: 32, color: AppColors.electricPurple),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.forgotPasswordTitle, style: AppTextStyles.headlineMd.copyWith(color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
          const SizedBox(height: 8),
          Text(AppStrings.forgotPasswordSubtitle, style: AppTextStyles.bodyMd.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
          const SizedBox(height: 32),
          SFTextField(controller: _emailController, labelText: AppStrings.email, hintText: 'you@example.com', prefixIcon: const Icon(Icons.email_outlined), keyboardType: TextInputType.emailAddress, validator: Validators.email, semanticsLabel: 'Email for password reset'),
          const SizedBox(height: 32),
          SFButton(label: AppStrings.sendOtpCode, onPressed: _sendResetLink, isLoading: isLoading),
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
    );
  }

  Widget _buildOtpInputView(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.electricPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.mark_email_read_rounded, size: 32, color: AppColors.electricPurple)),
        const SizedBox(height: 24),
        Text('Enter Verification Code', style: AppTextStyles.headlineMd.copyWith(color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
        const SizedBox(height: 8),
        const Text('We sent a 6-digit code to your email. Enter it below to continue.', style: TextStyle(fontFamily: 'Inter', fontSize: 14)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Container(
              width: 48,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _otpFocusNodes[i].hasFocus ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.5),
                  width: _otpFocusNodes[i].hasFocus ? 2 : 1,
                ),
              ),
              child: TextFormField(
                controller: _otpBoxCtrls[i],
                focusNode: _otpFocusNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', border: InputBorder.none, contentPadding: EdgeInsets.zero),
                style: AppTextStyles.headlineMd.copyWith(fontSize: 22),
                onChanged: (value) {
                  _syncOtpFromBoxes();
                  if (value.isNotEmpty && i < 5) {
                    _otpFocusNodes[i + 1].requestFocus();
                  }
                  if (value.isEmpty && i > 0) {
                    _otpFocusNodes[i - 1].requestFocus();
                  }
                  // If all boxes are filled, auto-advance
                  final code = _otpBoxCtrls.map((c) => c.text).join();
                  if (code.length == 6) {
                    // validate code with backend before advancing
                    _onOtpComplete(code);
                    return;
                  }
                  setState(() {});
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        SFButton(label: 'Next', onPressed: () {
          if (_enteredOtp == null || _enteredOtp!.trim().length != 6) return;
          setState(() => _step = 3);
        }),
        const SizedBox(height: 12),
        TextButton(onPressed: () { setState(() => _step = 1); }, child: const Text('Back')),
      ],
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05, end: 0, curve: Curves.easeOutQuad);
  }

  Widget _buildSetPasswordView(bool isDark, bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.electricPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.lock_reset_rounded, size: 32, color: AppColors.electricPurple)),
        const SizedBox(height: 24),
        Text('Set New Password', style: AppTextStyles.headlineMd.copyWith(color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
        const SizedBox(height: 8),
        const Text('Choose a new password for your account.', style: TextStyle(fontFamily: 'Inter', fontSize: 14)),
        const SizedBox(height: 24),
        SFTextField(controller: _newPasswordController, labelText: 'New Password', hintText: 'At least 8 characters', prefixIcon: const Icon(Icons.lock_outline_rounded), obscureText: true, validator: Validators.password),
        const SizedBox(height: 12),
        SFTextField(controller: _confirmPasswordController, labelText: 'Confirm Password', hintText: 'Re-enter password', prefixIcon: const Icon(Icons.lock_outline_rounded), obscureText: true, validator: (v) => Validators.confirmPassword(v, _newPasswordController.text)),
        const SizedBox(height: 24),
        SFButton(label: 'Reset Password', isLoading: isLoading, onPressed: () async {
          if (_newPasswordController.text != _confirmPasswordController.text) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
            return;
          }
          if (_enteredOtp == null || _enteredOtp!.trim().length != 6) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter the 6-digit reset code')));
            return;
          }
          final success = await ref.read(authNotifierProvider.notifier).verifyPasswordResetOtp(
            email: _emailController.text.trim().toLowerCase(),
            otp: _enteredOtp!,
            newPassword: _newPasswordController.text.trim(),
          );
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully. Please login again.')));
            context.go(RoutePaths.login);
          } else if (mounted) {
            final error = ref.read(authNotifierProvider).errorMessage ?? 'Invalid or expired reset code.';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          }
        }),
        const SizedBox(height: 12),
        TextButton(onPressed: () { setState(() => _step = 2); }, child: const Text('Back')),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0, curve: Curves.easeOutQuad);
  }

  
}
