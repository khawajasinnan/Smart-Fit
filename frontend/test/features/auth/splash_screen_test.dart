import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/screens/splash_screen.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

/// Pumps the splash at `/` with stub destination routes, reduce-motion on
/// (so it settles) and a fixed guard state.
Future<void> _pumpSplash(WidgetTester tester, GuardState guard) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SafeNetworkImage.debugImageProviderOverride = (_) => MemoryImage(Uint8List(0));
  addTearDown(() => SafeNetworkImage.debugImageProviderOverride = null);

  Widget stub(String name) => Scaffold(body: Text('stub:$name'));
  final router = GoRouter(
    routes: [
      GoRoute(path: RoutePaths.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: RoutePaths.onboarding, builder: (_, _) => stub('onboarding')),
      GoRoute(path: RoutePaths.register, builder: (_, _) => stub('register')),
      GoRoute(path: RoutePaths.login, builder: (_, _) => stub('login')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [guardStateProvider.overrideWithValue(guard)],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _signedOut = GuardState(bootstrapping: false, authed: false);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('start-up shows only the brand, no CTAs', (tester) async {
    await _pumpSplash(tester, const GuardState(bootstrapping: true, authed: false));
    expect(find.bySemanticsLabel('SmartFit'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Loading…'), findsOneWidget); // static under reduce-motion
  });

  testWidgets('signed-in user waiting on the profile sees no CTAs', (tester) async {
    await _pumpSplash(tester, const GuardState(bootstrapping: false, authed: true));
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('signed-out user sees the welcome CTAs', (tester) async {
    await _pumpSplash(tester, _signedOut);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('Already have an account?'), findsOneWidget);
  });

  testWidgets('Get started opens onboarding the first time', (tester) async {
    await _pumpSplash(tester, _signedOut);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('stub:onboarding'), findsOneWidget);
  });

  testWidgets('Get started skips onboarding once it has been seen', (tester) async {
    SharedPreferences.setMockInitialValues({'has_seen_onboarding': true});
    await _pumpSplash(tester, _signedOut);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('stub:register'), findsOneWidget);
  });

  testWidgets('Log in opens the login screen', (tester) async {
    await _pumpSplash(tester, _signedOut);
    await tester.tap(find.textContaining('Already have an account?'));
    await tester.pumpAndSettle();
    expect(find.text('stub:login'), findsOneWidget);
  });

  testWidgets('the top Log in button opens the login screen', (tester) async {
    await _pumpSplash(tester, _signedOut);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('stub:login'), findsOneWidget);
  });

  testWidgets('the landing page shows what the app does, how, and the brands', (tester) async {
    await _pumpSplash(tester, _signedOut);
    for (final text in ['Chat with Zayn', 'Virtual try-on', 'Look score', 'Build your profile', 'Outfitters']) {
      await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(text), findsOneWidget);
    }
    // The call to action stays pinned while the page scrolls.
    expect(find.text('Get started').hitTestable(), findsOneWidget);
  });
}
