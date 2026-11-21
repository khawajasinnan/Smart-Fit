import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'zayn_tts_engine.dart';

ZaynTtsEngine createPlatformTts() => WebSpeechEngine();

/// Flutter web: the browser's speechSynthesis directly, one utterance per line.
/// flutter_tts's web plugin reuses a single utterance, silently drops a line
/// spoken right after stop(), and only logs "[object SpeechSynthesisErrorEvent]"
/// when the browser refuses. Browsers refuse speech until the user has
/// interacted with the page ("not-allowed"): that line is kept and spoken on
/// the next tap or key press.
class WebSpeechEngine implements ZaynTtsEngine {
  VoidCallback? _start;
  VoidCallback? _done;
  web.SpeechSynthesisVoice? _voice;
  web.SpeechSynthesisUtterance? _current;
  String? _blocked;
  JSFunction? _unlock;

  web.SpeechSynthesis? get _synth {
    try {
      return web.window.speechSynthesis;
    } catch (_) {
      return null; // no speech support in this browser
    }
  }

  void _pickVoice() {
    final synth = _synth;
    if (synth == null) return;
    final all = synth.getVoices().toDart;
    // Prefer on-device voices: Chrome cuts long lines on its network voices.
    final local = all.where((v) => v.localService).toList();
    for (final list in [local, all]) {
      final pick = pickZaynVoice([for (final v in list) (v.name, v.lang)]);
      if (pick != null) {
        _voice = list[pick];
        return;
      }
    }
  }

  @override
  Future<void> configure() async {
    final synth = _synth;
    if (synth == null) return;
    _pickVoice();
    // Chrome loads its voice list asynchronously.
    if (_voice == null) synth.onvoiceschanged = ((web.Event _) => _pickVoice()).toJS;
  }

  @override
  Future<void> speak(String text) async {
    final synth = _synth;
    if (synth == null) return;
    synth.cancel();
    final u = web.SpeechSynthesisUtterance(text)
      ..lang = _voice?.lang ?? 'en-US'
      ..pitch = 1.02
      ..rate = 1.05;
    final voice = _voice;
    if (voice != null) u.voice = voice;
    u.onstart = ((web.Event _) {
      if (identical(_current, u)) _start?.call();
    }).toJS;
    u.onend = ((web.Event _) {
      if (identical(_current, u)) _done?.call();
    }).toJS;
    u.onerror = ((web.SpeechSynthesisErrorEvent e) {
      if (e.error == 'not-allowed') {
        _blocked = text;
        _armUnlock();
      } else if (e.error != 'interrupted' && e.error != 'canceled') {
        debugPrint('[ZaynVoice] browser speech error: ${e.error}');
      }
      if (identical(_current, u)) _done?.call();
    }).toJS;
    _current = u;
    synth.speak(u);
  }

  void _armUnlock() {
    if (_unlock != null) return;
    final unlock = ((web.Event _) {
      _disarm();
      final line = _blocked;
      _blocked = null;
      if (line != null) speak(line);
    }).toJS;
    _unlock = unlock;
    web.document.addEventListener('pointerdown', unlock, true.toJS);
    web.document.addEventListener('keydown', unlock, true.toJS);
  }

  void _disarm() {
    final unlock = _unlock;
    if (unlock == null) return;
    web.document.removeEventListener('pointerdown', unlock, true.toJS);
    web.document.removeEventListener('keydown', unlock, true.toJS);
    _unlock = null;
  }

  @override
  Future<void> stop() async {
    _blocked = null;
    _current = null;
    _synth?.cancel();
    _done?.call();
  }

  @override
  void onStart(VoidCallback callback) => _start = callback;

  @override
  void onDone(VoidCallback callback) => _done = callback;
}
