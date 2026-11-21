import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/data/models/user_model.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/screens/settings_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/screenshot_harness.dart';

class _SignedIn extends AuthNotifier {
  _SignedIn() : super(FakeAuthRepository()) {
    state = const AuthStateModel(
      status: AuthStatus.authenticated,
      user: UserModel(id: 'user-1', email: 'sara@example.com', fullName: 'Sara Khan'),
    );
  }
}

const _full = UserProfileModel(
  id: 'user-1',
  fullName: 'Sara Khan',
  gender: 'female',
  heightCm: 165,
  weightKg: 58,
  bodyType: 'Curvy',
  skinTone: 'Olive',
  budgetMax: 8000,
  stylePreferences: ['Casual', 'Lawn Suit', 'Minimalist'],
);

const _partial = UserProfileModel(id: 'user-1', fullName: 'Sara Khan', gender: 'female');

List<Override> _overrides(UserProfileModel profile) => [
      authNotifierProvider.overrideWith((ref) => _SignedIn()),
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository(loads: [profile])),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, UserProfileModel profile) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(profile),
      child: MaterialApp(theme: AppTheme.lightTheme, home: const SettingsScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows the account and the style profile the picks are built from', (tester) async {
    await pump(tester, _full);
    expect(find.text('Sara Khan'), findsOneWidget);
    expect(find.text('sara@example.com'), findsOneWidget);
    expect(find.text('Your style profile'), findsOneWidget);
    expect(find.text('5/5'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('165 cm · 58 kg'), findsOneWidget);
    expect(find.text('Olive'), findsOneWidget);
    expect(find.text('Budget'), findsNothing); // removed 21 Nov 2026: the budget comes from the chat
    expect(find.text('Lawn Suit'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing details offer "Add" and the count shows what is left', (tester) async {
    await pump(tester, _partial);
    expect(find.text('1/5'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(3)); // height/weight, body type, skin tone
    expect(find.text('Add the styles you love'), findsOneWidget);
  });

  testWidgets('log out asks first', (tester) async {
    await pump(tester, _full);
    await tester.scrollUntilVisible(find.text('Log out'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Log out'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log out?'), findsNothing);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('settings screenshot (${mode.name})', (tester) async {
      await pumpScreen(tester, const SettingsScreen(), mode: mode, overrides: _overrides(_full));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'settings_${mode.name}');
    }, skip: !screenshotsEnabled);
  }
}
