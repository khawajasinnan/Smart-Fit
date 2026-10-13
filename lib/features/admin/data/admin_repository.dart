import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';

class AdminRepository {
  final SupabaseClient _client;

  AdminRepository(this._client);

  bool get isCurrentUserAdmin =>
      (_client.auth.currentUser?.email ?? '').toLowerCase() ==
      ApiEndpoints.adminEmail.toLowerCase();

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    _ensureAdmin();
    final rows = await _client
        .from(ApiEndpoints.profilesTable)
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> fetchRecentMessages() async {
    _ensureAdmin();
    final messageRows = await _client
        .from(ApiEndpoints.chatMessagesTable)
        .select()
        .order('created_at', ascending: false);
    final messages = List<Map<String, dynamic>>.from(messageRows as List);
    if (messages.isEmpty) return messages;

    final sessions = await _client
        .from(ApiEndpoints.chatSessionsTable)
        .select('id, user_id, title')
        .order('updated_at', ascending: false);
    final sessionById = {
      for (final row in List<Map<String, dynamic>>.from(sessions as List))
        row['id'] as String: row,
    };

    final profiles = await _client
        .from(ApiEndpoints.profilesTable)
        .select(
          'id, full_name, username, email, is_banned, suspended_until, suspension_reason',
        );
    final profileById = {
      for (final row in List<Map<String, dynamic>>.from(profiles as List))
        row['id'] as String: row,
    };

    for (final message in messages) {
      final session = sessionById[message['session_id']];
      if (session == null) continue;
      final profile = profileById[session['user_id']];
      message['chat_sessions'] = {
        ...session,
        if (profile != null) 'profiles': profile,
      };
    }
    return messages;
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> setBan({
    required String userId,
    required bool banned,
    String? reason,
  }) async {
    _ensureAdmin();
    await _client
        .from(ApiEndpoints.profilesTable)
        .update({
          'is_banned': banned,
          'ban_reason': banned
              ? (reason?.trim().isEmpty == false
                    ? reason!.trim()
                    : 'Policy violation')
              : null,
          'banned_at': banned ? DateTime.now().toIso8601String() : null,
          'suspended_until': null,
          'suspension_reason': null,
          'suspended_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<void> suspendUser({
    required String userId,
    required Duration duration,
    String? reason,
  }) async {
    _ensureAdmin();
    await _client
        .from(ApiEndpoints.profilesTable)
        .update({
          'suspended_until': DateTime.now()
              .toUtc()
              .add(duration)
              .toIso8601String(),
          'suspension_reason': reason?.trim().isNotEmpty == true
              ? reason!.trim()
              : 'Temporary safety suspension',
          'suspended_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<void> clearSuspension(String userId) async {
    _ensureAdmin();
    await _client
        .from(ApiEndpoints.profilesTable)
        .update({
          'suspended_until': null,
          'suspension_reason': null,
          'suspended_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<void> markMessageReviewed(String messageId) async {
    _ensureAdmin();
    await _client.rpc(
      'admin_mark_message_reviewed',
      params: {'message_id_input': messageId},
    );
  }

  void _ensureAdmin() {
    if (!isCurrentUserAdmin) {
      throw Exception(
        'Admin access is restricted to ${ApiEndpoints.adminEmail}.',
      );
    }
  }
}
