import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smartfit/core/constants/env.dart';
import 'package:smartfit/core/utils/auth_url_cleanup.dart';
import 'package:smartfit/core/providers/theme_provider.dart';
import 'package:smartfit/app.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/features/chatbot/notifications/zayn_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // End-to-end tests (Playwright, e2e/) drive the web build through the accessibility
  // tree, which the web only builds on request. Only in builds made with --dart-define=E2E=true.
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Config comes from --dart-define or the bundled env/dev.json (see
  // core/constants/env.dart). Without it Supabase can't start, so explain
  // how to fix it instead of crashing.
  await Env.load();
  if (Env.missing.isNotEmpty) {
    runApp(ConfigErrorApp(missing: Env.missing));
    return;
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
  // Google sign-in on the web returns with ?code=...; it has been used now.
  clearAuthCallbackFromUrl();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  final themeMode = await ThemeNotifier.loadSaved();

  // iOS needs the notification button sets before notifications start.
  NotificationService.instance.darwinCategories = zaynDarwinCategories();

  runApp(
    ProviderScope(
      overrides: [themeProvider.overrideWith((ref) => ThemeNotifier(themeMode))],
      child: const SmartFitApp(),
    ),
  );
}

/// Shown only to developers who run the app without its env file.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFCF4FB),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings_suggest_rounded, size: 48, color: Color(0xFF0A7D3B)),
                const SizedBox(height: 16),
                const Text(
                  'SmartFit needs its configuration',
                  style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'Missing: ${missing.join(', ')}\n\n'
                  'Copy frontend/env/env.example.json to frontend/env/dev.json, fill in the values, '
                  'then stop the app and run it again:\n\nflutter run',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
