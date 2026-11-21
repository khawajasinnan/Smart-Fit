import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers Dio requests in-memory. [handler] returns (status, json body) or
/// throws to simulate a network failure.
class FakeDioAdapter implements HttpClientAdapter {
  FakeDioAdapter(this.handler);

  final Object? Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  int status = 200;
  Map<String, List<String>> headers = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeDioAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'))..httpClientAdapter = adapter;
