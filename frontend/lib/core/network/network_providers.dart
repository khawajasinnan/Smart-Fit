import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/network/dio_client.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';

/// Dio for the SmartFit API gateway (auth token attached automatically).
final apiDioProvider = Provider<Dio>((ref) {
  final dio = createApiDio(
    ref.watch(supabaseClientProvider).auth,
    // an expired / revoked login sends the user to the login screen with a notice
    onSessionExpired: () => ref.read(authNotifierProvider.notifier).sessionExpired(),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// Dio for third-party downloads (no auth header).
final externalDioProvider = Provider<Dio>((ref) {
  final dio = createExternalDio();
  ref.onDispose(dio.close);
  return dio;
});
