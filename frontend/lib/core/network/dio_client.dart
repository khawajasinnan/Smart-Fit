import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient;
import 'package:smartfit/core/constants/env.dart';
import 'package:smartfit/core/network/auth_interceptor.dart';

/// The one HTTP client for the SmartFit API gateway (rules.md §2.1: Dio only).
/// [onSessionExpired]: the refresh token was refused, so the user must log in again.
Dio createApiDio(GoTrueClient auth, {void Function()? onSessionExpired}) {
  final baseUrl = Env.apiBaseUrl;
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(
    AuthInterceptor(auth, dio, apiHost: Uri.parse(baseUrl).host, onSessionExpired: onSessionExpired),
  );
  if (kDebugMode) {
    // Bodies are not logged: they can contain photos and personal data.
    dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false, logPrint: (line) => debugPrint(redactLogLine(line))),
    );
  }
  return dio;
}

final _secretHeader = RegExp(r'^(\s*(authorization|apikey|cookie|x-api-key)\s*:).*$', caseSensitive: false);

/// Debug log line with credentials hidden: the login token must never reach
/// the console (it is printed with copied logs, screenshots, bug reports).
@visibleForTesting
String redactLogLine(Object? line) {
  final text = line.toString();
  return text.split('\n').map((l) => l.replaceFirstMapped(_secretHeader, (m) => '${m[1]} [hidden]')).join('\n');
}

/// Plain client for third-party downloads (e.g. a public profile photo).
/// Never carries the user's token.
Dio createExternalDio() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.bytes,
  ),
);
