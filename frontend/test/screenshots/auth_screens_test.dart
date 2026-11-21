import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/screens/forgot_password_screen.dart';
import 'package:smartfit/features/auth/screens/login_screen.dart';
import 'package:smartfit/features/auth/screens/register_screen.dart';
import 'package:smartfit/shared_widgets/otp_code_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/features/auth/screens/splash_screen.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/screenshot_harness.dart';

/// Visual review of the auth flow screens. Skipped unless SF_SCREENSHOT_DIR
/// is set (see screenshot_harness.dart).
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode.name;

    testWidgets('splash: boot ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        const SplashScreen(),
        mode: mode,
        overrides: [guardStateProvider.overrideWithValue(const GuardState(bootstrapping: true, authed: false))],
      );
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'splash_boot_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('splash: welcome ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        const SplashScreen(),
        mode: mode,
        overrides: [guardStateProvider.overrideWithValue(const GuardState(bootstrapping: false, authed: false))],
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'splash_welcome_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('splash: welcome small phone ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        const SplashScreen(),
        mode: mode,
        size: const Size(360, 640),
        overrides: [guardStateProvider.overrideWithValue(const GuardState(bootstrapping: false, authed: false))],
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'splash_welcome_small_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('onboarding: pages ($suffix)', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(), mode: mode);
      await pumpFrames(tester, const Duration(milliseconds: 800));
      await saveScreenshot(tester, 'onboarding_1_$suffix');
      for (final n in [2, 3]) {
        await tester.tap(find.text('Next'));
        await pumpFrames(tester, const Duration(milliseconds: 900));
        await saveScreenshot(tester, 'onboarding_${n}_$suffix');
      }
    }, skip: !screenshotsEnabled);

    testWidgets('onboarding: mid-swipe parallax ($suffix)', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(), mode: mode);
      await pumpFrames(tester, const Duration(milliseconds: 400));
      final gesture = await tester.startGesture(const Offset(300, 300));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      await saveScreenshot(tester, 'onboarding_swipe_$suffix');
      await gesture.up();
      await pumpFrames(tester, const Duration(milliseconds: 600));
    }, skip: !screenshotsEnabled);

    testWidgets('onboarding: small phone ($suffix)', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(), mode: mode, size: const Size(360, 640));
      await pumpFrames(tester, const Duration(milliseconds: 800));
      await saveScreenshot(tester, 'onboarding_small_$suffix');
    }, skip: !screenshotsEnabled);

    Override authWith(FakeAuthRepository repo) => authNotifierProvider.overrideWith((ref) => AuthNotifier(repo));

    testWidgets('login: default ($suffix)', (tester) async {
      await pumpScreen(tester, const LoginScreen(), mode: mode, overrides: [authWith(FakeAuthRepository())]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'login_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('login: error + restriction ($suffix)', (tester) async {
      final repo = FakeAuthRepository(restriction: {
        'message': 'Your account is suspended until 20 Oct 2026, 1:45 PM. If you violate the rules and regulations again, '
            'your account may be permanently banned.',
      });
      await pumpScreen(tester, const LoginScreen(), mode: mode, overrides: [authWith(repo)]);
      await pumpFrames(tester, const Duration(milliseconds: 800));
      await tester.enterText(find.byType(TextFormField).at(0), 'sara');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret');
      await tester.tap(find.text('Log in'));
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'login_restricted_$suffix');

      // A new attempt clears the banner; a wrong password shows inline.
      repo
        ..restriction = null
        ..signInError = const AuthException('Invalid login credentials');
      await tester.tap(find.text('Log in'));
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'login_error_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('login: small phone ($suffix)', (tester) async {
      await pumpScreen(tester, const LoginScreen(), mode: mode, size: const Size(360, 640), overrides: [authWith(FakeAuthRepository())]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'login_small_$suffix');
    }, skip: !screenshotsEnabled);

    Future<void> fillRegister(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Sara Khan');
      await tester.enterText(fields.at(1), 'sara_k');
      await tester.enterText(fields.at(2), 'sara@example.com');
      await tester.ensureVisible(find.text('Select your date of birth'));
      await tester.tap(find.text('Select your date of birth'));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      await tester.enterText(fields.at(3), 'Secret12');
      await tester.enterText(fields.at(4), 'Secret1');
      await pumpFrames(tester, const Duration(milliseconds: 500));
    }

    testWidgets('register: details ($suffix)', (tester) async {
      await pumpScreen(tester, const RegisterScreen(), mode: mode, overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'register_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('register: filled ($suffix)', (tester) async {
      await pumpScreen(tester, const RegisterScreen(), mode: mode, overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await pumpFrames(tester);
      await fillRegister(tester);
      await tester.ensureVisible(find.text('Create account'));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      await saveScreenshot(tester, 'register_filled_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('register: verify step ($suffix)', (tester) async {
      await pumpScreen(tester, const RegisterScreen(), mode: mode, overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await pumpFrames(tester);
      await fillRegister(tester);
      await tester.enterText(find.byType(TextFormField).at(4), 'Secret12');
      await tester.enterText(find.byType(TextFormField).at(3), 'Secret#12');
      await tester.enterText(find.byType(TextFormField).at(4), 'Secret#12');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await pumpFrames(tester, const Duration(seconds: 3));
      await tester.enterText(find.descendant(of: find.byType(OtpCodeField), matching: find.byType(TextField)), '482');
      await pumpFrames(tester, const Duration(milliseconds: 400));
      await saveScreenshot(tester, 'register_verify_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('register: verify small phone ($suffix)', (tester) async {
      await pumpScreen(tester, const RegisterScreen(), mode: mode, size: const Size(360, 640), overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await pumpFrames(tester);
      await fillRegister(tester);
      await tester.enterText(find.byType(TextFormField).at(3), 'Secret#12');
      await tester.enterText(find.byType(TextFormField).at(4), 'Secret#12');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await pumpFrames(tester, const Duration(seconds: 3));
      await saveScreenshot(tester, 'register_verify_small_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('forgot password: all steps ($suffix)', (tester) async {
      await pumpScreen(tester, const ForgotPasswordScreen(), mode: mode, overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await pumpFrames(tester);
      await saveScreenshot(tester, 'forgot_1_email_$suffix');

      await tester.enterText(find.byType(TextFormField), 'sara@example.com');
      await tester.tap(find.text('Send reset code'));
      await pumpFrames(tester, const Duration(seconds: 2));
      await saveScreenshot(tester, 'forgot_2_code_$suffix');

      await tester.enterText(find.descendant(of: find.byType(OtpCodeField), matching: find.byType(TextField)), '654321');
      await pumpFrames(tester, const Duration(seconds: 2));
      await tester.enterText(find.byType(TextFormField).at(0), 'NewSecret#1');
      await tester.enterText(find.byType(TextFormField).at(1), 'NewSecret#1');
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await saveScreenshot(tester, 'forgot_3_password_$suffix');

      await tester.tap(find.text('Save new password'));
      await pumpFrames(tester, const Duration(seconds: 2));
      await saveScreenshot(tester, 'forgot_4_done_$suffix');
    }, skip: !screenshotsEnabled);
  }
}
