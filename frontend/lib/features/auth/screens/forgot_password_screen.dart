import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
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

enum _Step { email, code, password, done }

/// Password recovery (SFR-005): email → 6-digit code → new password.
///
/// The code is verified once (step 2); that opens a short Supabase recovery
/// session in which step 3 sets the password, after which the user is signed
/// out to log in fresh. Leaving early ends the recovery session, so a
/// verified code never leaves anyone signed in.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  /// Supabase allows a new code once a minute (default rate limit).
  static const resendCooldown = Duration(seconds: 60);

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Step _step = _Step.email;
  bool _obscure = true;
  String? _error;
  String? _info;

  Timer? _timer;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _email => _emailCtrl.text.trim().toLowerCase();

  void _go(_Step step) {
    setState(() {
      _step = step;
      _error = null;
      _info = null;
    });
  }

  void _onOtpChanged() {
    setState(() {
      if (_otpCtrl.text.length < 6) _error = null;
    });
  }

  /// Back: code → email; otherwise leave the flow.
  void _back() => _step == _Step.code ? _go(_Step.email) : _exit();

  /// Ends any recovery session, then returns to login.
  Future<void> _exit() async {
    await ref.read(authNotifierProvider.notifier).cancelPasswordRecovery();
    if (!mounted) return;
    // pop() rather than maybePop(): this screen's PopScope would block it.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(RoutePaths.login);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = ForgotPasswordScreen.resendCooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_emailFormKey.currentState!.validate()) return;
    final ok = await ref.read(authNotifierProvider.notifier).sendPasswordResetOtp(email: _email);
    if (!ok || !mounted) return;
    _otpCtrl.clear();
    _go(_Step.code);
    _startCountdown();
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    setState(() {
      _error = null;
      _info = null;
    });
    final ok = await ref.read(authNotifierProvider.notifier).sendPasswordResetOtp(email: _email);
    if (!ok || !mounted) return;
    setState(() => _info = 'A new code is on its way to $_email.');
    _startCountdown();
  }

  Future<void> _verifyCode() async {
    if (_otpCtrl.text.length != 6 || ref.read(authNotifierProvider).status == AuthStatus.loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _info = null;
    });
    final ok = await ref.read(authNotifierProvider.notifier).verifyRecoveryCode(email: _email, otp: _otpCtrl.text);
    if (ok && mounted) {
      _timer?.cancel();
      _go(_Step.password);
    }
  }

  Future<void> _savePassword() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_passwordFormKey.currentState!.validate()) return;
    final ok = await ref.read(authNotifierProvider.notifier).completePasswordReset(_passwordCtrl.text.trim());
    if (!ok || !mounted) return;
    TextInput.finishAutofillContext();
    _go(_Step.done);
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).status == AuthStatus.loading;

    ref.listen<AuthStateModel>(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        setState(() => _error = next.errorMessage);
        ref.read(authNotifierProvider.notifier).clearError();
      }
    });

    final stepNumber = switch (_step) {
      _Step.email => 1,
      _Step.code => 2,
      _Step.password || _Step.done => 3,
    };

    return PopScope(
      canPop: _step == _Step.email || _step == _Step.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SFScaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.gutter, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _step == _Step.password ? 'Cancel' : MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: _step == _Step.done ? _exit : _back,
                    icon: Icon(_step == _Step.password ? Icons.close_rounded : Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _step == _Step.done ? 0 : 1,
                      duration: AppDurations.base,
                      child: SFStepProgress(step: stepNumber, total: 3),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageTransitionSwitcher(
                duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
                layoutBuilder: (entries) => Stack(fit: StackFit.expand, children: entries),
                transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                  animation: primary,
                  secondaryAnimation: secondary,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: Colors.transparent,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    _Step.email => _emailStep(loading),
                    _Step.code => _codeStep(loading),
                    _Step.password => _passwordStep(loading),
                    _Step.done => _doneStep(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Layout helpers ──────────────────────────────────────────────────────

  Widget _page({required IconData icon, required String title, required Widget subtitle, required Widget card, List<Widget> after = const []}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xxl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SFEntrance(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(gradient: context.sf.brandGradient, borderRadius: AppRadius.lgAll),
                child: Icon(icon, color: context.sf.onBrand, size: 30),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(index: 1, child: Semantics(header: true, child: Text(title, style: context.tt.displaySmall))),
          const SizedBox(height: AppSpace.xs),
          SFEntrance(index: 2, child: subtitle),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(index: 3, child: SFGlassCard(padding: const EdgeInsets.all(AppSpace.lg), child: card)),
          ...after,
        ],
      ),
    );
  }

  Widget _muted(String text) => Text(text, style: context.tt.bodyLarge?.copyWith(color: context.sf.textMuted));

  Widget _messages() => SFAnimatedSize(
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
      );

  // ── Steps ───────────────────────────────────────────────────────────────

  Widget _emailStep(bool loading) {
    return _page(
      icon: Icons.lock_reset_rounded,
      title: 'Forgot your password?',
      subtitle: _muted("Enter your account email and we'll send you a 6-digit code to reset it."),
      card: Form(
        key: _emailFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SFTextField(
              controller: _emailCtrl,
              label: 'Email',
              hint: 'you@example.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _sendCode(),
              validator: Validators.email,
            ),
            _messages(),
            const SizedBox(height: AppSpace.lg),
            SFButton(
              label: 'Send reset code',
              trailingIcon: Icons.arrow_forward_rounded,
              isLoading: loading,
              onPressed: _sendCode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeStep(bool loading) {
    final body = context.tt.bodyLarge?.copyWith(color: context.sf.textMuted);
    return _page(
      icon: Icons.mark_email_unread_outlined,
      title: 'Check your inbox',
      subtitle: Text.rich(
        TextSpan(
          text: 'Enter the 6-digit code we sent to ',
          style: body,
          children: [
            TextSpan(text: _email, style: body?.copyWith(color: context.sf.ink, fontWeight: FontWeight.w600)),
            const TextSpan(text: '.'),
          ],
        ),
      ),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OtpCodeField(controller: _otpCtrl, onCompleted: (_) => _verifyCode(), hasError: _error != null, enabled: !loading),
          _messages(),
          const SizedBox(height: AppSpace.lg),
          SFButton(label: 'Verify code', isLoading: loading, onPressed: _otpCtrl.text.length == 6 ? _verifyCode : null),
          const SizedBox(height: AppSpace.sm),
          _ResendRow(remaining: _countdown, onResend: loading ? null : _resend),
        ],
      ),
      after: [
        const SizedBox(height: AppSpace.lg),
        Text("Can't find it? Check your spam or promotions folder.", textAlign: TextAlign.center, style: context.tt.bodySmall),
        const SizedBox(height: AppSpace.xs),
        Center(
          child: TextButton.icon(
            onPressed: () => _go(_Step.email),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Use a different email'),
          ),
        ),
      ],
    );
  }

  Widget _passwordStep(bool loading) {
    return _page(
      icon: Icons.password_rounded,
      title: 'Set a new password',
      subtitle: _muted('Code confirmed. Choose a new password for your account.'),
      card: Form(
        key: _passwordFormKey,
        autovalidateMode: AutovalidateMode.onUnfocus,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SFTextField(
                controller: _passwordCtrl,
                label: 'New password',
                hint: 'At least 8 characters',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                validator: Validators.password,
                suffix: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              SFTextField(
                controller: _confirmCtrl,
                label: 'Confirm new password',
                hint: 'Type it again',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _savePassword(),
                validator: (v) => Validators.confirmPassword(v, _passwordCtrl.text),
              ),
              SFAnimatedSize(
                child: _passwordCtrl.text.isEmpty && _confirmCtrl.text.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpace.sm),
                        child: PasswordRequirementsList(password: _passwordCtrl.text, confirmPassword: _confirmCtrl.text),
                      ),
              ),
              _messages(),
              const SizedBox(height: AppSpace.lg),
              SFButton(label: 'Save new password', isLoading: loading, onPressed: _savePassword),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doneStep() {
    return _page(
      icon: Icons.check_rounded,
      title: 'Password updated',
      subtitle: _muted('You can now log in with your new password.'),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NoticeBanner(tone: NoticeTone.success, message: 'Your password was changed successfully.'),
          const SizedBox(height: AppSpace.lg),
          SFButton(label: 'Back to log in', trailingIcon: Icons.arrow_forward_rounded, onPressed: _exit),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.remaining, required this.onResend});

  final int remaining;
  final VoidCallback? onResend;

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
        onPressed: onResend,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Resend code'),
      ),
    );
  }
}
