import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts/zayn_tts_engine.dart';
import 'tts/zayn_tts_io.dart' if (dart.library.js_interop) 'tts/zayn_tts_web.dart';

export 'tts/zayn_tts_engine.dart';

/// Zayn's voice (spec §23.15, §23.16): the device's own text-to-speech with a
/// young male English voice. Engines: flutter_tts on phones, the browser's
/// speechSynthesis on the web (see tts/).
class ZaynVoiceState {
  const ZaynVoiceState({this.muted = false, this.speaking = false});

  final bool muted;
  final bool speaking;

  ZaynVoiceState copyWith({bool? muted, bool? speaking}) =>
      ZaynVoiceState(muted: muted ?? this.muted, speaking: speaking ?? this.speaking);
}

/// Speak text aloud as Zayn; mute is remembered on the device.
class ZaynVoice extends StateNotifier<ZaynVoiceState> {
  ZaynVoice({ZaynTtsEngine? engine, bool loadPrefs = true})
      : _engine = engine ?? createPlatformTts(),
        super(const ZaynVoiceState()) {
    _engine.onStart(() {
      if (mounted) state = state.copyWith(speaking: true);
    });
    _engine.onDone(() {
      if (mounted) state = state.copyWith(speaking: false);
    });
    if (loadPrefs) _loadMuted();
  }

  final ZaynTtsEngine _engine;
  Future<void>? _configured;

  static const mutedKey = 'zayn_voice_muted';
  static const maxLength = 420;

  Future<void> _loadMuted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = state.copyWith(muted: prefs.getBool(mutedKey) ?? false);
    } catch (_) {}
  }

  /// Text as Zayn should say it: no emojis, markdown or links; short.
  static String speakable(String text) {
    var t = text
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'[*_#`>~\[\]]'), '')
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > maxLength) {
      final cut = t.lastIndexOf(RegExp(r'[.!?]'), maxLength);
      t = cut > 80 ? t.substring(0, cut + 1) : '${t.substring(0, maxLength)}...';
    }
    return t;
  }

  Future<void> say(String text) async {
    if (state.muted) return;
    final line = speakable(text);
    if (line.isEmpty) return;
    try {
      _configured ??= _engine.configure();
      await _configured;
      await _engine.stop();
      await _engine.speak(line);
    } catch (e) {
      debugPrint('[ZaynVoice] speak failed: $e');
      if (mounted) state = state.copyWith(speaking: false);
    }
  }

  Future<void> stop() async {
    try {
      await _engine.stop();
    } catch (_) {}
    if (mounted) state = state.copyWith(speaking: false);
  }

  Future<void> setMuted(bool muted) async {
    if (muted) await stop();
    if (mounted) state = state.copyWith(muted: muted);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(mutedKey, muted);
    } catch (_) {}
  }

  @override
  void dispose() {
    _engine.stop().catchError((Object _) {});
    super.dispose();
  }
}

/// Zayn's opening line when the chat opens (spec §23.15).
String zaynGreeting(String fullName) {
  final first = zaynFirstName(fullName);
  return 'Hello${first.isEmpty ? '' : ' $first'}! What kind of clothes are you looking for today?';
}

/// "ayesha khan" -> "Ayesha"; '' when there is no name.
String zaynFirstName(String fullName) {
  final first = fullName.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? '' : '${first[0].toUpperCase()}${first.substring(1)}';
}

final zaynVoiceProvider = StateNotifierProvider<ZaynVoice, ZaynVoiceState>((ref) => ZaynVoice());
