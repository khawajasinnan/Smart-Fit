import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/errors/failure.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/profile/data/services/skin_tone_api_service.dart';
import 'package:smartfit/features/profile/screens/skin_tone_analyzer_screen.dart';

SkinPalette _palette(String? undertone) => SkinPalette(
  skinTone: 'Medium',
  undertone: undertone,
  summary: 'Medium skin with a ${undertone ?? 'unknown'} undertone.',
  best: const [SkinColour('maroon', '#800000'), SkinColour('teal', '#008080')],
  avoid: const [SkinColour('khaki', '#C3B091')],
  white: 'Off-white or cream.',
  metal: undertone == 'cool' ? 'Silver' : 'Gold',
  outfits: const ['Maroon or rust for festive wear'],
  avoidTip: 'Beige close to your skin can wash you out.',
);

class _FakeSkinApi extends SkinToneApiService {
  _FakeSkinApi({this.fail = false}) : super(Dio());

  final bool fail;
  final List<String> calls = [];

  @override
  Future<SkinAnalysis> analyze({String? imageBase64, String? imageUrl}) async {
    calls.add(imageUrl != null ? 'analyze:url' : 'analyze:bytes');
    if (fail) throw const ValidationFailure("We couldn't see a face. Use a clear, front-facing photo in daylight.");
    return SkinAnalysis(
      skinTone: 'Medium',
      monkLevel: 6,
      monkHex: '#A07E56',
      measuredHex: '#C58D7B',
      undertone: 'warm',
      undertoneSure: false,
      whiteBalanced: true,
      note: 'Your undertone is close to the line, so answer the two quick questions to confirm it.',
      palette: _palette('warm'),
    );
  }

  @override
  Future<SkinPalette> palette(String skinTone, String? undertone) async {
    calls.add('palette:$undertone');
    return _palette(undertone);
  }
}

Future<SkinToneChoice?> _open(WidgetTester tester, _FakeSkinApi api, {Uint8List? bytes}) async {
  SkinToneChoice? result;
  await tester.pumpWidget(ProviderScope(
    overrides: [skinToneApiServiceProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await Navigator.of(context).push<SkinToneChoice>(
              MaterialPageRoute(builder: (_) => SkinToneAnalyzerScreen(profilePhotoBytes: bytes)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('the undertone vote (photo + the two questions)', () {
    test('agreeing answers decide; the photo alone counts', () {
      expect(combineUndertone(photo: 'warm', photoSure: true), 'warm');
      expect(combineUndertone(photo: 'cool', photoSure: true, veins: 'cool', metal: 'cool'), 'cool');
      expect(combineUndertone(), isNull);
    });

    test('the answers outweigh an unsure photo', () {
      expect(combineUndertone(photo: 'warm', veins: 'cool', metal: 'cool'), 'cool');
      expect(combineUndertone(photo: 'warm', photoSure: false), 'neutral'); // 0.5: not enough alone
      expect(combineUndertone(photo: 'warm', photoSure: true, veins: 'cool'), 'neutral'); // they cancel
    });
  });

  testWidgets('a photo, then the shade, the questions and the advice; the result comes back', (tester) async {
    final api = _FakeSkinApi();
    SkinToneChoice? choice;
    await tester.pumpWidget(ProviderScope(
      overrides: [skinToneApiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => choice = await Navigator.of(context).push<SkinToneChoice>(
                MaterialPageRoute(builder: (_) => SkinToneAnalyzerScreen(profilePhotoBytes: Uint8List(200))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Take a selfie'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
    await _tap(tester, find.text('Use my profile photo'));
    expect(api.calls, ['analyze:bytes']);

    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Shade 6 of 10 on the Monk skin tone scale'), findsOneWidget);
    expect(find.text('Undertone: Likely warm'), findsOneWidget); // an unsure photo, no answers yet
    expect(find.textContaining('close to the line'), findsOneWidget);
    expect(find.text('Maroon'), findsOneWidget); // a best colour
    expect(find.text('Khaki'), findsOneWidget); // keep away from the face

    // both answers say cool: the undertone and the advice follow
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Blue or purple'));
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Silver'));
    expect(find.text('Undertone: Cool'), findsOneWidget);
    expect(api.calls.last, 'palette:cool');
    expect(find.textContaining('Silver'), findsWidgets);

    await _tap(tester, find.text('Use these results'));
    expect(choice?.skinTone, 'Medium');
    expect(choice?.undertone, 'cool');
  });

  testWidgets('no profile photo: that option is not offered', (tester) async {
    await _open(tester, _FakeSkinApi());
    expect(find.text('Use my profile photo'), findsNothing);
  });

  testWidgets('a photo it cannot read shows why', (tester) async {
    await _open(tester, _FakeSkinApi(fail: true), bytes: Uint8List(200));
    await _tap(tester, find.text('Use my profile photo'));
    expect(find.textContaining("couldn't see a face"), findsOneWidget);
    expect(find.text('Take a selfie'), findsOneWidget); // back to the photo choice
  });
}
