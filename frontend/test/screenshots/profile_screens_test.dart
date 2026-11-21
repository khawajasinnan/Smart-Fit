import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/screens/profile_gate_screen.dart';
import 'package:smartfit/features/profile/screens/profile_setup_screen.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_profile_repository.dart';
import '../helpers/screenshot_harness.dart';

/// Visual review of the profile screens. Skipped unless SF_SCREENSHOT_DIR
/// is set (see screenshot_harness.dart).
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode.name;

    testWidgets('profile gate ($suffix)', (tester) async {
      await pumpScreen(
        tester,
        const ProfileGateScreen(),
        mode: mode,
        overrides: [
          currentUserProvider.overrideWithValue(FakeAuthRepository.fakeUser()),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository(loads: [Exception('offline')])),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
      );
      await pumpFrames(tester);
      await saveScreenshot(tester, 'profile_gate_$suffix');
    }, skip: !screenshotsEnabled);

    // Photo from the local Unsplash set so the avatar renders.
    const partial = UserProfileModel(
      id: 'user-1',
      photoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
      gender: 'Female',
      phone: '03001234567',
      ethnicity: 'Punjabi',
      bodyType: 'Curvy',
      skinTone: 'Olive',
      stylePreferences: ['Casual', 'Lawn Suit', 'Minimalist'],
    );
    List<Override> setupOverrides(FakeAuthRepository auth) => [
          currentUserProvider.overrideWithValue(FakeAuthRepository.fakeUser()),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository(loads: [partial])),
          authRepositoryProvider.overrideWithValue(auth),
        ];

    testWidgets('profile setup: steps + celebration ($suffix)', (tester) async {
      await pumpScreen(tester, const ProfileSetupScreen(), mode: mode, overrides: setupOverrides(FakeAuthRepository()));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'setup_1_basics_$suffix');
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'setup_2_body_$suffix');
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'setup_3_style_$suffix');
      await tester.tap(find.text('Finish'));
      await pumpFrames(tester, const Duration(milliseconds: 700));
      await saveScreenshot(tester, 'setup_4_celebration_$suffix');
    }, skip: !screenshotsEnabled);

    testWidgets('profile setup: photo sheet ($suffix)', (tester) async {
      await pumpScreen(tester, const ProfileSetupScreen(), mode: mode, overrides: setupOverrides(FakeAuthRepository()));
      await pumpFrames(tester);
      await tester.tap(find.bySemanticsLabel('Change profile photo'));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'setup_photo_sheet_$suffix');
    }, skip: !screenshotsEnabled);
  }
}
