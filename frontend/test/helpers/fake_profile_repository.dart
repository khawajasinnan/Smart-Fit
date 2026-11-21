import 'dart:typed_data';

import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/repositories/profile_repository.dart';

/// In-memory ProfileRepository for widget tests.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({List<Object?>? loads, this.saveError}) : loads = loads ?? [null];

  /// Successive [getProfile] results: a UserProfileModel/null is returned,
  /// anything else is thrown. The last entry repeats.
  final List<Object?> loads;

  /// Thrown by [upsertProfile] when set.
  Object? saveError;

  final List<String> calls = [];
  final List<UserProfileModel> saved = [];
  int _loadIndex = 0;

  @override
  Future<UserProfileModel?> getProfile(String userId) async {
    calls.add('get:$userId');
    final result = loads[_loadIndex.clamp(0, loads.length - 1)];
    _loadIndex++;
    if (result == null || result is UserProfileModel) return result as UserProfileModel?;
    throw result;
  }

  @override
  Future<void> upsertProfile(UserProfileModel profile) async {
    calls.add('upsert:${profile.id}');
    if (saveError != null) throw saveError!;
    saved.add(profile);
  }

  final List<Map<String, dynamic>> extras = [];

  @override
  Future<void> saveExtras(UserProfileModel profile) async {
    calls.add('extras:${profile.id}');
    extras.add(profile.extrasJson());
  }

  @override
  Future<String> uploadAvatar(String userId, Uint8List imageBytes, {String ext = 'jpg'}) async {
    calls.add('avatar:$userId');
    return 'https://example.com/avatars/$userId.jpg';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeProfileRepository.${invocation.memberName} not scripted');
}
