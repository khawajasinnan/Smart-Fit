import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/utils/hive_boxes.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';
import 'package:smartfit/features/auth/data/repositories/auth_repository.dart';
import 'package:smartfit/features/auth/data/models/user_model.dart';
import 'package:smartfit/features/profile/data/services/account_api_service.dart';

/// Auth repository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});

/// Auth state
enum AuthStatus { initial, loading, authenticated, unauthenticated, error, reactivationRequired }

enum SignUpResult { success, alreadyRegistered, failed }

class AuthStateModel {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;

  /// Why the user was signed out by the ban/suspension check (shown on login).
  final String? restrictionMessage;

  /// Signed in to a deactivated account: they must choose to reactivate it
  /// (SFR-008). Kept out of [user] so the router holds them on the login screen.
  final UserModel? pendingReactivationUser;

  /// A one-off notice for the login screen (account deactivated / deleted).
  final String? infoMessage;

  const AuthStateModel({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.restrictionMessage,
    this.pendingReactivationUser,
    this.infoMessage,
  });

  AuthStateModel copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? restrictionMessage,
    bool clearRestrictionMessage = false,
    bool clearInfoMessage = false,
  }) {
    return AuthStateModel(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      restrictionMessage:
          clearRestrictionMessage ? null : (restrictionMessage ?? this.restrictionMessage),
      pendingReactivationUser: pendingReactivationUser,
      infoMessage: clearInfoMessage ? null : infoMessage,
    );
  }
}

/// Turns Supabase / network errors into plain language (SRDS §4.3.2: no raw
/// technical errors in the UI).
String friendlyAuthError(Object error) {
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Incorrect email/username or password.';
    }
    if (m.contains('email not confirmed')) {
      return 'Please verify your email first — enter the 6-digit code we sent you.';
    }
    if (m.contains('rate limit') || m.contains('too many') || m.contains('security purposes')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (m.contains('expired') || (m.contains('invalid') && (m.contains('otp') || m.contains('token')))) {
      return 'That code is invalid or has expired. Please request a new one.';
    }
    if (m.contains('same') && m.contains('password')) {
      return 'Your new password must be different from the old one.';
    }
    if (m.contains('provider is not enabled') || m.contains('unsupported provider')) {
      return 'That sign-in option is not available yet. Please use email for now.';
    }
    if (m.contains('email') && m.contains('external provider')) {
      return "Your account didn't share an email address. Please sign up with email instead.";
    }
    if (m.contains('access_denied') || m.contains('cancel')) {
      return 'Sign-in was cancelled.';
    }
    return error.message;
  }
  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('network') ||
      text.contains('clientexception') ||
      text.contains('connection')) {
    return "Can't reach SmartFit right now. Check your internet connection and try again.";
  }
  return 'Something went wrong. Please try again.';
}

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthStateModel> {
  final AuthRepository _repository;
  AuthNotifier(this._repository) : super(const AuthStateModel()) {
    _init();
  }

  /// True between a verified reset code and the new password being saved.
  bool _inRecovery = false;

  Future<bool> _rejectIfRestricted(String userId) async {
    final restriction = await _repository.userRestriction(userId);
    if (restriction != null) {
      await _repository.signOut();
      final message = restriction['message']?.toString();
      state = AuthStateModel(
        status: AuthStatus.error,
        errorMessage: message,
        restrictionMessage: message,
      );
      return true;
    }
    return false;
  }

  /// Restriction first (banned/suspended users are signed out), then
  /// deactivation (SFR-008: the user chooses whether to reactivate). Returns
  /// true when the user may continue into the app.
  Future<bool> _completeSignIn(User user) async {
    if (await _rejectIfRestricted(user.id)) return false;
    if (await _repository.isDeactivated(user.id)) {
      state = AuthStateModel(
        status: AuthStatus.reactivationRequired,
        pendingReactivationUser: UserModel.fromSupabaseUser(user),
      );
      return false;
    }
    state = AuthStateModel(status: AuthStatus.authenticated, user: UserModel.fromSupabaseUser(user));
    return true;
  }

  void _init() {
    final user = _repository.currentUser;
    if (user != null) {
      state = AuthStateModel(
        status: AuthStatus.authenticated,
        user: UserModel.fromSupabaseUser(user),
      );
      Future.microtask(() => _completeSignIn(user));
    } else {
      state = const AuthStateModel(status: AuthStatus.unauthenticated);
    }

    // Listen for auth state changes
    _repository.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session?.user != null) {
        // An explicit sign-in (status loading) runs its own checks; this path
        // covers OAuth redirects and restored sessions.
        if (state.status == AuthStatus.loading || state.status == AuthStatus.reactivationRequired) return;
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(session!.user),
        );
        Future.microtask(() => _completeSignIn(session.user));
      } else if (event == AuthChangeEvent.signedOut) {
        // Keep a ban/suspension or account notice so the login screen can explain it.
        state = AuthStateModel(
          status: AuthStatus.unauthenticated,
          restrictionMessage: state.restrictionMessage,
          infoMessage: state.infoMessage,
        );
      } else if ((event == AuthChangeEvent.tokenRefreshed || event == AuthChangeEvent.userUpdated) &&
          session?.user != null &&
          state.status == AuthStatus.authenticated) {
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(session!.user),
        );
      }
    }, onError: (Object error) {
      // A Google sign-in redirect that came back with an error.
      if (state.status == AuthStatus.authenticated) return;
      state = AuthStateModel(status: AuthStatus.error, errorMessage: friendlyAuthError(error));
    });
  }

  void _fail(Object error) {
    state = state.copyWith(status: AuthStatus.error, errorMessage: friendlyAuthError(error));
  }

  /// Sign up with email
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required DateTime dateOfBirth,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearRestrictionMessage: true, clearInfoMessage: true);
    try {
      final response = await _repository.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        username: username,
        dateOfBirth: dateOfBirth,
      );

      // If Supabase returns no user object, treat as failure
      if (response.user == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Registration failed. Please try again.',
        );
        return SignUpResult.failed;
      }

      // An empty identities list means the email already has an account.
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'This email is already registered. Please login instead.',
        );
        return SignUpResult.alreadyRegistered;
      }

      // Success — still unauthenticated until the email code is verified.
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return SignUpResult.success;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') || msg.contains('already exists')) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'This email is already registered. Please login instead.',
        );
        return SignUpResult.alreadyRegistered;
      }
      _fail(e);
      return SignUpResult.failed;
    } catch (e) {
      _fail(e);
      return SignUpResult.failed;
    }
  }

  /// Verify the 6-digit code from the sign-up email (SFR-002).
  Future<bool> verifySignupOtp({required String email, required String otp}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.verifySignupOtp(email: email, otp: otp);
      if (response.user == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Verification failed. Please check the code and try again.',
        );
        return false;
      }
      state = AuthStateModel(
        status: AuthStatus.authenticated,
        user: UserModel.fromSupabaseUser(response.user!),
      );
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Re-send the sign-up verification code.
  Future<bool> resendSignupOtp({required String email}) async {
    try {
      await _repository.resendSignupOtp(email);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Send the password-reset code (SFR-005).
  Future<bool> sendPasswordResetOtp({required String email}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.sendPasswordResetOtp(email);
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Verify the reset code ONCE. Supabase then opens a short recovery session
  /// that [completePasswordReset] uses to set the new password.
  Future<bool> verifyRecoveryCode({required String email, required String otp}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.verifyRecoveryOtp(email: email, otp: otp);
      if (response.user != null) {
        _inRecovery = true;
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'That code is invalid or has expired. Please request a new one.',
      );
      return false;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Set the new password inside the recovery session, then sign out so the
  /// user logs in fresh with it.
  Future<bool> completePasswordReset(String newPassword) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.resetUserPassword(newPassword);
      await _repository.signOut();
      _inRecovery = false;
      state = const AuthStateModel(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Leave the reset flow without changing the password: end the short
  /// recovery session so a verified code never leaves the user signed in.
  Future<void> cancelPasswordRecovery() async {
    if (!_inRecovery) return;
    _inRecovery = false;
    await _repository.signOut();
  }

  /// Sign in with email or username
  Future<bool> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearRestrictionMessage: true, clearInfoMessage: true);
    try {
      final response = await _repository.signInWithIdentifier(
        identifier: identifier,
        password: password,
      );
      if (response.user != null) {
        return _completeSignIn(response.user!);
      }
      state = state.copyWith(status: AuthStatus.error, errorMessage: 'Login failed. Please try again.');
      return false;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Continue with Google (SFR-001, SFR-004). Opens the
  /// provider's sign-in page; the session comes back later through the auth
  /// listener (a "signed in" event), which runs the same ban / deactivation
  /// checks as email login. New users then complete their profile, including
  /// their date of birth (15+), before using the app (SFR-006).
  Future<bool> signInWithProvider(OAuthProvider provider) async {
    final name = '${provider.name[0].toUpperCase()}${provider.name.substring(1)}';
    state = state.copyWith(clearRestrictionMessage: true, clearInfoMessage: true, clearErrorMessage: true);
    try {
      final opened = await _repository.signInWithProvider(provider);
      if (!opened) {
        state = state.copyWith(status: AuthStatus.error, errorMessage: "Couldn't open $name sign-in. Please try again.");
      }
      return opened;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Sign out
  static const sessionExpiredMessage = 'Your session has expired. Please log in again.';

  /// The login can't be renewed any more (refresh token refused): sign out on
  /// this device and tell the user why they are back on the login screen.
  Future<void> sessionExpired() async {
    if (state.status != AuthStatus.authenticated) return; // already handled
    _inRecovery = false;
    state = const AuthStateModel(status: AuthStatus.unauthenticated, infoMessage: sessionExpiredMessage);
    await _repository.signOutLocally();
    state = const AuthStateModel(status: AuthStatus.unauthenticated, infoMessage: sessionExpiredMessage);
  }

  Future<void> signOut() async {
    _inRecovery = false;
    await _repository.signOut();
    state = const AuthStateModel(status: AuthStatus.unauthenticated);
  }

  Future<bool> updateAccountName(String fullName) async {
    final trimmed = fullName.trim();
    if (trimmed.length < 2) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Please enter your full name.',
      );
      return false;
    }

    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.updateAccountName(trimmed);
      final user = _repository.currentUser;
      state = AuthStateModel(
        status: user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
        user: user != null ? UserModel.fromSupabaseUser(user) : null,
      );
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Clear the error after it has been shown.
  void clearError() {
    state = state.copyWith(
      status: state.user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      clearErrorMessage: true,
    );
  }

  /// Dismiss the ban/suspension banner.
  void clearRestriction() {
    state = state.copyWith(clearRestrictionMessage: true);
  }

  /// Change the password of the signed-in account. Throws with a readable
  /// message (e.g. when Supabase asks for a recent sign-in first).
  Future<void> changePassword(String newPassword) async {
    try {
      await _repository.resetUserPassword(newPassword);
    } catch (e) {
      throw Exception(friendlyAuthError(e));
    }
  }

  void clearInfo() {
    state = state.copyWith(clearInfoMessage: true);
  }

  // ── SFR-008: deactivate / reactivate / delete ────────────────────────────

  /// The user chose to reactivate their deactivated account after signing in.
  Future<bool> reactivateAccount() async {
    final pending = state.pendingReactivationUser;
    if (pending == null) return false;
    try {
      await _repository.setDeactivated(pending.id, deactivated: false);
      state = AuthStateModel(status: AuthStatus.authenticated, user: pending);
      return true;
    } catch (e) {
      state = AuthStateModel(
        status: AuthStatus.reactivationRequired,
        pendingReactivationUser: pending,
        errorMessage: friendlyAuthError(e),
      );
      return false;
    }
  }

  /// The user signed in to a deactivated account but chose not to reactivate.
  Future<void> declineReactivation() async {
    await _repository.signOutLocally();
    state = const AuthStateModel(
      status: AuthStatus.unauthenticated,
      infoMessage: 'Your account stays deactivated. Sign in any time to reactivate it.',
    );
  }

  /// Hide the account and sign out on every device. Throws if the profile
  /// can't be updated (the caller shows the reason).
  Future<void> deactivateAccount() async {
    final user = state.user;
    if (user == null) return;
    await _repository.setDeactivated(user.id, deactivated: true);
    _inRecovery = false;
    await _repository.signOutEverywhere();
    state = const AuthStateModel(
      status: AuthStatus.unauthenticated,
      infoMessage: 'Your account is deactivated. Sign in any time to reactivate it.',
    );
  }

  /// Permanently delete the account through the backend, then clear what the
  /// app stored on this phone. Throws a Failure with a readable message.
  Future<void> deleteAccount(AccountApiService api) async {
    final user = state.user;
    if (user == null) return;
    await api.deleteMyAccount();
    // this device's copies too (the taste box was missed before 20 Nov 2026)
    for (final box in ['smartfit_wardrobe_${user.id}', 'smartfit_loved_fits_${user.id}', 'smartfit_taste_${user.id}',
                      ProfileRepository.extrasBoxName(user.id)]) {
      await deleteLocalBox(box); // closes it first: on the web a plain delete never finished
    }
    _inRecovery = false;
    await _repository.signOutLocally();
    state = const AuthStateModel(
      status: AuthStatus.unauthenticated,
      infoMessage: 'Your SmartFit account and all its data have been deleted.',
    );
  }
}

/// Auth notifier provider
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthStateModel>((ref) {
      final repository = ref.watch(authRepositoryProvider);
      return AuthNotifier(repository);
    });
