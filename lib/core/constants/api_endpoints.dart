/// SmartFit — API Endpoints
/// Update SUPABASE_URL and SUPABASE_ANON_KEY with your actual values
class ApiEndpoints {
  ApiEndpoints._();

  // ─── Supabase Config ───
  static const String supabaseUrl = 'https://krzchbwbqxnantbnkvbw.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtyemNoYndicXhuYW50Ym5rdmJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2MTEwOTcsImV4cCI6MjA5NDE4NzA5N30.7EugeUlWQJWFzgefaP8UUOO_oQOGaKLOSEsTbTwZmw4';

  // ─── Gemini AI Config ───
  static const String geminiApiKey = 'AIzaSyAkwHxOQcPMm9wcfQ5qqp6Cn8KeVM9uWiI';
  static const String geminiModel = 'gemini-2.5-flash';

  // ─── Supabase Tables ───
  static const String profilesTable = 'profiles';
  static const String chatSessionsTable = 'chat_sessions';
  static const String chatMessagesTable = 'chat_messages';
  static const String analysisResultsTable = 'analysis_results';
  static const String userFeedbackTable = 'user_feedback';

  // ─── Storage Buckets ───
  static const String avatarsBucket = 'avatars';
  static const String chatImagesBucket = 'chat-images';

  // ─── FastAPI Backend (for future AI endpoints) ───
  static const String backendBaseUrl = 'http://localhost:8000/api/v1';
  static const String analyzeEndpoint = '$backendBaseUrl/analyze';
  static const String recommendEndpoint = '$backendBaseUrl/recommend';
  static const String chatEndpoint = '$backendBaseUrl/chat';
  static const String scrapeEndpoint = '$backendBaseUrl/scrape';
  static const String tryOnEndpoint = '$backendBaseUrl/tryon';
}
