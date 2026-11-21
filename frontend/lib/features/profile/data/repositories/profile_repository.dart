import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';

class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  /// This device's copy of the fields saved apart from the profile row (skin undertone,
  /// usual size): they still work before migration 20261121000100 adds their columns.
  /// Deleted with the account (AuthNotifier.deleteAccount).
  static String extrasBoxName(String userId) => 'smartfit_profile_$userId';

  Future<UserProfileModel?> getProfile(String userId) async {
    final response = await _client
        .from(ApiEndpoints.profilesTable)
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (response == null) return null;
    final profile = UserProfileModel.fromJson(response);
    final local = await _readLocalExtras(userId);
    return profile.copyWith(
      skinUndertone: profile.skinUndertone ?? local['skin_undertone'] as String?,
      usualSize: profile.usualSize ?? local['usual_size'] as String?,
    );
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
    await saveExtras(profile);
  }

  /// Skin undertone and usual size: kept on this device, and in the profile row when its
  /// columns exist. Never fails the save that calls it.
  Future<void> saveExtras(UserProfileModel profile) async {
    final extras = profile.extrasJson()..removeWhere((_, v) => v == null);
    if (extras.isEmpty) return;
    try {
      final box = await Hive.openBox<String>(extrasBoxName(profile.id));
      await box.put('extras', jsonEncode(extras));
    } catch (e) {
      debugPrint('[Profile] local extras not saved: $e');
    }
    try {
      await _client.from(ApiEndpoints.profilesTable).update(extras).eq('id', profile.id);
    } catch (e) {
      debugPrint('[Profile] undertone/usual size kept on this device only (migration not applied?): $e');
    }
  }

  Future<Map<String, dynamic>> _readLocalExtras(String userId) async {
    try {
      final box = await Hive.openBox<String>(extrasBoxName(userId));
      final raw = box.get('extras');
      return raw == null ? const {} : (jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const {};
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
