import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';

import '../../helpers/fake_auth_repository.dart';

class _Profiles implements ProfileRepository {
  _Profiles(this.row);

  /// The `profiles` row as the database returns it (null = no row yet).
  Map<String, dynamic>? row;

  @override
  Future<UserProfileModel?> getProfile(String userId) async => row == null ? null : UserProfileModel.fromJson(row!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The row `handle_new_user` (supabase baseline migration) creates for a Google
/// sign-up: Google gives a name and a photo, never a date of birth.
Map<String, dynamic> googleTriggerRow(String id) => {
      'id': id,
      'full_name': 'Sara Khan',
      'date_of_birth': null,
      'avatar_url': 'https://lh3.googleusercontent.com/a/sara',
    };

/// The whole path a "Continue with Google" user takes when the browser hands
/// them back: Supabase's signed-in event -> AuthNotifier -> the profile load ->
/// the router guard. SFR-006 / SFR-013: the first time, profile setup; after
/// finishing it, never again.
void main() {
  late FakeAuthRepository auth;
  late _Profiles profiles;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository();
    profiles = _Profiles(null);
    container = ProviderContainer(overrides: [
      splashMinimumProvider.overrideWith((ref) async {}),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profiles),
    ]);
    addTearDown(container.dispose);
  });

  /// Signs in through Google and returns where the router sends the user from
  /// [from] once everything has loaded.
  Future<String?> googleSignIn({String from = RoutePaths.login}) async {
    await container.read(splashMinimumProvider.future);
    container.read(authNotifierProvider); // starts the auth listener
    auth.emitSignedIn(FakeAuthRepository.fakeUser(viaOAuth: true));
    for (var i = 0; i < 5; i++) {
      container.read(guardStateProvider); // starts the profile load
      await Future<void>.delayed(Duration.zero);
    }
    final guard = container.read(guardStateProvider);
    expect(guard.authed, isTrue);
    return resolveRedirect(guard, from);
  }

  test('a brand-new Google user goes to profile setup, from any screen', () async {
    profiles.row = googleTriggerRow('user-1');
    expect(await googleSignIn(), RoutePaths.profileSetup);
    for (final screen in [RoutePaths.splash, RoutePaths.register, RoutePaths.home, RoutePaths.chat, RoutePaths.tryOn]) {
      expect(resolveRedirect(container.read(guardStateProvider), screen), RoutePaths.profileSetup, reason: screen);
    }
  });

  test('a Google user whose profile row has not appeared yet also goes to profile setup', () async {
    expect(await googleSignIn(from: RoutePaths.splash), RoutePaths.profileSetup);
  });

  test('no date of birth is never complete, even if the row says so', () async {
    profiles.row = {...googleTriggerRow('user-1'), 'profile_completed': true, 'gender': 'female'};
    expect(await googleSignIn(), RoutePaths.profileSetup);
  });

  test('only the first time: once setup is finished, Google sign-in goes home', () async {
    profiles.row = {...googleTriggerRow('user-1'), 'profile_completed': true, 'date_of_birth': '2000-05-14'};
    expect(await googleSignIn(), RoutePaths.home);
  });
}
