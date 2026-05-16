import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/features/auth/screens/splash_screen.dart';
import 'package:smartfit/features/auth/screens/onboarding_screen.dart';
import 'package:smartfit/features/auth/screens/login_screen.dart';
import 'package:smartfit/features/auth/screens/register_screen.dart';
import 'package:smartfit/features/auth/screens/forgot_password_screen.dart';
import 'package:smartfit/features/profile/screens/profile_gate_screen.dart';
import 'package:smartfit/features/profile/screens/profile_setup_screen.dart';
import 'package:smartfit/features/chat/screens/ai_stylist_chat_screen.dart';
import 'package:smartfit/features/home/screens/home_dashboard_screen.dart';
import 'package:smartfit/features/settings/screens/settings_screen.dart';

/// Route paths
class RoutePaths {
  RoutePaths._();
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String profileGate = '/profile-gate';
  static const String profileSetup = '/profile-setup';
  static const String chat = '/chat';
  static const String home = '/home';
  static const String settings = '/settings';
}

/// GoRouter provider
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: 'forgotPassword',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.profileGate,
        name: 'profileGate',
        builder: (context, state) => const ProfileGateScreen(),
      ),
      GoRoute(
        path: RoutePaths.profileSetup,
        name: 'profileSetup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: RoutePaths.chat,
        name: 'chat',
        builder: (context, state) => const AiStylistChatScreen(),
      ),
      GoRoute(
        path: RoutePaths.home,
        name: 'home',
        builder: (context, state) => const HomeDashboardScreen(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],

    // ─── Error page ───
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.uri}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );
});
