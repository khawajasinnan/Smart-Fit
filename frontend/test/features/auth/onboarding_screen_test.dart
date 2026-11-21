import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

/// Welcome (`/`) → onboarding pushed on top, as in the app.
Future<GoRouter> _pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SafeNetworkImage.debugImageProviderOverride = (_) => MemoryImage(Uint8List(0));
  addTearDown(() => SafeNetworkImage.debugImageProviderOverride = null);

  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    routes: [
      GoRoute(path: RoutePaths.splash, builder: (_, _) => const Scaffold(body: Text('stub:welcome'))),
      GoRoute(path: RoutePaths.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: RoutePaths.register, builder: (_, _) => const Scaffold(body: Text('stub:register'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    ),
  );
  router.push(RoutePaths.onboarding);
  await tester.pumpAndSettle();
  return router;
}

Future<bool?> _seen() async => (await SharedPreferences.getInstance()).getBool(OnboardingScreen.seenKey);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Next walks the three pages, then creates the account', (tester) async {
    final router = await _pumpOnboarding(tester);
    expect(find.textContaining('01 / 03'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('02 / 03'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('03 / 03'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.text('Create my account'));
    await tester.pumpAndSettle();
    expect(find.text('stub:register'), findsOneWidget);
    expect(await _seen(), isTrue);

    // Replaced, not reset: back from register returns to the welcome screen.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('stub:welcome'), findsOneWidget);
  });

  testWidgets('Skip marks the intro seen and goes to register', (tester) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('stub:register'), findsOneWidget);
    expect(await _seen(), isTrue);
  });

  testWidgets('swiping changes the caption', (tester) async {
    await _pumpOnboarding(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('02 / 03'), findsOneWidget);
  });

  testWidgets('back returns to the welcome screen', (tester) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('stub:welcome'), findsOneWidget);
  });
}
