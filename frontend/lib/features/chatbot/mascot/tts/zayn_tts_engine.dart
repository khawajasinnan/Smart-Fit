import 'package:flutter/foundation.dart';

/// The speech engine behind Zayn's voice (spec §23.15–23.16): the phone's or
/// browser's own text-to-speech, so it works offline and costs nothing.
abstract class ZaynTtsEngine {
  Future<void> configure();
  Future<void> speak(String text);
  Future<void> stop();
  void onStart(VoidCallback callback);
  void onDone(VoidCallback callback);
}

/// Male English voices by name, best first: South-Asian English first (closest
/// to a Pakistani accent), then US / UK. Android (Google TTS), iOS, Windows,
/// macOS and Chrome name their voices differently, so all are listed.
const zaynPreferredVoices = [
  'rishi', 'microsoft ravi', 'microsoft prabhat', 'en-in-x-end', 'en-in-x-ene',
  'en-us-x-iom', 'en-us-x-tpd', 'en-us-x-iol', 'en-gb-x-rjs', 'en-gb-x-gbd',
  'aaron', 'daniel', 'arthur', 'alex', 'fred', 'tom',
  'microsoft andrew', 'microsoft guy', 'microsoft brian', 'microsoft christopher', 'microsoft eric',
  'microsoft davis', 'microsoft roger', 'microsoft david', 'microsoft mark', 'google uk english male',
];

/// The index of the best voice among [voices] given as (name, locale), or null.
int? pickZaynVoice(List<(String, String)> voices) {
  for (final wanted in zaynPreferredVoices) {
    for (var i = 0; i < voices.length; i++) {
      final (name, locale) = voices[i];
      if (name.toLowerCase().contains(wanted) && locale.toLowerCase().startsWith('en')) return i;
    }
  }
  return null;
}
