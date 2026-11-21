import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/providers/theme_provider.dart';
import 'package:smartfit/features/chatbot/notifications/zayn_notifications.dart';

/// Root application widget
class SmartFitApp extends ConsumerWidget {
  const SmartFitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);
    // Start notifications with the app so the daily reminder is (re)scheduled.
    ref.watch(notificationNotifierProvider.select((s) => s.isEnabled));
    // Zayn's 3-a-day notifications (funny, roast, chill): planned a week ahead, re-planned on changes.
    final zayn = ref.watch(zaynNotificationsProvider);
    // A tapped notification opens its screen (the router's guards still apply);
    // Zayn's answer buttons are saved as feedback first.
    NotificationService.instance
      ..onTapRoute = router.go
      ..onAction = (payload, actionId) => zayn.handle(payload, actionId, router.go);

    return MaterialApp.router(
      title: 'SmartFit',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      // Decode the loader's 3D tee frames while the splash shows, so the
      // first page loader never spins an empty ring.
      builder: (context, child) {
        ClothFrames.precache(context);
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
