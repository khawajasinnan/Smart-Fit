import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / system theme choice, saved on the device.
/// Light is the default (the SRDS mock-ups are light).
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier([super.initial = ThemeMode.light]);

  static const String storageKey = 'theme_mode';

  /// Reads the saved choice before the first frame (no theme flash).
  static Future<ThemeMode> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.light);
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  Future<void> toggleTheme() => setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);

  bool get isDark => state == ThemeMode.dark;
}

/// Overridden in main() with the saved choice.
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) => ThemeNotifier());
