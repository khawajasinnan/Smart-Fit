import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  Future<UserProfileModel?> getProfile(String userId) async {
    final response = await _client
        .from(ApiEndpoints.profilesTable)
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (response == null) return null;
    return UserProfileModel.fromJson(response);
  }

  Future<void> upsertProfile(UserProfileModel profile) async {
    try {
      await _client
          .from(ApiEndpoints.profilesTable)
          .upsert(profile.toJson(), onConflict: 'id');
    } on PostgrestException catch (e) {
      if (!_isSchemaMismatch(e)) rethrow;
      await _client
          .from(ApiEndpoints.profilesTable)
          .upsert(profile.toLegacyJson(), onConflict: 'id');
    }
  }

  Future<String> uploadAvatar(
    String userId,
    Uint8List imageBytes, {
    String ext = 'jpg',
  }) async {
    final version = DateTime.now().millisecondsSinceEpoch;
    final path = '$userId/avatar_$version.$ext';
    final contentType = ext.toLowerCase() == 'jpg'
        ? 'image/jpeg'
        : 'image/$ext';
    await _client.storage
        .from(ApiEndpoints.avatarsBucket)
        .uploadBinary(
          path,
          imageBytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final url = _client.storage
        .from(ApiEndpoints.avatarsBucket)
        .getPublicUrl(path);
    return url;
  }

  /// Check if profile is complete.
  /// Uses BOTH the profileCompleted flag AND actual data check.
  /// This handles old profiles that were created before the flag existed.
  Future<bool> isProfileComplete(String userId) async {
    final profile = await getProfile(userId);
    if (profile == null) return false;

    if (profile.isProfileComplete) {
      // Old profile has data but flag is false — fix it
      if (!profile.profileCompleted) {
        try {
          await _client
              .from(ApiEndpoints.profilesTable)
              .update({'profile_completed': true})
              .eq('id', userId);
        } catch (_) {}
      }
      return true;
    }

    return false;
  }

  bool _isSchemaMismatch(PostgrestException e) {
    final message = e.message.toLowerCase();
    return message.contains('column') ||
        message.contains('schema cache') ||
        message.contains('could not find');
  }
}
