import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Authentication repository — Supabase auth methods (SFR-001..005).
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Register with email + password. Supabase emails a 6-digit code (SFR-002).
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
      } catch (_) {
        // The profile row is also created by the on_auth_user_created trigger.
      }
    }
    return response;
  }

  /// Verify the 6-digit code from the sign-up email. (`OtpType.email` is the
  /// current GoTrue type for email codes; `signup` is its deprecated alias.)
  Future<AuthResponse> verifySignupOtp({
    required String email,
    required String otp,
  }) {
    return _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: otp.trim(),
      type: OtpType.email,
    );
  }

  /// Re-send the sign-up verification code (does not create a new account).
  Future<void> resendSignupOtp(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());
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
              'Your account is suspended until ${DateFormat('d MMM yyyy, h:mm a').format(suspendedUntil.toLocal())}. If you violate the rules and regulations again, your account may be permanently banned.',
        };
      }
    }
    return null;
  }

  // ── SFR-008: deactivation ────────────────────────────────────────────────

  /// Whether the user deactivated their account. Fails open (false) if the
  /// check can't run (e.g. the deactivation migration isn't applied yet), so a
  /// database problem never locks everyone out.
  Future<bool> isDeactivated(String userId) async {
    try {
      final row = await _client.from('profiles').select('deactivated_at').eq('id', userId).maybeSingle();
      return row != null && row['deactivated_at'] != null;
    } catch (_) {
      return false;
    }
  }

  /// Set or clear the deactivation flag on the user's own profile (row-level
  /// security allows a user to update their own row).
  Future<void> setDeactivated(String userId, {required bool deactivated}) async {
    await _client
        .from('profiles')
        .update({'deactivated_at': deactivated ? DateTime.now().toUtc().toIso8601String() : null})
        .eq('id', userId);
  }

  /// Sign out on every device (revokes all refresh tokens).
  Future<void> signOutEverywhere() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  /// Local sign-out only; never throws (used after the account is deleted,
  /// when the server no longer knows the session).
  Future<void> signOutLocally() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  /// Send the password-reset code (SFR-005).
  Future<void> sendPasswordResetOtp(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  /// Verify the recovery code. On success Supabase opens a short recovery
  /// session in which the new password can be set.
  Future<AuthResponse> verifyRecoveryOtp({
    required String email,
    required String otp,
  }) {
    return _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: otp.trim(),
      type: OtpType.recovery,
    );
  }

  /// Merge [data] into the user's auth metadata (e.g. phone, avatar_url).
  Future<void> updateUserMetadata(Map<String, dynamic> data) async {
    await _client.auth.updateUser(UserAttributes(data: data));
  }

  Future<void> updateAccountName(String fullName) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName.trim()}),
    );
  }

  /// Set a new password (inside the recovery session).
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
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Where the provider sends the user back after signing in. Phones: the
  /// app's deep link (AndroidManifest / Info.plist). Web: this app's origin.
  /// Both must be in Supabase → Authentication → URL Configuration.
  static const mobileRedirect = 'io.supabase.smartfit://login-callback/';

  static String redirectUrl() => kIsWeb ? '${Uri.base.origin}/' : mobileRedirect;

  /// Sign up / sign in with an OAuth provider (Google; SFR-001, SFR-004) through
  /// Supabase's OAuth: the provider's page opens in the browser, then the
  /// redirect brings the user back and the session arrives as a "signed in"
  /// auth event. Returns false if the browser couldn't be opened.
  Future<bool> signInWithProvider(OAuthProvider provider) {
    return _client.auth.signInWithOAuth(
      provider,
      redirectTo: redirectUrl(),
      scopes: 'email profile',
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      queryParams: oauthQueryParams(provider),
    );
  }

  /// Extra parameters for the provider's own sign-in page. Google: always show the account
  /// chooser. Without it Google went straight back into the account last used in that browser,
  /// so after logging out nobody could pick, or sign up with, a different Google account
  /// (reported 21 Nov 2026). Logging out of SmartFit never signs anyone out of Google itself.
  static Map<String, String>? oauthQueryParams(OAuthProvider provider) =>
      provider == OAuthProvider.google ? const {'prompt': 'select_account'} : null;

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
