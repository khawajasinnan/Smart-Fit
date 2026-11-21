import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/home/screens/home_dashboard_screen.dart';
import 'package:smartfit/features/home/widgets/home_cards.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_profile_repository.dart';
import '../helpers/fake_wardrobe.dart';
import '../helpers/screenshot_harness.dart';

/// Visual review of Home. Skipped unless SF_SCREENSHOT_DIR is set.
void main() {
  // the app opens Hive in main(); the loved-fits / feedback stores need it
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('sf_home').path));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('home (${mode.name})', (tester) async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      SharedPreferences.setMockInitialValues({
        'streak_user-1_count': 3,
        'streak_user-1_best': 6,
        'streak_user-1_last': yesterday.toIso8601String(),
        'streak_user-1_days': [
          for (var d = 1; d <= 3; d++) DateTime(now.year, now.month, now.day - d).toIso8601String(),
        ],
      });
      final profile = UserProfileModel(
        id: 'user-1',
        fullName: 'Sara Khan',
        dateOfBirth: DateTime(2002, 4, 2),
        gender: 'Female',
        profileCompleted: true,
      );
      await pumpScreen(tester, const HomeDashboardScreen(), mode: mode, overrides: [
        supabaseClientProvider.overrideWithValue(
            SupabaseClient('http://localhost:1', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false))),
        currentUserProvider.overrideWithValue(FakeAuthRepository.fakeUser()),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository(loads: [profile])),
        trendingPicksProvider.overrideWith((ref) async => [for (final s in sampleWardrobe(now)) s.product]),
        wardrobeNotifierProvider.overrideWith((ref) => FakeWardrobe(const [])),
      ]);
      await pumpFrames(tester, const Duration(seconds: 3));
      await saveScreenshot(tester, 'home_top_${mode.name}');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await pumpFrames(tester);
      await saveScreenshot(tester, 'home_middle_${mode.name}');
    }, skip: !screenshotsEnabled);
  }
}
