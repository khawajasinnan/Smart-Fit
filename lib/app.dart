import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/providers/theme_provider.dart';

/// Root application widget
class SmartFitApp extends ConsumerWidget {
  const SmartFitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'SmartFit',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
