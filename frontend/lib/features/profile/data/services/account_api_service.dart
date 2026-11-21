import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/network/network_providers.dart';

final accountApiServiceProvider = Provider<AccountApiService>(
  (ref) => AccountApiService(ref.watch(apiDioProvider)),
);

/// The user's own account on the SmartFit API (SFR-008).
///
/// Permanent deletion needs the server's service key, so it goes through the
/// backend (`DELETE /api/v1/account`); deactivation is a profile flag the app
/// sets directly (see AuthRepository).
class AccountApiService {
  AccountApiService(this._dio);

  final Dio _dio;

  /// The exact word the user must type; the server checks it too.
  static const String confirmation = 'DELETE';

  /// Throws a [Failure] with a readable message when it doesn't work.
  Future<void> deleteMyAccount() async {
    try {
      await _dio.delete<Map<String, dynamic>>(
        ApiEndpoints.accountPath,
        data: {'confirm': confirmation},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}
