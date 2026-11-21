import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/auth_interceptor.dart';
import 'package:smartfit/features/auth/data/models/user_model.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException;

import '../../helpers/fake_auth_repository.dart';

class _Notifier extends AuthNotifier {
  _Notifier(super.repository, AuthStateModel start) {
    state = start;
  }
}

/// A login that can't be renewed any more must end on the login screen with a
/// reason, not leave the app "signed in" with every request failing (18 Nov 2026).
void main() {
  const signedIn = AuthStateModel(status: AuthStatus.authenticated, user: UserModel(id: 'u1', email: 'a@b.co'));

  test('an expired session signs out on this device and explains why', () async {
    final repo = FakeAuthRepository();
    final auth = _Notifier(repo, signedIn);
    await auth.sessionExpired();
    expect(auth.state.status, AuthStatus.unauthenticated);
    expect(auth.state.infoMessage, AuthNotifier.sessionExpiredMessage);
    expect(repo.calls.where((c) => c == 'signOutLocally'), hasLength(1));
  });

  test('several failing requests at once sign out only once', () async {
    final repo = FakeAuthRepository();
    final auth = _Notifier(repo, signedIn);
    await Future.wait([auth.sessionExpired(), auth.sessionExpired(), auth.sessionExpired()]);
    expect(repo.calls.where((c) => c == 'signOutLocally'), hasLength(1));
  });

  test('nothing happens when nobody is signed in', () async {
    final repo = FakeAuthRepository();
    final auth = _Notifier(repo, const AuthStateModel(status: AuthStatus.unauthenticated));
    await auth.sessionExpired();
    expect(repo.calls, isNot(contains('signOutLocally')));
    expect(auth.state.infoMessage, isNull);
  });

  test('a refused refresh token ends the session; being offline does not', () {
    expect(AuthInterceptor.isSessionGone(const AuthException('Invalid Refresh Token: Refresh Token Not Found')), isTrue);
    expect(AuthInterceptor.isSessionGone(AuthRetryableFetchException(message: 'SocketException')), isFalse);
    expect(AuthInterceptor.isSessionGone(Exception('timeout')), isFalse);
  });

  test('the rejected request tells the user to log in again', () {
    final err = AuthInterceptor.sessionExpiredError(RequestOptions(path: '/x'), const AuthException('gone'));
    final failure = Failure.fromDio(err);
    expect(failure, isA<UnauthorizedFailure>());
    expect(failure.message, 'Your session has expired. Please log in again.');
  });
}
