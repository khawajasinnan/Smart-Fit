import 'package:flutter/foundation.dart';
import 'package:smartfit/core/router/route_paths.dart';

/// Where the signed-in user's profile stands.
enum ProfileStatus {
  /// Not known yet (first load in progress).
  loading,

  /// The first load failed — the profile gate offers a retry.
  error,

  /// Loaded but the mandatory onboarding isn't finished (SFR-006 / SFR-013).
  incomplete,

  complete,
}

/// Everything the router needs to decide where a user may go.
@immutable
class GuardState {
  const GuardState({
    required this.bootstrapping,
    required this.authed,
    this.isAdmin = false,
    this.profile = ProfileStatus.loading,
    this.restricted = false,
  });

  /// Splash still showing (app start-up).
  final bool bootstrapping;
  final bool authed;
  final bool isAdmin;
  final ProfileStatus profile;

  /// Signed out because the account is banned or suspended.
  final bool restricted;

  @override
  bool operator ==(Object other) =>
      other is GuardState &&
      other.bootstrapping == bootstrapping &&
      other.authed == authed &&
      other.isAdmin == isAdmin &&
      other.profile == profile &&
      other.restricted == restricted;

  @override
  int get hashCode => Object.hash(bootstrapping, authed, isAdmin, profile, restricted);

  @override
  String toString() =>
      'GuardState(boot: $bootstrapping, authed: $authed, admin: $isAdmin, profile: ${profile.name}, restricted: $restricted)';
}

/// Signed-out-only screens. A signed-in user who lands here moves on.
const Set<String> _signedOutOnly = {
  RoutePaths.onboarding,
  RoutePaths.login,
  RoutePaths.register,
};

bool _isEntry(String loc) => loc == RoutePaths.splash || _signedOutOnly.contains(loc);

/// Returns the path to redirect to, or null to stay on [location].
///
/// Rules (SRDS SFR-004 login, SFR-006 / SFR-013 mandatory profile, SFR-039
/// admin):
///  * forgot-password is always reachable (its reset session is temporary);
///  * during start-up everything waits on the splash;
///  * signed-out users only see the splash/welcome and auth screens;
///  * admins go to the admin panel and skip the shopper profile gate;
///  * shoppers can't reach anything until their profile is complete — they
///    are sent straight to profile setup (or to the gate if it failed to load).
String? resolveRedirect(GuardState s, String location) {
  if (location == RoutePaths.forgotPassword) return null;

  if (s.bootstrapping) return location == RoutePaths.splash ? null : RoutePaths.splash;

  if (!s.authed) {
    if (_isEntry(location)) return null;
    return s.restricted ? RoutePaths.login : RoutePaths.splash;
  }

  if (s.isAdmin) {
    if (_isEntry(location) || location == RoutePaths.profileGate || location == RoutePaths.profileSetup) {
      return RoutePaths.admin;
    }
    return null;
  }

  switch (s.profile) {
    case ProfileStatus.loading:
      // Stay on the entry screens (or onboarding) until we know; anything
      // else waits on the splash so no feature shows before the check.
      if (_isEntry(location) || location == RoutePaths.profileGate || location == RoutePaths.profileSetup) {
        return null;
      }
      return RoutePaths.splash;
    case ProfileStatus.error:
      return location == RoutePaths.profileGate ? null : RoutePaths.profileGate;
    case ProfileStatus.incomplete:
      return location == RoutePaths.profileSetup ? null : RoutePaths.profileSetup;
    case ProfileStatus.complete:
      if (_isEntry(location) || location == RoutePaths.profileGate) return RoutePaths.home;
      if (location == RoutePaths.admin || location.startsWith('${RoutePaths.admin}/')) {
        return RoutePaths.home; // shoppers can't open the admin panel
      }
      return null;
  }
}
