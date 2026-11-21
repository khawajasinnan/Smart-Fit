import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;
import 'package:smartfit/core/router/guard_state_provider.dart';
import 'package:smartfit/core/router/guards.dart';
import 'package:smartfit/features/auth/data/models/user_model.dart';
import 'package:smartfit/features/auth/data/repositories/auth_repository.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super(_FakeAuthRepository());
  void emit(AuthStateModel next) => state = next;
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.next);
  Future<UserProfileModel?> Function() next;
  @override
  Future<UserProfileModel?> getProfile(String userId) => next();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _shopper = UserModel(id: 'u1', email: 'ayesha@example.com');
const _admin = UserModel(id: 'a1', email: 'Admin@SmartFit.pk');
final _complete = UserProfileModel(id: 'u1', profileCompleted: true, dateOfBirth: DateTime(2000, 5, 14));
const _incomplete = UserProfileModel(id: 'u1');

void main() {
  late _FakeAuthNotifier auth;
  late _FakeProfileRepository profiles;
  late ProviderContainer container;

  setUp(() {
    auth = _FakeAuthNotifier();
    profiles = _FakeProfileRepository(() async => _complete);
    container = ProviderContainer(overrides: [
      splashMinimumProvider.overrideWith((ref) async {}),
      authNotifierProvider.overrideWith((ref) => auth),
      profileRepositoryProvider.overrideWithValue(profiles),
    ]);
    addTearDown(container.dispose);
  });

  /// Reads the guard (which starts any profile load), lets pending async work
  /// finish, then reads the settled state.
  Future<GuardState> settle() async {
    await container.read(splashMinimumProvider.future);
    container.read(guardStateProvider);
    await Future<void>.delayed(Duration.zero);
    return container.read(guardStateProvider);
  }

  test('bootstrapping until the splash minimum has passed', () async {
    final slow = Completer<void>();
    final c = ProviderContainer(overrides: [
      splashMinimumProvider.overrideWith((ref) => slow.future),
      authNotifierProvider.overrideWith((ref) => auth),
    ]);
    addTearDown(c.dispose);
    expect(c.read(guardStateProvider).bootstrapping, isTrue);
    slow.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(guardStateProvider).bootstrapping, isFalse);
  });

  test('signed out', () async {
    expect(await settle(), const GuardState(bootstrapping: false, authed: false));
  });

  test('signed out because of a ban is marked restricted', () async {
    auth.emit(const AuthStateModel(status: AuthStatus.error, restrictionMessage: 'Banned'));
    expect((await settle()).restricted, isTrue);
  });

  test('admin email (any case) skips the profile check', () async {
    auth.emit(const AuthStateModel(status: AuthStatus.authenticated, user: _admin));
    final s = await settle();
    expect(s.isAdmin, isTrue);
    expect(s.authed, isTrue);
  });

  test('shopper profile: loading -> complete', () async {
    final pending = Completer<UserProfileModel?>();
    profiles.next = () => pending.future;
    auth.emit(const AuthStateModel(status: AuthStatus.authenticated, user: _shopper));
    expect((await settle()).profile, ProfileStatus.loading);
    pending.complete(_complete);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(guardStateProvider).profile, ProfileStatus.complete);
  });

  test('no profile row or unfinished onboarding -> incomplete', () async {
    profiles.next = () async => null;
    auth.emit(const AuthStateModel(status: AuthStatus.authenticated, user: _shopper));
    expect((await settle()).profile, ProfileStatus.incomplete);

    profiles.next = () async => _incomplete;
    await container.read(profileNotifierProvider('u1').notifier).loadProfile();
    expect(container.read(guardStateProvider).profile, ProfileStatus.incomplete);
  });

  test('first load failing -> error; a failed refresh keeps the known profile', () async {
    profiles.next = () async => throw Exception('offline');
    auth.emit(const AuthStateModel(status: AuthStatus.authenticated, user: _shopper));
    expect((await settle()).profile, ProfileStatus.error);

    profiles.next = () async => _complete;
    await container.read(profileNotifierProvider('u1').notifier).loadProfile();
    expect(container.read(guardStateProvider).profile, ProfileStatus.complete);

    profiles.next = () async => throw Exception('offline again');
    await container.read(profileNotifierProvider('u1').notifier).loadProfile();
    expect(container.read(guardStateProvider).profile, ProfileStatus.complete);
  });
}
