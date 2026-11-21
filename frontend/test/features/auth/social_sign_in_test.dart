import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/constants/env.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/data/repositories/auth_repository.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/auth/widgets/social_sign_in_buttons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, OAuthProvider;

import '../../helpers/fake_auth_repository.dart';

/// Google and Facebook sign-up / sign-in (SFR-001, SFR-004). Facebook shows only
/// when switched on (Env.facebookLogin), off by default.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, FakeAuthRepository repo, {bool? facebook}) async {
    final container = ProviderContainer(overrides: [authNotifierProvider.overrideWith((ref) => AuthNotifier(repo))]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16), child: SocialSignInButtons(showFacebook: facebook ?? false)))),
    ));
    return container;
  }

  testWidgets('the Facebook button, when switched on, opens Facebook', (tester) async {
    final repo = FakeAuthRepository();
    await pump(tester, repo, facebook: true);
    await tester.tap(find.bySemanticsLabel('Continue with Facebook'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['oauth:facebook']);
  });

  test('the Facebook switch reads true / false from the config', () async {
    expect(Env.facebookLogin, isFalse); // off by default
  });

  testWidgets('the Google button opens Google; Facebook is hidden while switched off', (tester) async {
    final repo = FakeAuthRepository();
    await pump(tester, repo);
    await tester.tap(find.bySemanticsLabel('Continue with Google'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['oauth:google']);
    expect(find.textContaining('Facebook'), findsNothing);
  });

  testWidgets("a browser that can't open is reported", (tester) async {
    final repo = FakeAuthRepository()..oauthOpens = false;
    final container = await pump(tester, repo);
    await tester.tap(find.bySemanticsLabel('Continue with Google'));
    await tester.pumpAndSettle();
    expect(container.read(authNotifierProvider).errorMessage, "Couldn't open Google sign-in. Please try again.");
  });

  test('errors coming back from the provider become friendly messages', () async {
    final repo = FakeAuthRepository();
    final notifier = AuthNotifier(repo);
    addTearDown(notifier.dispose);
    repo.emitAuthError(const AuthException('Unsupported provider: provider is not enabled'));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.status, AuthStatus.error);
    expect(notifier.state.errorMessage, 'That sign-in option is not available yet. Please use email for now.');
    repo.emitAuthError(const AuthException('Error getting user email from external provider'));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.errorMessage, "Your account didn't share an email address. Please sign up with email instead.");
  });

  test('phones come back through the app link; the web through its own address', () {
    expect(AuthRepository.mobileRedirect, 'io.supabase.smartfit://login-callback/');
    expect(AuthRepository.redirectUrl(), AuthRepository.mobileRedirect); // tests run as a non-web platform
  });

  test('Google always shows its account chooser (log out, then pick or sign up with another account)', () {
    // reported 21 Nov 2026: without it Google went straight back into the account used before
    expect(AuthRepository.oauthQueryParams(OAuthProvider.google), {'prompt': 'select_account'});
    expect(AuthRepository.oauthQueryParams(OAuthProvider.facebook), isNull);
  });
}
