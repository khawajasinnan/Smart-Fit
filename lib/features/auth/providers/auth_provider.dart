import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/auth/data/repositories/auth_repository.dart';
import 'package:smartfit/features/auth/data/models/user_model.dart';

/// Auth repository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});

/// Auth state
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum SignUpResult { success, alreadyRegistered, failed }

class AuthStateModel {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;

  const AuthStateModel({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  AuthStateModel copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
  }) {
    return AuthStateModel(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthStateModel> {
  final AuthRepository _repository;
  AuthNotifier(this._repository) : super(const AuthStateModel()) {
    _init();
  }

  Future<bool> _rejectIfRestricted(String userId) async {
    final restriction = await _repository.userRestriction(userId);
    if (restriction != null) {
      await _repository.signOut();
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: restriction['message']?.toString(),
      );
      return true;
    }
    return false;
  }

  void _init() {
    final user = _repository.currentUser;
    if (user != null) {
      state = AuthStateModel(
        status: AuthStatus.authenticated,
        user: UserModel.fromSupabaseUser(user),
      );
      Future.microtask(() => _rejectIfRestricted(user.id));
    } else {
      state = const AuthStateModel(status: AuthStatus.unauthenticated);
    }

    // Listen for auth state changes
    _repository.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session?.user != null) {
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(session!.user),
        );
        Future.microtask(() => _rejectIfRestricted(session.user.id));
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthStateModel(status: AuthStatus.unauthenticated);
      } else if (event == AuthChangeEvent.tokenRefreshed &&
          session?.user != null) {
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(session!.user),
        );
      }
    });
  }

  /// Sign up with email
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required DateTime dateOfBirth,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
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
          errorMessage: 'Registration failed',
        );
        return SignUpResult.failed;
      }

      // If identities list is present but empty, it's likely a duplicate/existing account
      try {
        final identities = response.user?.identities;
        if (identities != null && identities.isEmpty) {
          state = state.copyWith(
            status: AuthStatus.error,
            errorMessage:
                'This email is already registered. Please login instead.',
          );
          return SignUpResult.alreadyRegistered;
        }
      } catch (_) {}

      // Success — user was created or invited; still unauthenticated until email verification
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return SignUpResult.success;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('user already registered') ||
          msg.contains('email already exists') ||
          msg.contains('already exists')) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage:
              'This email is already registered. Please login instead.',
        );
        return SignUpResult.alreadyRegistered;
      }
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return SignUpResult.failed;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return SignUpResult.failed;
    }
  }

  /// Send OTP
  Future<bool> sendRegisterOtp({required String email}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.sendRegisterOtp(email);
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Send password reset email only for forgot password flow.
  Future<bool> sendPasswordResetOtp({required String email}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.sendPasswordResetOtp(email);
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Verify recovery OTP only (do not reset password yet).
  Future<bool> verifyRecoveryCode({
    required String email,
    required String otp,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.verifyRecoveryOtp(
        email: email,
        otp: otp,
      );
      if (response.user != null) {
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Invalid or expired reset code.',
      );
      return false;
    } on AuthException catch (e) {
      final low = e.message.toLowerCase();
      if (low.contains('invalid') || low.contains('expired')) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Invalid or expired reset code.',
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: e.message,
        );
      }
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Verify recovery OTP and set the new password.
  Future<bool> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.verifyRecoveryOtp(
        email: email,
        otp: otp,
      );
      if (response.user != null) {
        await _repository.resetUserPassword(newPassword);
        await _repository.signOut();
        state = const AuthStateModel(status: AuthStatus.unauthenticated);
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Invalid or expired reset code.',
      );
      return false;
    } on AuthException catch (e) {
      final low = e.message.toLowerCase();
      if (low.contains('invalid') || low.contains('expired')) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Invalid or expired reset code.',
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: e.message,
        );
      }
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Verify OTP and update metadata
  Future<bool> verifyRegisterOtp({
    required String email,
    required String otp,
    required String fullName,
    String? password,
    String? phone,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.verifyRegisterOtp(
        email: email,
        otp: otp,
      );
      if (response.user != null) {
        // For signup verification: do NOT set password here.
        // Only update metadata (profile creation). Password should be set via signUp flow.
        await _repository.updateUserMetadata(
          fullName: fullName,
          dateOfBirth: DateTime(2000, 1, 1),
          phone: phone,
        );
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(response.user!),
        );
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Verification failed',
      );
      return false;
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Sign in with email or username
  Future<bool> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.signInWithIdentifier(
        identifier: identifier,
        password: password,
      );
      if (response.user != null) {
        if (await _rejectIfRestricted(response.user!.id)) {
          return false;
        }
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(response.user!),
        );
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Login failed',
      );
      return false;
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await _repository.signInWithGoogle();
      if (response.user != null) {
        if (await _rejectIfRestricted(response.user!.id)) {
          return false;
        }
        state = AuthStateModel(
          status: AuthStatus.authenticated,
          user: UserModel.fromSupabaseUser(response.user!),
        );
        return true;
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Google sign in failed',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Reset password
  Future<bool> resetPassword(String email) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _repository.resetPassword(email);
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
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
        status: user != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        user: user != null ? UserModel.fromSupabaseUser(user) : null,
      );
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(
      status: state.user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
      errorMessage: null,
    );
  }
}

/// Auth notifier provider
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthStateModel>((ref) {
      final repository = ref.watch(authRepositoryProvider);
      return AuthNotifier(repository);
    });
