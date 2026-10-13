/// SmartFit — API Endpoints
class ApiEndpoints {
  ApiEndpoints._();

  // ─── Supabase Config ───
  static const String supabaseUrl = 'https://krzchbwbqxnantbnkvbw.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtyemNoYndicXhuYW50Ym5rdmJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2MTEwOTcsImV4cCI6MjA5NDE4NzA5N30.7EugeUlWQJWFzgefaP8UUOO_oQOGaKLOSEsTbTwZmw4';

  // ─── Gemini AI Config ───
  static const String geminiApiKey = 'AIzaSyAtoiGBlOBIBJqNZ6CWFqMLQIoO4RypLJA';
  static const String geminiModel = 'gemini-2.5-flash';

  // ─── Trend & Image API Config ───
  static const String trendApiKey = 'bQhZ9i97uK2x14P27g7a6bE2c1d9f8e7_smartfit_trend_key';
  static const String trendApiBaseUrl = 'https://api.unsplash.com';

  // ─── Admin ───
  static const String adminEmail = 'admin@smartfit.pk';

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

  // ─── FastAPI Backend ───
  // Web: 127.0.0.1:8000
  // Android Emulator: 10.0.2.2:8000
  // Physical Mobile Phone (Same Wi-Fi): Your PC's LAN IP e.g. 192.168.0.132:8000
  static String get backendBaseUrl {
    // For physical device over USB (with adb reverse) or Web:
    return 'http://127.0.0.1:8000/api/v1';
    // For wireless Wi-Fi (without USB): 'http://192.168.0.132:8000/api/v1'
    // For Android Emulator: 'http://10.0.2.2:8000/api/v1'
  }

  static String get analyzeEndpoint => '$backendBaseUrl/analyze';
  static String get recommendEndpoint => '$backendBaseUrl/recommend';
  static String get chatEndpoint => '$backendBaseUrl/chat';
  static String get scrapeEndpoint => '$backendBaseUrl/scrape';
  static String get scrapeRecommendEndpoint =>
      '$backendBaseUrl/scrape/recommend';
  static String get tryOnEndpoint => '$backendBaseUrl/tryon';
  static String get cvAnalyzeEndpoint => '$backendBaseUrl/cv/analyze';
}
