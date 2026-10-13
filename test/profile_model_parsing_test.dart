import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

void main() {
  test(
    'fromJson supports alternate DB column names and profile_completed alias',
    () {
      final json1 = {
        'id': 'user-1',
        'full_name': 'Alice',
        'gender': 'Female',
        'height': 165,
        'weight': 60,
        'avatar_url': 'https://example.com/a.jpg',
        'body_type': 'Slim',
        'profile_completed': true,
      };

      final p1 = UserProfileModel.fromJson(json1);
      expect(p1.heightCm, 165.0);
      expect(p1.weightKg, 60.0);
      expect(p1.photoUrl, 'https://example.com/a.jpg');
      expect(p1.profileCompleted, true);

      final json2 = {
        'id': 'user-2',
        'full_name': 'Bob',
        'gender': 'Male',
        'height_cm': 180.5,
        'weight_kg': 80,
        'photo_url': 'https://example.com/b.jpg',
        'body_type': 'Athletic',
        // older DB uses `is_complete` instead of `profile_completed`
        'is_complete': true,
      };

      final p2 = UserProfileModel.fromJson(json2);
      expect(p2.heightCm, 180.5);
      expect(p2.weightKg, 80.0);
      expect(p2.photoUrl, 'https://example.com/b.jpg');
      expect(p2.profileCompleted, true);

      final json3 = {'id': 'user-3', 'gender': null};
      final p3 = UserProfileModel.fromJson(json3);
      expect(p3.profileCompleted, false);
    },
  );

  test('profile completion requires recommendation-critical setup data', () {
    final flaggedProfile = UserProfileModel.fromJson({
      'id': 'user-1',
      'profile_completed': true,
    });
    expect(flaggedProfile.isProfileComplete, true);

    final completedProfile = UserProfileModel.fromJson({
      'id': 'user-2',
      'gender': 'Male',
      'phone': '+923001234567',
      'height': 180,
      'weight': 82,
      'body_type': 'Athletic',
      'avatar_url': 'https://example.com/a.jpg',
      'skin_tone': 'Medium',
      'ethnicity': 'Punjabi',
      'chest_cm': 100,
      'waist_cm': 84,
      'hip_cm': 98,
      'style_vibe': 'Clean',
    });
    expect(completedProfile.stylePreferences, ['Clean']);
    expect(completedProfile.isProfileComplete, true);

    final partialProfile = UserProfileModel.fromJson({
      'id': 'user-3',
      'gender': 'Female',
      'height_cm': 165,
      'body_type': 'Slim',
    });
    expect(partialProfile.isProfileComplete, false);
  });

  test('toLegacyJson writes columns used by the bundled Supabase schema', () {
    final profile = UserProfileModel(
      id: 'user-1',
      fullName: 'Alice',
      gender: 'Female',
      heightCm: 165,
      weightKg: 60,
      bodyType: 'Slim',
      photoUrl: 'https://example.com/a.jpg',
      stylePreferences: const ['Streetwear', 'Formal'],
      profileCompleted: true,
    );

    expect(profile.toLegacyJson(), {
      'id': 'user-1',
      'full_name': 'Alice',
      'gender': 'Female',
      'height': 165,
      'weight': 60,
      'body_type': 'Slim',
      'avatar_url': 'https://example.com/a.jpg',
      'style_vibe': 'Streetwear',
      'profile_completed': true,
    });
  });
}
