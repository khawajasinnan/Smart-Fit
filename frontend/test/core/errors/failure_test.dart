import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';

import '../../helpers/fake_dio_adapter.dart';

Future<Failure> _failureFor(int status, Object? body, {Map<String, List<String>> headers = const {}}) async {
  final adapter = FakeDioAdapter((_) => body)
    ..status = status
    ..headers = headers;
  try {
    await fakeDio(adapter).get<dynamic>('/x');
  } on DioException catch (e) {
    return Failure.fromDio(e);
  }
  fail('expected a DioException for status $status');
}

void main() {
  test('reads the backend error envelope', () async {
    final f = await _failureFor(503, {
      'error': {'code': 'SERVICE_UNAVAILABLE', 'message': "The AI stylist service isn't available right now."},
    });
    expect(f, isA<ServerFailure>());
    expect(f.code, 'SERVICE_UNAVAILABLE');
    expect(f.message, "The AI stylist service isn't available right now.");
  });

  test('maps status codes to typed failures', () async {
    expect(await _failureFor(401, {}), isA<UnauthorizedFailure>());
    expect(await _failureFor(422, {'detail': 'Bad budget'}), isA<ValidationFailure>());
    expect(await _failureFor(501, {}), isA<NotImplementedFailure>());

    final rate = await _failureFor(429, {}, headers: {'retry-after': ['42']});
    expect(rate, isA<RateLimitedFailure>());
    expect((rate as RateLimitedFailure).retryAfterSeconds, 42);
  });

  test('falls back to friendly text when the body is not an envelope', () async {
    final f = await _failureFor(500, 'boom');
    expect(f.message, 'Something went wrong on our side. Please try again.');
  });

  test('network and timeout errors', () {
    final options = RequestOptions(path: '/x');
    expect(
      Failure.fromDio(DioException(requestOptions: options, type: DioExceptionType.connectionError)),
      isA<NetworkFailure>(),
    );
    expect(
      Failure.fromDio(DioException(requestOptions: options, type: DioExceptionType.receiveTimeout)),
      isA<TimeoutFailure>(),
    );
  });
}
