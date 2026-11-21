import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App configuration — never hard-code keys in source (rules.md §2.2).
///
/// Values come from, in priority order:
///  1. `--dart-define` / `--dart-define-from-file=env/dev.json` (CI, release);
///  2. the bundled `env/dev.json` asset, read by [load] — so a plain
///     `flutter run` works once dev.json exists.
///
/// Copy `env/env.example.json` to `env/dev.json` and fill it in; dev.json is
/// gitignored. It is bundled into the app, so it must only ever hold public
/// client values (Supabase URL + anon key, API URL, admin email) — never the
/// service-role key, Gemini key or any other secret (those live in the
/// backend's .env).
abstract final class Env {
  static const _definedUrl = String.fromEnvironment('SUPABASE_URL');
  static const _definedAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _definedAdminEmail = String.fromEnvironment('ADMIN_EMAIL');
  static const _definedApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _definedFacebookLogin = String.fromEnvironment('FACEBOOK_LOGIN');

  static const _defaultAdminEmail = 'admin@smartfit.pk';

  /// Bundled file read by [load] when values weren't passed as defines.
  static const assetPath = 'env/dev.json';

  static String supabaseUrl = _definedUrl;
  static String supabaseAnonKey = _definedAnonKey;
  static String adminEmail = _definedAdminEmail.isEmpty ? _defaultAdminEmail : _definedAdminEmail;
  static String _apiBaseUrl = _definedApiBaseUrl;

  /// SFR-001 / SFR-004: show "Continue with Facebook". Off until the Facebook app is
  /// created and enabled in Supabase (docs/oauth-setup.md §3); then set FACEBOOK_LOGIN
  /// to "true" in env/dev.json or as a --dart-define.
  static bool facebookLogin = _isTrue(_definedFacebookLogin);

  static bool _isTrue(String? v) => const {'true', '1', 'yes', 'on'}.contains(v?.trim().toLowerCase());

  /// Fills any value not given via `--dart-define` from the bundled
  /// `env/dev.json`. Call once at start-up, before reading values.
  static Future<void> load({AssetBundle? bundle}) async {
    Map<String, dynamic> file;
    try {
      file = jsonDecode(await (bundle ?? rootBundle).loadString(assetPath)) as Map<String, dynamic>;
    } catch (_) {
      return; // No dev.json bundled: defines (or the config screen) decide.
    }
    String? read(String key) {
      final v = file[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    if (_definedUrl.isEmpty) supabaseUrl = read('SUPABASE_URL') ?? '';
    if (_definedAnonKey.isEmpty) supabaseAnonKey = read('SUPABASE_ANON_KEY') ?? '';
    if (_definedAdminEmail.isEmpty) adminEmail = read('ADMIN_EMAIL') ?? _defaultAdminEmail;
    if (_definedApiBaseUrl.isEmpty) _apiBaseUrl = read('API_BASE_URL') ?? '';
    if (_definedFacebookLogin.isEmpty) facebookLogin = _isTrue(read('FACEBOOK_LOGIN'));
  }

  /// SmartFit API gateway base URL (…/api/v1).
  ///
  /// If API_BASE_URL isn't set: the Android emulator reaches the host PC at
  /// 10.0.2.2; everything else uses 127.0.0.1. A physical phone needs either
  /// `adb reverse tcp:8000 tcp:8000` (then 127.0.0.1 works) or the PC's LAN IP.
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return isAndroid ? 'http://10.0.2.2:8000/api/v1' : 'http://127.0.0.1:8000/api/v1';
  }

  /// Names of required values that are still missing.
  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
