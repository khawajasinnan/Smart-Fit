/// Every route in the app. Tabs (inside the bottom-navigation shell) are
/// marked; all other routes open full-screen above it.
abstract final class RoutePaths {
  // ── Entry ──
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // ── Onboarding gate (SFR-006 / SFR-013) ──
  static const String profileGate = '/profile-gate';
  static const String profileSetup = '/profile-setup';

  // ── Tabs (SRDS Fig 3.7: Home / Try-On / AI Stylist / Saved / Profile) ──
  static const String home = '/home';
  static const String tryOn = '/try-on';
  static const String chat = '/chat';
  static const String wardrobe = '/wardrobe';
  static const String profile = '/profile';

  /// Settings live on the Profile tab.
  static const String settings = profile;

  // ── Full-screen features ──
  static const String hairstyle = '/hairstyle';
  static const String lookScore = '/scoring';
  static const String admin = '/admin';

  // ── Settings sub-pages (open above the tabs) ──
  static const String privacy = '/privacy';
  static const String help = '/help';
  static const String about = '/about';
}
