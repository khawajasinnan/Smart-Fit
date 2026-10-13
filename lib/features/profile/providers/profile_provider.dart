import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

class ProfileNotifier extends StateNotifier<AsyncValue<UserProfileModel?>> {
  final ProfileRepository _repo;
  final String _userId;

  ProfileNotifier(this._repo, this._userId)
    : super(const AsyncValue.loading()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    state = const AsyncValue.loading();
    try {
      final profile = await _repo.getProfile(_userId);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateProfile(UserProfileModel profile) async {
    try {
      await _repo.upsertProfile(profile);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
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
