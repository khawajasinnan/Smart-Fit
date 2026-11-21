import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/network/dio_client.dart';
import 'package:smartfit/features/tryon/screens/tryon_screen.dart';

void main() {
  group('garment flat width (own clothes size check)', () {
    test('centimetres are taken as typed, commas and spaces allowed', () {
      expect(flatWidthCm('52', inches: false), 52);
      expect(flatWidthCm(' 48,5 ', inches: false), 48.5);
    });

    test('inches are converted to centimetres', () {
      expect(flatWidthCm('20', inches: true), 50.8);
    });

    test('empty, text and impossible sizes are refused (same range as the server)', () {
      for (final bad in ['', 'abc', '5', '200', '-40']) {
        expect(flatWidthCm(bad, inches: false), isNull, reason: bad);
      }
      expect(flatWidthCm('50', inches: true), isNull); // 127 cm flat: a typo
    });
  });

  group('debug log never shows the login token', () {
    test('authorization and api key headers are hidden, the rest is kept', () {
      const line = 'headers:\n Authorization: Bearer eyJhbGciOi.secret.token\n apikey: sb_secret\n content-type: json';
      final out = redactLogLine(line);
      expect(out, isNot(contains('eyJhbGciOi')));
      expect(out, isNot(contains('sb_secret')));
      expect(out, contains(' Authorization: [hidden]'));
      expect(out, contains('content-type: json'));
    });

    test('other lines pass through unchanged', () {
      expect(redactLogLine('uri: http://x/api/v1/tryon/1'), 'uri: http://x/api/v1/tryon/1');
    });
  });
}
