import 'package:dio/dio.dart';

/// App-level failures (rules.md §3.1). Screens show [message] — always plain,
/// human-readable text — and never see raw exceptions or status codes.
sealed class Failure implements Exception {
  const Failure(this.message, {this.code, this.statusCode});

  /// User-facing explanation.
  final String message;

  /// Machine-readable code from the backend envelope (e.g. `RATE_LIMITED`).
  final String? code;

  final int? statusCode;

  /// Maps any Dio error to a [Failure], reading the backend's
  /// `{"error": {"code", "message"}}` envelope when present.
  factory Failure.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure('The request was cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Secure connection to SmartFit failed.');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.unknown:
        // Socket errors on some platforms surface as `unknown`.
        return e.response == null ? const NetworkFailure() : _fromResponse(e.response);
    }
  }

  static Failure _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    String? code;
    String? message;
    final data = response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        code = error['code']?.toString();
        message = error['message']?.toString();
      } else if (data['detail'] is String) {
        message = data['detail'] as String;
      }
    }

    switch (status) {
      case 401:
        return UnauthorizedFailure(message ?? 'Your session has expired. Please log in again.');
      case 400:
      case 413:
      case 422:
        return ValidationFailure(message ?? 'Please check your input and try again.', code: code, statusCode: status);
      case 429:
        final retryAfter = int.tryParse(response?.headers.value('retry-after') ?? '');
        return RateLimitedFailure(
          message ?? "You're going a bit fast — please wait a moment and try again.",
          retryAfterSeconds: retryAfter,
        );
      case 501:
        return NotImplementedFailure(message ?? 'This feature is coming soon.');
      default:
        return ServerFailure(
          message ?? 'Something went wrong on our side. Please try again.',
          code: code,
          statusCode: status,
        );
    }
  }

  @override
  String toString() => message;
}

/// No connection to the SmartFit server (offline, or the backend isn't running).
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = "Can't reach SmartFit right now. Check your internet connection and try again."]);
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure([super.message = 'The server took too long to respond. Please try again.']);
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message) : super(statusCode: 401);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code, super.statusCode});
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(super.message, {this.retryAfterSeconds}) : super(code: 'RATE_LIMITED', statusCode: 429);

  final int? retryAfterSeconds;
}

final class NotImplementedFailure extends Failure {
  const NotImplementedFailure(super.message) : super(code: 'NOT_IMPLEMENTED', statusCode: 501);
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, super.statusCode});
}

/// Virtual try-on is "unavailable" for this item (SFR-027): a normal outcome
/// with its own screen, not an error. [reason]: not_supported | size | garment_image | gone
/// (gone: the brand no longer sells it or it's sold out; gender: menswear on a female
/// profile or womenswear on a male one).
final class TryOnUnavailableFailure extends Failure {
  const TryOnUnavailableFailure(super.message, {required this.reason})
      : super(code: 'TRYON_UNAVAILABLE', statusCode: 422);

  final String reason;
}

/// A try-on photo was rejected; [angle] ("front", "back", ...) says which side to retake.
final class TryOnPhotoFailure extends Failure {
  const TryOnPhotoFailure(super.message, {this.angle, super.code}) : super(statusCode: 422);

  final String? angle;
}

final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong. Please try again.']);
}
