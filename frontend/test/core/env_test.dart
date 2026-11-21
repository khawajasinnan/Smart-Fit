import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/constants/env.dart';

/// Serves [files] by path; anything else is "not bundled".
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  // Tests run without --dart-define, so values come only from the bundle.
  test('plain `flutter run`: values come from the bundled env/dev.json', () async {
    await Env.load(
      bundle: _Bundle({
        Env.assetPath: jsonEncode({
          'SUPABASE_URL': 'https://abc.supabase.co',
          'SUPABASE_ANON_KEY': 'anon-key',
          'ADMIN_EMAIL': 'boss@smartfit.pk',
          'API_BASE_URL': 'http://192.168.1.5:8000/api/v1',
        }),
      }),
    );
    expect(Env.supabaseUrl, 'https://abc.supabase.co');
    expect(Env.supabaseAnonKey, 'anon-key');
    expect(Env.adminEmail, 'boss@smartfit.pk');
    expect(Env.apiBaseUrl, 'http://192.168.1.5:8000/api/v1');
    expect(Env.missing, isEmpty);
  });

  test('blank values count as missing; admin email falls back', () async {
    await Env.load(
      bundle: _Bundle({Env.assetPath: jsonEncode({'SUPABASE_URL': '  ', 'SUPABASE_ANON_KEY': 'k'})}),
    );
    expect(Env.missing, ['SUPABASE_URL']);
    expect(Env.adminEmail, 'admin@smartfit.pk');
  });

  test('no dev.json bundled: nothing changes, nothing throws', () async {
    await Env.load(bundle: _Bundle({Env.assetPath: jsonEncode({'SUPABASE_URL': 'u', 'SUPABASE_ANON_KEY': 'k'})}));
    await Env.load(bundle: _Bundle({}));
    expect(Env.missing, isEmpty);
  });
}
