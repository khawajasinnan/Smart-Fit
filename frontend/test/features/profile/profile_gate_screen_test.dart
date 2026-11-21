import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/screens/profile_gate_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

Future<ProviderContainer> _pumpGate(WidgetTester tester, FakeProfileRepository profiles, FakeAuthRepository auth) async {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(FakeAuthRepository.fakeUser()),
      profileRepositoryProvider.overrideWithValue(profiles),
      authRepositoryProvider.overrideWithValue(auth),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const ProfileGateScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('retry reloads the profile; success clears the error state', (tester) async {
    final profiles = FakeProfileRepository(loads: [Exception('offline'), const UserProfileModel(id: 'user-1')]);
    final container = await _pumpGate(tester, profiles, FakeAuthRepository());
    final provider = profileNotifierProvider('user-1');

    expect(container.read(provider).hasError, isTrue);
    expect(find.text("We couldn't load your profile"), findsOneWidget);
    expect(find.text('Signed in as sara@example.com'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(profiles.calls, ['get:user-1', 'get:user-1']);
    expect(container.read(provider).hasValue, isTrue);
    expect(container.read(provider).hasError, isFalse);
  });

  testWidgets('log out signs the user out', (tester) async {
    final auth = FakeAuthRepository();
    await _pumpGate(tester, FakeProfileRepository(loads: [Exception('offline')]), auth);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(auth.calls, contains('signOut'));
  });
}
