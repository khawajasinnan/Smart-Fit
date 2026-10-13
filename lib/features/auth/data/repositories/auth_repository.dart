import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Authentication repository — Supabase auth methods
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Register with email + password
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required DateTime dateOfBirth,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedUsername = username.trim().toLowerCase();
    final response = await _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'full_name': fullName,
        'username': normalizedUsername,
        'date_of_birth': dateOfBirth.toIso8601String(),
      },
    );
    if (response.user != null) {
      try {
        await _client.from('profiles').upsert({
          'id': response.user!.id,
          'email': normalizedEmail,
          'full_name': fullName.trim(),
          'username': normalizedUsername,
          'date_of_birth': dateOfBirth.toIso8601String(),
        }, onConflict: 'id');
      } catch (_) {}
    }
    return response;
  }

  Future<String?> emailForUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    final response = await _client.rpc(
      'email_for_username',
      params: {'username_input': normalized},
    );
    return response as String?;
  }

  Future<Map<String, dynamic>?> userRestriction(String userId) async {
    final response = await _client
        .from('profiles')
        .select('is_banned, ban_reason, suspended_until, suspension_reason')
        .eq('id', userId)
        .maybeSingle();
    if (response == null) return null;
    if (response['is_banned'] == true) {
      return {
        'type': 'banned',
        'message':
            'You have violated the rules and regulations. You are banned.',
      };
    }
    final suspendedUntilRaw = response['suspended_until'];
    if (suspendedUntilRaw != null) {
      final suspendedUntil = DateTime.tryParse(suspendedUntilRaw.toString());
      if (suspendedUntil != null &&
          suspendedUntil.isAfter(DateTime.now().toUtc())) {
        return {
          'type': 'suspended',
          'until': suspendedUntil.toIso8601String(),
          'message':
              'Your account is suspended until ${suspendedUntil.toLocal()}. If you violate the rules and regulations again, your account may be permanently banned.',
        };
      }
    }
    return null;
  }

  /// Upload avatar to Supabase storage and return public URL
  Future<String> uploadAvatar(
    Uint8List bytes,
    String userId, {
    String ext = 'jpg',
  }) async {
    final path = '$userId/avatar.$ext';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    return publicUrl;
  }

  /// Send OTP for registration/login
  Future<void> sendRegisterOtp(String email) async {
    await _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
  }

  /// Send password reset email only for forgot password flow.
  Future<void> sendPasswordResetOtp(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _client.auth.resetPasswordForEmail(normalizedEmail);
  }

  /// Verify recovery OTP (reset password flow)
  Future<AuthResponse> verifyRecoveryOtp({
    required String email,
    required String otp,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client.auth.verifyOTP(
      email: normalizedEmail,
      token: otp,
      type: OtpType.recovery,
    );
    return response;
  }

  /// Verify signup OTP
  Future<AuthResponse> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client.auth.verifyOTP(
      email: normalizedEmail,
      token: otp,
      type: OtpType.email,
    );
    return response;
  }

  /// Update User Metadata
  Future<void> updateUserMetadata({
    required String fullName,
    required DateTime dateOfBirth,
    String? phone,
  }) async {
    final data = {
      'full_name': fullName,
      'date_of_birth': dateOfBirth.toIso8601String(),
    };
    if (phone != null && phone.isNotEmpty) {
      data['phone'] = phone;
    }
    await _client.auth.updateUser(UserAttributes(data: data));
  }

  Future<void> updateAccountName(String fullName) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName.trim()}),
    );
  }

  /// Reset user password after recovery flow
  Future<void> resetUserPassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  /// Sign in with email/username + password
  Future<AuthResponse> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    final email = trimmed.contains('@')
        ? trimmed.toLowerCase()
        : await emailForUsername(trimmed);
    if (email == null || email.isEmpty) {
      throw const AuthException('No account found for that username.');
    }
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle() async {
    final googleUser = await GoogleSignIn(
      scopes: ['email', 'profile'],
    ).signIn();

    if (googleUser == null) {
      throw Exception('Google sign in cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('Failed to get Google ID token');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  /// Sign in with Facebook
  Future<AuthResponse> signInWithFacebook() async {
    // Facebook auth flow via Supabase OAuth redirect.
    // Implementation requires Facebook provider setup and deep links.
    await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'io.supabase.smartfit://login-callback/',
    );
    // Note: This opens a browser — the auth state change listener will pick up the result
    throw UnimplementedError('Facebook OAuth requires deep link setup');
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _client.auth.resetPasswordForEmail(normalizedEmail);
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Resend email verification
  Future<void> resendVerificationEmail(String email) async {
    await _client.auth.resend(type: OtpType.email, email: email);
  }

  /// Check if user email is verified
  bool get isEmailVerified {
    return currentUser?.emailConfirmedAt != null;
  }

  /// Refresh session
  Future<AuthResponse> refreshSession() async {
    return await _client.auth.refreshSession();
  }
}
