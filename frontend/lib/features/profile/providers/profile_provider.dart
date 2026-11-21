import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in user's profile. The router reads this to enforce the
/// mandatory-profile gate (SFR-006 / SFR-013), so the state only becomes an
/// error when the profile genuinely can't be loaded — never because a later
/// save failed.
class ProfileNotifier extends StateNotifier<AsyncValue<UserProfileModel?>> {
  final ProfileRepository _repo;
  final String _userId;

  ProfileNotifier(this._repo, this._userId)
    : super(const AsyncValue.loading()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    // Keep the current profile visible while refreshing.
    state = const AsyncLoading<UserProfileModel?>().copyWithPrevious(state);
    try {
      final profile = await _repo.getProfile(_userId);
      if (mounted) state = AsyncValue.data(profile);
    } catch (e, st) {
      if (mounted) state = AsyncValue<UserProfileModel?>.error(e, st).copyWithPrevious(state);
    }
  }

  /// Saves the profile. On failure the previous profile is kept and the
  /// error is rethrown so the screen can tell the user.
  Future<void> updateProfile(UserProfileModel profile) async {
    await _repo.upsertProfile(profile);
    if (mounted) state = AsyncValue.data(profile);
  }

  Future<String> uploadAvatar(Uint8List bytes) {
    return _repo.uploadAvatar(_userId, bytes);
  }

  void updateLocal(UserProfileModel profile) {
    state = AsyncValue.data(profile);
  }
}

final profileNotifierProvider =
    StateNotifierProvider.family<
      ProfileNotifier,
      AsyncValue<UserProfileModel?>,
      String
    >((ref, userId) {
      final repo = ref.watch(profileRepositoryProvider);
      return ProfileNotifier(repo, userId);
    });
