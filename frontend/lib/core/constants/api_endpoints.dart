import 'package:smartfit/core/constants/env.dart';

/// SmartFit — API endpoints, Supabase table and bucket names.
///
/// No secrets live here: keys and URLs come from [Env] (build-time defines).
class ApiEndpoints {
  ApiEndpoints._();

  // ─── Admin ───
  static String get adminEmail => Env.adminEmail;

  // ─── Supabase Tables ───
  static const String profilesTable = 'profiles';
  static const String chatSessionsTable = 'chat_sessions';
  static const String chatMessagesTable = 'chat_messages';
  static const String analysisResultsTable = 'analysis_results';
  static const String userFeedbackTable = 'user_feedback';
  static const String savedProductsTable = 'saved_products';

  // ─── Storage Buckets ───
  static const String avatarsBucket = 'avatars';
  static const String chatImagesBucket = 'chat-images';

  // ─── SmartFit API gateway (backend/gateway) — paths relative to Env.apiBaseUrl ───
  static const String chatPath = '/chat';
  static const String scrapeRecommendPath = '/scrape/recommend';
  static const String cvAnalyzePath = '/cv/analyze';
  static const String skinToneAnalyzePath = '/skin-tone/analyze';
  static const String skinTonePalettePath = '/skin-tone/palette';
  static const String cultureGuidePath = '/culture/guide';
  static const String accountPath = '/account';
  static const String tryOnPath = '/tryon';
  static const String tryOnSignPath = '/tryon/sign';
  static const String hairstylesPath = '/hairstyles';
  static const String hairstyleFaceCheckPath = '/hairstyles/face-check';
  static const String lookScorePath = '/score';
  static const String lookFeedbackPath = '/feedback';
}
