import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/screens/forgot_password_screen.dart';
import 'package:smartfit/shared_widgets/otp_code_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../helpers/fake_auth_repository.dart';

/// Login with forgot-password pushed on top, as in the app.
Future<void> _pumpForgot(WidgetTester tester, FakeAuthRepository repo) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: RoutePaths.login,
    routes: [
      GoRoute(path: RoutePaths.login, builder: (_, _) => const Scaffold(body: Text('stub:login'))),
      GoRoute(path: RoutePaths.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
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
  router.push(RoutePaths.forgotPassword);
  await tester.pumpAndSettle();
}

Future<void> _toCodeStep(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'Sara@Example.com');
  await tester.tap(find.text('Send reset code'));
  await tester.pumpAndSettle();
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.descendant(of: find.byType(OtpCodeField), matching: find.byType(TextField)), code);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invalid email is caught before anything is sent', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpForgot(tester, repo);
    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.emailInvalid), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('email → code → new password → done → back to login (SFR-005)', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpForgot(tester, repo);

    await _toCodeStep(tester);
    expect(repo.calls, ['resetSend:sara@example.com']);
    expect(find.text('Resend code in 1:00'), findsOneWidget);

    await _enterCode(tester, '654321');
    expect(repo.calls.last, 'recoveryVerify:sara@example.com:654321');
    expect(find.text('Set a new password'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'NewSecret#1');
    await tester.enterText(fields.at(1), 'NewSecret#1');
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(repo.calls, containsAllInOrder(['setPassword', 'signOut']));
    expect(find.text('Password updated'), findsOneWidget);

    await tester.tap(find.text('Back to log in'));
    await tester.pumpAndSettle();
    expect(find.text('stub:login'), findsOneWidget);
  });

  testWidgets('a wrong code shows an error and stays on the code step', (tester) async {
    final repo = FakeAuthRepository(recoveryError: const AuthException('Token has expired or is invalid'));
    await _pumpForgot(tester, repo);
    await _toCodeStep(tester);
    await _enterCode(tester, '000000');
    expect(find.text('That code is invalid or has expired. Please request a new one.'), findsOneWidget);
    expect(find.text('Check your inbox'), findsOneWidget);
  });

  testWidgets('cancelling after the code ends the recovery session', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpForgot(tester, repo);
    await _toCodeStep(tester);
    await _enterCode(tester, '654321');
    expect(find.text('Set a new password'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'signOut');
    expect(repo.calls, isNot(contains('setPassword')));
    expect(find.text('stub:login'), findsOneWidget);
  });

  testWidgets('back from the code step returns to the email step', (tester) async {
    await _pumpForgot(tester, FakeAuthRepository());
    await _toCodeStep(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.text('Sara@Example.com'), findsOneWidget);
  });

  testWidgets('back on the first step leaves without signing anything out', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpForgot(tester, repo);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('stub:login'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });
}
