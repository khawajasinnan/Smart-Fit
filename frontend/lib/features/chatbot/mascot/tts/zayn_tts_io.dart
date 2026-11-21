import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'zayn_tts_engine.dart';

ZaynTtsEngine createPlatformTts() => FlutterTtsEngine();

/// Android / iOS / desktop: flutter_tts. A young male voice: natural pitch,
/// a touch faster than normal.
class FlutterTtsEngine implements ZaynTtsEngine {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> configure() async {
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.02);
    await _tts.setSpeechRate(0.52); // 0..1 on Android / iOS, 0.5 = normal
    await _tts.setVolume(1.0);
    try {
      final voices = [
        for (final v in (await _tts.getVoices as List?) ?? const [])
          if (v is Map) ('${v['name'] ?? ''}', '${v['locale'] ?? ''}'),
      ];
      final pick = pickZaynVoice(voices);
      if (pick != null) await _tts.setVoice({'name': voices[pick].$1, 'locale': voices[pick].$2});
    } catch (_) {
      // keep the default voice
    }
  }

  @override
  Future<void> speak(String text) async => _tts.speak(text);

  @override
  Future<void> stop() async => _tts.stop();

  @override
  void onStart(VoidCallback callback) => _tts.setStartHandler(callback);

  @override
  void onDone(VoidCallback callback) {
    _tts
      ..setCompletionHandler(callback)
      ..setCancelHandler(callback)
      ..setErrorHandler((_) => callback());
  }
}
