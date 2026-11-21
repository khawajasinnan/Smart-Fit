import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/widgets/social_sign_in_buttons.dart';
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/sf_animated_size.dart';
import 'package:smartfit/shared_widgets/sf_brand.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:smartfit/shared_widgets/sf_text_field.dart';

/// Email/username + password login (SFR-004). Where the user goes after a
/// successful login (admin panel, profile setup or home) is decided by the
/// router guard. A banned/suspended account sees why in a banner.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const rememberMeKey = 'remember_me_enabled';
  static const savedIdentifierKey = 'saved_login_identifier';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  /// Last login error, shown inline above the button.
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedIdentifier();
  }

  Future<void> _loadSavedIdentifier() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(LoginScreen.rememberMeKey) ?? false;
      final identifier = prefs.getString(LoginScreen.savedIdentifierKey);
      if (!mounted) return;
      if (remember && identifier != null && identifier.trim().isNotEmpty) {
        _identifierController.text = identifier;
        setState(() => _rememberMe = true);
      }
    } catch (_) {
      // Preferences unavailable — start with an empty form.
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final identifier = _identifierController.text.trim();
    final success = await ref
        .read(authNotifierProvider.notifier)
        .signInWithIdentifier(identifier: identifier, password: _passwordController.text);
    if (!success) return;

    TextInput.finishAutofillContext();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(LoginScreen.rememberMeKey, true);
        await prefs.setString(LoginScreen.savedIdentifierKey, identifier);
      } else {
        await prefs.setBool(LoginScreen.rememberMeKey, false);
        await prefs.remove(LoginScreen.savedIdentifierKey);
      }
      // They have an account, so the intro isn't needed again.
      await prefs.setBool(OnboardingScreen.seenKey, true);
    } catch (_) {
      // Remembering the user is a convenience; never block the login on it.
    }
    // The router guard now moves the user on (core/router/guards.dart).
  }

  bool _askingReactivation = false;

  /// SFR-008: a deactivated account signed in. Reactivate, or stay signed out.
  Future<void> _askToReactivate() async {
    if (_askingReactivation || !mounted) return;
    _askingReactivation = true;
    final reactivate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.waving_hand_rounded),
        title: const Text('Welcome back!'),
        content: const Text(
          'Your account is deactivated. Reactivate it to pick up where you left off — '
          'your profile, wardrobe and chats are still here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay signed out')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reactivate')),
        ],
      ),
    );
    _askingReactivation = false;
    if (!mounted) return;
    final notifier = ref.read(authNotifierProvider.notifier);
    if (reactivate == true) {
      HapticFeedback.mediumImpact();
      await notifier.reactivateAccount();
    } else {
      await notifier.declineReactivation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final auth = ref.watch(authNotifierProvider);
    final loading = auth.status == AuthStatus.loading;
    final restriction = auth.restrictionMessage;

    ref.listen<AuthStateModel>(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        // A ban/suspension is explained by the banner, not repeated here.
        if (next.errorMessage != next.restrictionMessage) {
          setState(() => _error = next.errorMessage);
        }
        ref.read(authNotifierProvider.notifier).clearError();
      }
      final becamePending =
          next.status == AuthStatus.reactivationRequired && prev?.status != AuthStatus.reactivationRequired;
      if (becamePending || (next.status == AuthStatus.reactivationRequired && next.errorMessage != null)) {
        if (next.errorMessage != null) setState(() => _error = next.errorMessage);
        _askToReactivate();
      }
    });
    final info = auth.infoMessage;

    final canPop = Navigator.of(context).canPop();

    return SFScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 48,
                child: canPop
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Align(
              alignment: Alignment.centerLeft,
              child: SFEntrance(child: SFBrandLockup(markSize: 52, fontSize: 28, tagline: true)),
            ),
            const SizedBox(height: AppSpace.xl),
            SFEntrance(
              index: 1,
              child: Semantics(header: true, child: Text('Welcome back', style: context.tt.displaySmall)),
            ),
            const SizedBox(height: AppSpace.xs),
            SFEntrance(
              index: 2,
              child: Text(
                'Log in to pick up where your style left off.',
                style: context.tt.bodyLarge?.copyWith(color: sf.textMuted),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SFAnimatedSize(
              child: restriction == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.lg),
                      child: NoticeBanner(
                        tone: NoticeTone.warning,
                        title: 'Account restricted',
                        message: restriction,
                        onClose: () => ref.read(authNotifierProvider.notifier).clearRestriction(),
                      ),
                    ),
            ),
            SFAnimatedSize(
              child: info == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.lg),
                      child: NoticeBanner(
                        tone: NoticeTone.info,
                        message: info,
                        onClose: () => ref.read(authNotifierProvider.notifier).clearInfo(),
                      ),
                    ),
            ),
            SFEntrance(
              index: 3,
              child: SFGlassCard(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: AbsorbPointer(
                  absorbing: loading,
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SFTextField(
                            controller: _identifierController,
                            label: 'Email or username',
                            hint: 'you@example.com',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            onChanged: _clearError,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter your email or username' : null,
                          ),
                          const SizedBox(height: AppSpace.md),
                          SFTextField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            label: 'Password',
                            hint: 'Your password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onChanged: _clearError,
                            onSubmitted: (_) => _login(),
                            validator: (v) => v == null || v.isEmpty ? AppStrings.passwordRequired : null,
                            suffix: IconButton(
                              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          // Wrap, not Row: on narrow phones or large text the
                          // link drops to its own line instead of overflowing.
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              MergeSemantics(
                                child: InkWell(
                                  borderRadius: AppRadius.smAll,
                                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                                  // Compact checkbox; the whole row is the
                                  // (44 px high) tap target.
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(minHeight: 44),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Checkbox(
                                          value: _rememberMe,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(left: AppSpace.xxs, right: AppSpace.xs),
                                          child: Text('Remember me', style: context.tt.bodyMedium),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
                                onPressed: () => context.push(RoutePaths.forgotPassword),
                                child: const Text('Forgot password?'),
                              ),
                            ],
                          ),
                          SFAnimatedSize(
                            child: _error == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: AppSpace.sm),
                                    child: NoticeBanner(tone: NoticeTone.error, message: _error!),
                                  ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          SFButton(
                            label: 'Log in',
                            trailingIcon: Icons.arrow_forward_rounded,
                            isLoading: loading,
                            onPressed: _login,
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
              index: 4,
              child: Center(
                child: TextButton(
                  // Replace so back from register returns to the welcome screen.
                  onPressed: () => canPop ? context.pushReplacement(RoutePaths.register) : context.go(RoutePaths.register),
                  child: Text.rich(
                    TextSpan(
                      text: 'New to SmartFit? ',
                      style: context.tt.bodyMedium,
                      children: [
                        TextSpan(
                          text: 'Create an account',
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
      ),
    );
  }
}
