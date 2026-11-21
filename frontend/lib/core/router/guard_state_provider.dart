import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/constants/env.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';

/// How long the start-up splash and its loading bar run (2-3 s brand moment).
const Duration kSplashMinimum = Duration(milliseconds: 2500);

/// Minimum time the splash stays up at start-up, so the brand moment isn't a
/// flicker. Overridden with an instantly-complete value in tests.
final splashMinimumProvider = FutureProvider<void>(
  (ref) => Future<void>.delayed(kSplashMinimum),
);

/// The facts the router guard decides on. Recomputed whenever sign-in state
/// or the user's profile changes; the router refreshes on every change.
final guardStateProvider = Provider<GuardState>((ref) {
  final bootstrapping = ref.watch(splashMinimumProvider).isLoading;
  final auth = ref.watch(authNotifierProvider);
  final user = auth.user;

  if (user == null) {
    return GuardState(
      bootstrapping: bootstrapping,
      authed: false,
      restricted: auth.restrictionMessage != null,
    );
  }

  if (user.email.toLowerCase() == Env.adminEmail.toLowerCase()) {
    return GuardState(bootstrapping: bootstrapping, authed: true, isAdmin: true);
  }

  final profileAsync = ref.watch(profileNotifierProvider(user.id));
  final ProfileStatus profile;
  if (profileAsync.hasValue) {
    profile = (profileAsync.value?.isProfileComplete ?? false) ? ProfileStatus.complete : ProfileStatus.incomplete;
  } else if (profileAsync.hasError) {
    profile = ProfileStatus.error;
  } else {
    profile = ProfileStatus.loading;
  }

  return GuardState(bootstrapping: bootstrapping, authed: true, profile: profile);
});
