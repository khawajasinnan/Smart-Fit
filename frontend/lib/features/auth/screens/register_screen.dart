import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/widgets/social_sign_in_buttons.dart';
import 'package:smartfit/features/auth/widgets/password_requirements.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/otp_code_field.dart';
import 'package:smartfit/shared_widgets/sf_animated_size.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:smartfit/shared_widgets/sf_step_progress.dart';
import 'package:smartfit/shared_widgets/sf_text_field.dart';

/// Sign-up (SFR-001, SFR-003) followed by email verification with a 6-digit
/// code (SFR-002). Both steps live on this route; going back from the code
/// step returns to the details with everything still filled in.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  /// Supabase allows a new code once a minute (its default rate limit), so
  /// an earlier resend would only fail with "too many attempts".
  static const resendCooldown = Duration(seconds: 60);

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  DateTime? _dob;
  bool _verifyStep = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Inline messages (errors from the provider, resend confirmation).
  String? _error;
  String? _info;

  Timer? _resendTimer;
  int _resendRemaining = 0;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _email => _emailCtrl.text.trim().toLowerCase();

  void _onOtpChanged() {
    // Rebuild for the Verify button; editing a wrong code clears its error.
    setState(() {
      if (_otpCtrl.text.length < 6) _error = null;
    });
  }

  void _showDetails() {
    setState(() {
      _verifyStep = false;
      _error = null;
      _info = null;
    });
  }

  void _back() => _verifyStep ? _showDetails() : Navigator.of(context).maybePop();

  static String? _validateUsername(String? v) {
    final value = v?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return 'Username is required';
    if (RegExp(r'\s').hasMatch(v ?? '')) return 'Username cannot contain spaces';
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(value)) return 'Use 3-24 letters, numbers, or underscore';
    return null;
  }

  Future<void> _pickDob(FormFieldState<DateTime> field) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: field.value ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Your date of birth',
    );
    if (picked == null) return;
    _dob = picked;
    field.didChange(picked);
    field.validate(); // shows the 15+ rule straight away
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authNotifierProvider.notifier);
    // Start from a clean session: Supabase can keep one briefly after logout.
    if (ref.read(authRepositoryProvider).currentSession != null) {
      try {
        await auth.signOut();
      } catch (_) {
        setState(() => _error = 'Could not clear the previous session. Please try again.');
        return;
      }
    }

    final result = await auth.signUpWithEmail(
      email: _email,
      password: _passwordCtrl.text.trim(),
      fullName: _fullNameCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      dateOfBirth: _dob!,
    );
    // Failures (incl. "already registered") arrive through the listener.
    if (result != SignUpResult.success || !mounted) return;

    TextInput.finishAutofillContext();
    _otpCtrl.clear();
    setState(() {
      _verifyStep = true;
      _info = null;
    });
    _startResendTimer(); // a code was just sent
  }

  Future<void> _verify() async {
    if (_otpCtrl.text.length != 6 || ref.read(authNotifierProvider).status == AuthStatus.loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _info = null;
    });
    final ok = await ref.read(authNotifierProvider.notifier).verifySignupOtp(email: _email, otp: _otpCtrl.text);
    // Verified and signed in: next is the mandatory profile (SFR-006).
    if (ok && mounted) context.go(RoutePaths.profileSetup);
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = RegisterScreen.resendCooldown.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendRemaining--);
      if (_resendRemaining <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_resending || _resendRemaining > 0) return;
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    final ok = await ref.read(authNotifierProvider.notifier).resendSignupOtp(email: _email);
    if (!mounted) return;
    setState(() {
      _resending = false;
      if (ok) _info = 'A new code is on its way to $_email.';
    });
    if (ok) _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).status == AuthStatus.loading;
    final canPop = Navigator.of(context).canPop();

    ref.listen<AuthStateModel>(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        setState(() => _error = next.errorMessage);
        ref.read(authNotifierProvider.notifier).clearError();
      }
    });

    return PopScope(
      canPop: !_verifyStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showDetails();
      },
      child: SFScaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.gutter, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: _verifyStep || canPop
                        ? IconButton(
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            onPressed: _back,
                            icon: const Icon(Icons.arrow_back_rounded),
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: SFStepProgress(step: _verifyStep ? 2 : 1, total: 2)),
                ],
              ),
            ),
            Expanded(
              child: PageTransitionSwitcher(
                duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
                reverse: !_verifyStep,
                // Expand: the default centred, loose Stack shrinks a short
                // step to its content and centres it vertically.
                layoutBuilder: (entries) => Stack(fit: StackFit.expand, children: entries),
                transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                  animation: primary,
                  secondaryAnimation: secondary,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: Colors.transparent,
                  child: child,
                ),
                child: _verifyStep ? _verifyView(loading) : _detailsView(loading, canPop),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: details ──────────────────────────────────────────────────────

  Widget _detailsView(bool loading, bool canPop) {
    final sf = context.sf;
    return SingleChildScrollView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xxl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: SFEntrance(child: SFBrandLockup(markSize: 40, fontSize: 22)),
          ),
          const SizedBox(height: AppSpace.lg),
          SFEntrance(
            child: Semantics(header: true, child: Text('Create your account', style: context.tt.displaySmall)),
          ),
          const SizedBox(height: AppSpace.xs),
          SFEntrance(
            index: 1,
            child: Text(
              'A minute now, and every outfit we suggest fits you better.',
              style: context.tt.bodyLarge?.copyWith(color: sf.textMuted),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(
            index: 2,
            child: SFGlassCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: AbsorbPointer(
                absorbing: loading,
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUnfocus,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SFTextField(
                          controller: _fullNameCtrl,
                          label: 'Full name',
                          hint: 'e.g. Sara Khan',
                          icon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          validator: Validators.fullName,
                        ),
                        const SizedBox(height: AppSpace.md),
                        SFTextField(
                          controller: _usernameCtrl,
                          label: 'Username',
                          hint: 'letters, numbers or _',
                          icon: Icons.alternate_email_rounded,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newUsername],
                          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                          validator: _validateUsername,
                        ),
                        const SizedBox(height: AppSpace.md),
                        SFTextField(
                          controller: _emailCtrl,
                          label: 'Email',
                          hint: 'you@example.com',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          validator: Validators.email,
                        ),
                        const SizedBox(height: AppSpace.md),
                        _DobField(initialValue: _dob, onPick: _pickDob),
                        const SizedBox(height: AppSpace.md),
                        SFTextField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          hint: 'At least 8 characters',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => setState(() {}),
                          validator: Validators.password,
                          suffix: IconButton(
                            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        SFTextField(
                          controller: _confirmCtrl,
                          label: 'Confirm password',
                          hint: 'Type it again',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _register(),
                          validator: (v) => Validators.confirmPassword(v, _passwordCtrl.text),
                          suffix: IconButton(
                            tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                            icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        SFAnimatedSize(
                          child: _passwordCtrl.text.isEmpty && _confirmCtrl.text.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: AppSpace.sm),
                                  child: PasswordRequirementsList(
                                    password: _passwordCtrl.text,
                                    confirmPassword: _confirmCtrl.text,
                                  ),
                                ),
                        ),
                        SFAnimatedSize(
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: AppSpace.md),
                                  child: NoticeBanner(tone: NoticeTone.error, message: _error!),
                                ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        SFButton(
                          label: 'Create account',
                          trailingIcon: Icons.arrow_forward_rounded,
                          isLoading: loading,
                          onPressed: _register,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        SocialSignInButtons(enabled: !loading),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(
            index: 3,
            child: Center(
              child: TextButton(
                // Replace so back from login returns to the welcome screen.
                onPressed: () => canPop ? context.pushReplacement(RoutePaths.login) : context.go(RoutePaths.login),
                child: Text.rich(
                  TextSpan(
                    text: 'Already have an account? ',
                    style: context.tt.bodyMedium,
                    children: [
                      TextSpan(
                        text: 'Log in',
                        style: context.tt.bodyMedium?.copyWith(color: sf.accentText, fontWeight: FontWeight.w700),
                      ),
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

  // ── Step 2: verify email ─────────────────────────────────────────────────

  Widget _verifyView(bool loading) {
    final sf = context.sf;
    final body = context.tt.bodyLarge?.copyWith(color: sf.textMuted);
    return SingleChildScrollView(
      key: const ValueKey('verify'),
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SFEntrance(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(gradient: sf.brandGradient, borderRadius: AppRadius.lgAll),
                child: Icon(Icons.mark_email_unread_outlined, color: context.sf.onBrand, size: 30),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(
            index: 1,
            child: Semantics(header: true, child: Text('Check your inbox', style: context.tt.displaySmall)),
          ),
          const SizedBox(height: AppSpace.xs),
          SFEntrance(
            index: 2,
            child: Text.rich(
              TextSpan(
                text: 'Enter the 6-digit code we sent to ',
                style: body,
                children: [
                  TextSpan(text: _email, style: body?.copyWith(color: sf.ink, fontWeight: FontWeight.w600)),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(
            index: 3,
            child: SFGlassCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OtpCodeField(
                    controller: _otpCtrl,
                    onCompleted: (_) => _verify(),
                    hasError: _error != null,
                    enabled: !loading,
                  ),
                  SFAnimatedSize(
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpace.md),
                            child: NoticeBanner(tone: NoticeTone.error, message: _error!),
                          )
                        : _info != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: AppSpace.md),
                                child: NoticeBanner(tone: NoticeTone.success, message: _info!),
                              )
                            : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  SFButton(
                    label: 'Verify & continue',
                    isLoading: loading,
                    onPressed: _otpCtrl.text.length == 6 ? _verify : null,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  _ResendRow(remaining: _resendRemaining, resending: _resending, onResend: _resend),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            "Can't find it? Check your spam or promotions folder.",
            textAlign: TextAlign.center,
            style: context.tt.bodySmall,
          ),
          const SizedBox(height: AppSpace.xs),
          Center(
            child: TextButton.icon(
              onPressed: _showDetails,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Use a different email'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Date-of-birth picker that validates with the form (15+, SRDS SFR-001).
class _DobField extends StatelessWidget {
  const _DobField({required this.initialValue, required this.onPick});

  final DateTime? initialValue;
  final Future<void> Function(FormFieldState<DateTime> field) onPick;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: initialValue,
      validator: (v) => Validators.dateOfBirth(v),
      builder: (field) => MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.xxs, bottom: AppSpace.xs),
              child: Text('Date of birth', style: context.tt.labelMedium?.copyWith(color: context.sf.ink)),
            ),
            InkWell(
              onTap: () => onPick(field),
              borderRadius: AppRadius.mdAll,
              child: InputDecorator(
                isEmpty: field.value == null,
                decoration: InputDecoration(
                  hintText: 'Select your date of birth',
                  prefixIcon: const Icon(Icons.cake_outlined, size: 22),
                  suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
                  errorText: field.errorText,
                  helperText: 'You need to be 15 or older to join.',
                ),
                child: Text(
                  field.value == null ? '' : DateFormat('d MMMM yyyy').format(field.value!),
                  style: context.tt.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.remaining, required this.resending, required this.onResend});

  final int remaining;
  final bool resending;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    if (remaining > 0) {
      final time = '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
      return SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: context.sf.textMuted),
            const SizedBox(width: 6),
            Text('Resend code in $time', style: context.tt.bodyMedium),
          ],
        ),
      );
    }
    return Center(
      child: TextButton.icon(
        onPressed: resending ? null : onResend,
        icon: resending
            ? const SFLoader.small()
            : const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Resend code'),
      ),
    );
  }
}
