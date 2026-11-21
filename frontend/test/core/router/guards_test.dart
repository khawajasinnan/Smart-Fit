import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/core/router/route_paths.dart';

const _signedOut = GuardState(bootstrapping: false, authed: false);
GuardState _shopper(ProfileStatus p) => GuardState(bootstrapping: false, authed: true, profile: p);
const _admin = GuardState(bootstrapping: false, authed: true, isAdmin: true);

const _tabs = [RoutePaths.home, RoutePaths.tryOn, RoutePaths.chat, RoutePaths.wardrobe, RoutePaths.profile];
const _features = [RoutePaths.hairstyle, RoutePaths.lookScore];
const _entry = [RoutePaths.splash, RoutePaths.onboarding, RoutePaths.login, RoutePaths.register];

void main() {
  test('forgot password is always reachable (temporary recovery session)', () {
    for (final s in [
      const GuardState(bootstrapping: true, authed: false),
      _signedOut,
      _shopper(ProfileStatus.incomplete),
      _admin,
    ]) {
      expect(resolveRedirect(s, RoutePaths.forgotPassword), isNull, reason: '$s');
    }
  });

  test('start-up: everything waits on the splash', () {
    const boot = GuardState(bootstrapping: true, authed: true, profile: ProfileStatus.complete);
    expect(resolveRedirect(boot, RoutePaths.splash), isNull);
    for (final loc in [..._tabs, RoutePaths.login, RoutePaths.admin]) {
      expect(resolveRedirect(boot, loc), RoutePaths.splash, reason: loc);
    }
  });

  group('signed out', () {
    test('may use the welcome and auth screens', () {
      for (final loc in _entry) {
        expect(resolveRedirect(_signedOut, loc), isNull, reason: loc);
      }
    });

    test('is sent to welcome from anything protected', () {
      for (final loc in [..._tabs, ..._features, RoutePaths.admin, RoutePaths.profileSetup, RoutePaths.profileGate]) {
        expect(resolveRedirect(_signedOut, loc), RoutePaths.splash, reason: loc);
      }
    });

    test('a banned/suspended user lands on login (which explains why)', () {
      const restricted = GuardState(bootstrapping: false, authed: false, restricted: true);
      expect(resolveRedirect(restricted, RoutePaths.home), RoutePaths.login);
      expect(resolveRedirect(restricted, RoutePaths.login), isNull);
    });
  });

  group('shopper with an incomplete profile (SFR-006 / SFR-013)', () {
    final s = _shopper(ProfileStatus.incomplete);

    test('can reach nothing but profile setup', () {
      for (final loc in [..._entry, ..._tabs, ..._features, RoutePaths.profileGate, RoutePaths.admin]) {
        expect(resolveRedirect(s, loc), RoutePaths.profileSetup, reason: loc);
      }
      expect(resolveRedirect(s, RoutePaths.profileSetup), isNull);
    });
  });

  group('shopper with a complete profile', () {
    final s = _shopper(ProfileStatus.complete);

    test('uses tabs, features and edits their profile freely', () {
      for (final loc in [..._tabs, ..._features, RoutePaths.profileSetup]) {
        expect(resolveRedirect(s, loc), isNull, reason: loc);
      }
    });

    test('entry screens and the gate move on to home', () {
      for (final loc in [..._entry, RoutePaths.profileGate]) {
        expect(resolveRedirect(s, loc), RoutePaths.home, reason: loc);
      }
    });

    test('cannot open the admin panel', () {
      expect(resolveRedirect(s, RoutePaths.admin), RoutePaths.home);
    });
  });

  group('while the profile is loading', () {
    final s = _shopper(ProfileStatus.loading);

    test('no feature shows before the check', () {
      for (final loc in [..._tabs, ..._features]) {
        expect(resolveRedirect(s, loc), RoutePaths.splash, reason: loc);
      }
    });

    test('entry and onboarding screens stay put', () {
      for (final loc in [..._entry, RoutePaths.profileSetup, RoutePaths.profileGate]) {
        expect(resolveRedirect(s, loc), isNull, reason: loc);
      }
    });
  });

  test('profile failed to load -> the retry gate', () {
    final s = _shopper(ProfileStatus.error);
    for (final loc in [..._tabs, RoutePaths.splash, RoutePaths.profileSetup]) {
      expect(resolveRedirect(s, loc), RoutePaths.profileGate, reason: loc);
    }
    expect(resolveRedirect(s, RoutePaths.profileGate), isNull);
  });

  group('admin', () {
    test('lands on the admin panel from entry/onboarding screens', () {
      for (final loc in [..._entry, RoutePaths.profileGate, RoutePaths.profileSetup]) {
        expect(resolveRedirect(_admin, loc), RoutePaths.admin, reason: loc);
      }
    });

    test('may also browse the app', () {
      for (final loc in [RoutePaths.admin, ..._tabs]) {
        expect(resolveRedirect(_admin, loc), isNull, reason: loc);
      }
    });
  });

  test('GuardState equality drives router refreshes', () {
    expect(_shopper(ProfileStatus.complete), _shopper(ProfileStatus.complete));
    expect(_shopper(ProfileStatus.complete) == _shopper(ProfileStatus.loading), isFalse);
  });
}
