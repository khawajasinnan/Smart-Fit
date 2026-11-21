import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/screens/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../helpers/fake_auth_repository.dart';

/// Welcome (`/`) with login pushed on top, as in the app.
Future<void> _pumpLogin(WidgetTester tester, FakeAuthRepository repo) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  Widget stub(String name) => Scaffold(body: Text('stub:$name'));
  final router = GoRouter(
    routes: [
      GoRoute(path: RoutePaths.splash, builder: (_, _) => stub('welcome')),
      GoRoute(path: RoutePaths.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: RoutePaths.register, builder: (_, _) => stub('register')),
      GoRoute(path: RoutePaths.forgotPassword, builder: (_, _) => stub('forgot')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith((ref) => AuthNotifier(repo))],
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
  router.push(RoutePaths.login);
  await tester.pumpAndSettle();
}

Finder get _identifierField => find.byType(TextFormField).at(0);
Finder get _passwordField => find.byType(TextFormField).at(1);

Future<void> _submit(WidgetTester tester, {String id = 'sara@example.com', String pw = 'Secret#123'}) async {
  await tester.enterText(_identifierField, id);
  await tester.enterText(_passwordField, pw);
  await tester.tap(find.text('Log in'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty form is validated without calling the backend', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpLogin(tester, repo);
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email or username'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('wrong password shows a friendly inline error that clears on edit', (tester) async {
    final repo = FakeAuthRepository(signInError: const AuthException('Invalid login credentials'));
    await _pumpLogin(tester, repo);
    await _submit(tester);
    expect(find.text('Incorrect email/username or password.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.enterText(_passwordField, 'another');
    await tester.pump();
    expect(find.text('Incorrect email/username or password.'), findsNothing);
  });

  testWidgets('a banned account sees the restriction banner once, not a duplicate error', (tester) async {
    final repo = FakeAuthRepository(restriction: {'message': 'You are banned.'});
    await _pumpLogin(tester, repo);
    await _submit(tester);

    expect(find.text('Account restricted'), findsOneWidget);
    expect(find.text('You are banned.'), findsOneWidget);
    expect(repo.calls, contains('signOut'));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Account restricted'), findsNothing);
  });

  testWidgets('a deactivated account is offered reactivation and can reactivate (SFR-008)', (tester) async {
    final repo = FakeAuthRepository(deactivated: true);
    await _pumpLogin(tester, repo);
    await _submit(tester);

    expect(find.text('Welcome back!'), findsOneWidget);
    await tester.tap(find.text('Reactivate'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('setDeactivated:false'));
    expect(repo.deactivated, isFalse);
    expect(find.text('Welcome back!'), findsNothing);
  });

  testWidgets('choosing to stay signed out keeps the account deactivated (SFR-008)', (tester) async {
    final repo = FakeAuthRepository(deactivated: true);
    await _pumpLogin(tester, repo);
    await _submit(tester);

    await tester.tap(find.text('Stay signed out'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('signOutLocally'));
    expect(repo.deactivated, isTrue);
    expect(find.textContaining('stays deactivated'), findsOneWidget);
  });

  testWidgets('remember me saves the identifier and pre-fills it next time', (tester) async {
    final repo = FakeAuthRepository();
    await _pumpLogin(tester, repo);
    await tester.tap(find.text('Remember me'));
    await _submit(tester, id: 'sara');
    expect(repo.calls.first, 'signIn:sara');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LoginScreen.savedIdentifierKey), 'sara');
    expect(prefs.getBool('has_seen_onboarding'), isTrue);

    await _pumpLogin(tester, FakeAuthRepository());
    expect(find.widgetWithText(TextFormField, 'sara'), findsOneWidget);
  });

  testWidgets('forgot password is pushed on top of login', (tester) async {
    await _pumpLogin(tester, FakeAuthRepository());
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('stub:forgot'), findsOneWidget);
  });

  testWidgets('create account replaces login, so back returns to welcome', (tester) async {
    await _pumpLogin(tester, FakeAuthRepository());
    final link = find.textContaining('New to SmartFit?');
    await tester.ensureVisible(link); // below the Google button: scroll to it
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('stub:register'), findsOneWidget);
  });
}
