import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/shared_widgets/page_loading_gate.dart';
import 'package:smartfit/core/router/app_shell.dart';
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/router/transitions.dart';
import 'package:smartfit/features/auth/screens/splash_screen.dart';
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/features/auth/screens/login_screen.dart';
import 'package:smartfit/features/auth/screens/register_screen.dart';
import 'package:smartfit/features/auth/screens/forgot_password_screen.dart';
import 'package:smartfit/features/profile/screens/profile_gate_screen.dart';
import 'package:smartfit/features/profile/screens/profile_setup_screen.dart';
import 'package:smartfit/features/chatbot/screens/ai_stylist_chat_screen.dart';
import 'package:smartfit/features/home/screens/home_dashboard_screen.dart';
import 'package:smartfit/features/profile/screens/about_screen.dart';
import 'package:smartfit/features/profile/screens/help_support_screen.dart';
import 'package:smartfit/features/profile/screens/privacy_security_screen.dart';
import 'package:smartfit/features/profile/screens/settings_screen.dart';
import 'package:smartfit/features/admin/screens/admin_panel_screen.dart';
import 'package:smartfit/features/wardrobe/screens/wardrobe_screen.dart';
import 'package:smartfit/features/tryon/screens/tryon_screen.dart';
import 'package:smartfit/features/hairstyle/screens/hairstyle_screen.dart';
import 'package:smartfit/features/scoring/screens/look_score_screen.dart';
import 'package:smartfit/features/scoring/data/look_score_models.dart';

export 'package:smartfit/core/router/route_paths.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Tells GoRouter to re-run its redirect whenever the guard facts change
/// (sign-in, sign-out, profile loaded/completed, ban).
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    _subscription = ref.listen<GuardState>(guardStateProvider, (_, _) => notifyListeners());
  }

  late final ProviderSubscription<GuardState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

/// The app router — created once; navigation rules live in [resolveRedirect].
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(ref.read(guardStateProvider), state.matchedLocation),
    routes: [
      // ── Entry ──
      GoRoute(
        path: RoutePaths.splash,
        // the splash has its own start-up loading bar
        pageBuilder: (context, state) => fadeThroughPage(state, const SplashScreen(), loading: false),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        pageBuilder: (context, state) => sharedAxisPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) => sharedAxisPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: RoutePaths.register,
        pageBuilder: (context, state) => sharedAxisPage(state, const RegisterScreen()),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        pageBuilder: (context, state) => sharedAxisPage(state, const ForgotPasswordScreen()),
      ),

      // ── Mandatory profile (SFR-006 / SFR-013) ──
      GoRoute(
        path: RoutePaths.profileGate,
        pageBuilder: (context, state) => fadeThroughPage(state, const ProfileGateScreen()),
      ),
      GoRoute(
        path: RoutePaths.profileSetup,
        pageBuilder: (context, state) => sharedAxisPage(
          state,
          const ProfileSetupScreen(),
          type: SharedAxisTransitionType.vertical,
        ),
      ),

      // ── The 6 tabs (order = nav bar order; Zayn's chat is the centre, index 3) ──
      StatefulShellRoute(
        // The loader plays once when the tabs appear (after sign-in or
        // onboarding); switching tabs keeps the shell, so it stays instant.
        builder: (context, state, navigationShell) => PageLoadingGate(child: AppShell(navigationShell: navigationShell)),
        navigatorContainerBuilder: (context, navigationShell, children) => FadeThroughBranchContainer(
          currentIndex: navigationShell.currentIndex,
          children: children,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.home, builder: (context, state) => const HomeDashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.tryOn, builder: (context, state) => const TryOnScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.hairstyle, builder: (context, state) => const HairstyleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.chat, builder: (context, state) => const AiStylistChatScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.wardrobe, builder: (context, state) => const WardrobeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RoutePaths.profile, builder: (context, state) => const SettingsScreen()),
          ]),
        ],
      ),

      // ── Full-screen features (open above the tabs) ──
      GoRoute(
        path: RoutePaths.lookScore,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => sharedAxisPage(
          state,
          LookScoreScreen(args: state.extra is LookScoreArgs ? state.extra! as LookScoreArgs : null),
          type: SharedAxisTransitionType.scaled,
        ),
      ),
      GoRoute(
        path: RoutePaths.admin,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => fadeThroughPage(state, const AdminPanelScreen()),
      ),
      GoRoute(
        path: RoutePaths.privacy,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => sharedAxisPage(state, const PrivacySecurityScreen()),
      ),
      GoRoute(
        path: RoutePaths.help,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => sharedAxisPage(state, const HelpSupportScreen()),
      ),
      GoRoute(
        path: RoutePaths.about,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => sharedAxisPage(state, const AboutScreen()),
      ),
      // Old paths kept working.
      GoRoute(path: '/look-score', redirect: (_, _) => RoutePaths.lookScore),
      GoRoute(path: '/settings', redirect: (_, _) => RoutePaths.profile),
    ],
    errorBuilder: (context, state) => const _NotFoundScreen(),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 48),
              const SizedBox(height: 12),
              Text("That page doesn't exist.", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => GoRouter.of(context).go(RoutePaths.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
