import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Attaches the signed-in user's Supabase access token to SmartFit API
/// requests and transparently refreshes it once on a 401 (SRDS §4.2: JWT with
/// refresh tokens).
///
/// The token is only ever sent to the SmartFit API host — never to third-party
/// URLs that happen to go through the same Dio instance.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._auth, this._dio, {required this.apiHost, this.onSessionExpired});

  final GoTrueClient _auth;
  final Dio _dio;
  final String apiHost;

  /// Called when Supabase refuses the refresh token (expired, revoked, signed
  /// out elsewhere): the login is over and the user must sign in again.
  /// Never called for network problems (offline is not "logged out").
  final void Function()? onSessionExpired;

  /// A refresh failure that means the session is gone (not a network error).
  static bool isSessionGone(Object e) => e is AuthException && e is! AuthRetryableFetchException;

  static const _retriedKey = 'auth_retried';

  static DioException sessionExpiredError(RequestOptions options, Object cause) => DioException(
        requestOptions: options,
        error: cause,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 401,
          data: const {
            'error': {'code': 'SESSION_EXPIRED', 'message': 'Your session has expired. Please log in again.'},
          },
        ),
      );

  bool _isApiRequest(RequestOptions options) => options.uri.host == apiHost;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_isApiRequest(options)) {
      var session = _auth.currentSession;
      if (session != null && session.isExpired) {
        try {
          session = (await _auth.refreshSession()).session ?? session;
        } catch (e) {
          debugPrint('[Auth] token refresh failed: ${e.runtimeType}');
          if (isSessionGone(e)) {
            onSessionExpired?.call();
            // answered like the server would: 401 -> "Your session has expired. Please log in again."
            return handler.reject(sessionExpiredError(options, e));
          }
        }
      }
      final token = session?.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final shouldRetry =
        err.response?.statusCode == 401 &&
        _isApiRequest(options) &&
        options.extra[_retriedKey] != true &&
        _auth.currentSession != null;
    if (!shouldRetry) return handler.next(err);

    try {
      final refreshed = await _auth.refreshSession();
      final token = refreshed.session?.accessToken;
      if (token == null) return handler.next(err);
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[_retriedKey] = true;
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (e) {
      if (isSessionGone(e)) onSessionExpired?.call();
      handler.next(err);
    }
  }
}
