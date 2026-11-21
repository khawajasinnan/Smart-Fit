import 'dart:async';

import 'package:smartfit/features/auth/data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory AuthRepository for widget tests: no Supabase, scripted results.
/// Anything a test doesn't script throws, so unexpected calls are caught.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.signInError,
    this.restriction,
    this.signUpError,
    this.emailTaken = false,
    this.verifyError,
    this.resendError,
    this.resetSendError,
    this.recoveryError,
    this.deactivated = false,
  });

  /// Returned by [isDeactivated] (SFR-008); [setDeactivated] updates it.
  bool deactivated;

  /// Thrown by [sendPasswordResetOtp] when set.
  Object? resetSendError;

  /// Thrown by [verifyRecoveryOtp] when set (e.g. wrong reset code).
  Object? recoveryError;

  /// Thrown by [signInWithIdentifier] when set (e.g. bad password).
  Object? signInError;

  /// Thrown by [signUpWithEmail] when set.
  Object? signUpError;

  /// Sign-up "succeeds" with no identities — Supabase's already-registered signal.
  bool emailTaken;

  /// Thrown by [verifySignupOtp] when set (e.g. wrong code).
  Object? verifyError;

  /// Thrown by [resendSignupOtp] when set (e.g. rate limit).
  Object? resendError;

  /// Returned by [userRestriction] (e.g. `{'message': 'You are banned.'}`).
  Map<String, dynamic>? restriction;

  final List<String> calls = [];
  final _authEvents = StreamController<AuthState>.broadcast();

  /// An email sign-up (has a date of birth); `viaOAuth` = a Google
  /// sign-up, which has none.
  static User fakeUser({String id = 'user-1', String email = 'sara@example.com', bool viaOAuth = false}) => User(
        id: id,
        email: email,
        appMetadata: const {},
        userMetadata: viaOAuth
            ? const {'full_name': 'Sara Khan', 'avatar_url': 'https://lh3.googleusercontent.com/a/sara'}
            : const {'full_name': 'Sara Khan', 'date_of_birth': '2000-05-14'},
        aud: 'authenticated',
        createdAt: DateTime(2026).toIso8601String(),
      );

  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get authStateChanges => _authEvents.stream;

  @override
  Future<AuthResponse> signInWithIdentifier({required String identifier, required String password}) async {
    calls.add('signIn:$identifier');
    if (signInError != null) throw signInError!;
    return AuthResponse(user: fakeUser());
  }

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required DateTime dateOfBirth,
  }) async {
    calls.add('signUp:$email:$username');
    if (signUpError != null) throw signUpError!;
    final user = fakeUser(email: email);
    return AuthResponse(user: emailTaken ? (User.fromJson({...user.toJson(), 'identities': []})!) : user);
  }

  @override
  Future<AuthResponse> verifySignupOtp({required String email, required String otp}) async {
    calls.add('verify:$email:$otp');
    if (verifyError != null) throw verifyError!;
    return AuthResponse(user: fakeUser(email: email));
  }

  @override
  Future<void> resendSignupOtp(String email) async {
    calls.add('resend:$email');
    if (resendError != null) throw resendError!;
  }

  @override
  Future<void> sendPasswordResetOtp(String email) async {
    calls.add('resetSend:$email');
    if (resetSendError != null) throw resetSendError!;
  }

  @override
  Future<AuthResponse> verifyRecoveryOtp({required String email, required String otp}) async {
    calls.add('recoveryVerify:$email:$otp');
    if (recoveryError != null) throw recoveryError!;
    return AuthResponse(user: fakeUser(email: email));
  }

  @override
  Future<void> resetUserPassword(String password) async => calls.add('setPassword');

  @override
  Future<Map<String, dynamic>?> userRestriction(String userId) async {
    calls.add('restriction:$userId');
    return restriction;
  }

  @override
  Future<void> updateUserMetadata(Map<String, dynamic> data) async {
    calls.add('metadata:${data.keys.join(',')}');
    metadata.addAll(data);
  }

  /// Everything written through [updateUserMetadata].
  final Map<String, dynamic> metadata = {};

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<bool> isDeactivated(String userId) async => deactivated;

  @override
  Future<void> setDeactivated(String userId, {required bool deactivated}) async {
    calls.add('setDeactivated:$deactivated');
    this.deactivated = deactivated;
  }

  @override
  Future<void> signOutEverywhere() async => calls.add('signOutEverywhere');

  @override
  Future<void> signOutLocally() async => calls.add('signOutLocally');

  /// What [signInWithProvider] returns: false = the browser couldn't open.
  bool oauthOpens = true;

  @override
  Future<bool> signInWithProvider(OAuthProvider provider) async {
    calls.add('oauth:${provider.name}');
    return oauthOpens;
  }

  /// A Google sign-in redirect that came back with an error.
  void emitAuthError(Object error) => _authEvents.addError(error);

  /// A Google sign-in redirect that came back with a session (Supabase's
  /// "signed in" event, as when the browser hands the user back to the app).
  void emitSignedIn(User user) => _authEvents.add(
        AuthState(AuthChangeEvent.signedIn, Session(accessToken: 'token', tokenType: 'bearer', user: user)),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeAuthRepository.${invocation.memberName} not scripted');
}
