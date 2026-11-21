import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/screens/register_screen.dart';
import 'package:smartfit/shared_widgets/otp_code_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../helpers/fake_auth_repository.dart';

/// Welcome (`/`) with register pushed on top, as in the app.
Future<void> _pumpRegister(WidgetTester tester, FakeAuthRepository repo) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  Widget stub(String name) => Scaffold(body: Text('stub:$name'));
  final router = GoRouter(
    routes: [
      GoRoute(path: RoutePaths.splash, builder: (_, _) => stub('welcome')),
      GoRoute(path: RoutePaths.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: RoutePaths.login, builder: (_, _) => stub('login')),
      GoRoute(path: RoutePaths.profileSetup, builder: (_, _) => stub('profile-setup')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      // The notifier is built from this repository too.
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  router.push(RoutePaths.register);
  await tester.pumpAndSettle();
}

Finder _field(int i) => find.byType(TextFormField).at(i);

/// Fills every field; [dobYearsAgo] picks a birthday that many years ago
/// through the date picker's text-input mode.
Future<void> _fillForm(WidgetTester tester, {int dobYearsAgo = 20, String password = 'Secret#123'}) async {
  await tester.enterText(_field(0), 'Sara Khan');
  await tester.enterText(_field(1), 'sara_k');
  await tester.enterText(_field(2), 'Sara@Example.com');

  final now = DateTime.now();
  final dob = DateTime(now.year - dobYearsAgo, now.month, 1);
  await tester.ensureVisible(find.text('Select your date of birth'));
  await tester.tap(find.text('Select your date of birth'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final mm = dob.month.toString().padLeft(2, '0');
  await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '$mm/01/${dob.year}');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.enterText(_field(3), password);
  await tester.enterText(_field(4), password);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Create account'));
  await tester.tap(find.text('Create account'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty form shows every required-field error, including date of birth', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpRegister(tester, repo);
    await _submit(tester);
    expect(find.text(AppStrings.nameRequired), findsOneWidget);
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text(AppStrings.emailRequired), findsOneWidget);
    expect(find.text(AppStrings.dobRequired), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('under-15 date of birth is rejected (SFR-001)', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpRegister(tester, repo);
    await _fillForm(tester, dobYearsAgo: 13);
    expect(find.text(AppStrings.mustBe15), findsOneWidget);
    await _submit(tester);
    expect(repo.calls, isEmpty);
  });

  testWidgets('already-registered email shows an inline error and stays on the form', (tester) async {
    final repo = FakeAuthRepository(emailTaken: true);
    await _pumpRegister(tester, repo);
    await _fillForm(tester);
    await _submit(tester);
    expect(find.text('This email is already registered. Please login instead.'), findsOneWidget);
    expect(find.byType(OtpCodeField), findsNothing);
  });

  testWidgets('sign-up → code step → verify goes to profile setup', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpRegister(tester, repo);
    await _fillForm(tester);
    await _submit(tester);

    expect(repo.calls, contains('signUp:sara@example.com:sara_k'));
    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.textContaining('sara@example.com'), findsOneWidget);

    // Pasting the whole code works and submits by itself.
    await tester.enterText(find.descendant(of: find.byType(OtpCodeField), matching: find.byType(TextField)), '123456');
    await tester.pumpAndSettle();
    expect(repo.calls, contains('verify:sara@example.com:123456'));
    expect(find.text('stub:profile-setup'), findsOneWidget);
  });

  testWidgets('wrong code shows an error and keeps the user on the code step', (tester) async {
    final repo = FakeAuthRepository(verifyError: const AuthException('Token has expired or is invalid'));
    await _pumpRegister(tester, repo);
    await _fillForm(tester);
    await _submit(tester);
    await tester.enterText(find.descendant(of: find.byType(OtpCodeField), matching: find.byType(TextField)), '000000');
    await tester.pumpAndSettle();
    expect(find.text('That code is invalid or has expired. Please request a new one.'), findsOneWidget);
    expect(find.text('Check your inbox'), findsOneWidget);
  });

  testWidgets('resend waits out the 60 s cooldown, then restarts it', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpRegister(tester, repo);
    await _fillForm(tester);
    await _submit(tester);

    expect(find.text('Resend code in 1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Resend code in 0:01'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code'), findsOneWidget);

    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('resend:sara@example.com'));
    expect(find.text('A new code is on its way to sara@example.com.'), findsOneWidget);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
  });

  testWidgets('back from the code step returns to the filled-in form', (tester) async {
    await _pumpRegister(tester, FakeAuthRepository());
    await _fillForm(tester);
    await _submit(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Sara Khan'), findsOneWidget);
  });

  testWidgets('log in link replaces register', (tester) async {
    await _pumpRegister(tester, FakeAuthRepository());
    await tester.ensureVisible(find.textContaining('Already have an account?'));
    await tester.tap(find.textContaining('Already have an account?'));
    await tester.pumpAndSettle();
    expect(find.text('stub:login'), findsOneWidget);
  });
}
