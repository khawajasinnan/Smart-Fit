import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/chatbot/data/services/chatbot_api_service.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_hero.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_mood.dart';

/// Zayn, the AI stylist mascot (spec §23.14).
void main() {
  group('ZaynController', () {
    test('a reaction shows its mood and a line, then relaxes to idle', () {
      fakeAsync((async) {
        final zayn = ZaynController(random: Random(1));
        zayn.react(ZaynMood.excited);
        expect(zayn.state.mood, ZaynMood.excited);
        expect(zaynQuips[ZaynMood.excited], contains(zayn.state.quip));
        async.elapse(ZaynController.defaultHold + const Duration(milliseconds: 1));
        expect(zayn.state.mood, ZaynMood.idle);
        expect(zayn.state.quip, isNull);
        zayn.dispose();
      });
    });

    test('thinking holds until the next event', () {
      fakeAsync((async) {
        final zayn = ZaynController(random: Random(1));
        zayn.react(ZaynMood.thinking, hold: null);
        async.elapse(const Duration(minutes: 5));
        expect(zayn.state.mood, ZaynMood.thinking);
        zayn.react(ZaynMood.happy);
        expect(zayn.state.mood, ZaynMood.happy);
        zayn.dispose();
      });
    });

    test('typing keeps listening without repeating the line on every key', () {
      fakeAsync((async) {
        final zayn = ZaynController(random: Random(1));
        zayn.listening();
        final first = zayn.state.quip;
        expect(zayn.state.mood, ZaynMood.listening);
        zayn.listening();
        zayn.listening();
        expect(zayn.state.quip, first);
        async.elapse(const Duration(seconds: 5));
        expect(zayn.state.mood, ZaynMood.idle);
        zayn.dispose();
      });
    });

    test('typing does not interrupt a reaction to the last reply', () {
      final zayn = ZaynController(random: Random(1));
      zayn.react(ZaynMood.sad);
      zayn.listening();
      expect(zayn.state.mood, ZaynMood.sad);
      zayn.dispose();
    });

    test('a poke gets a playful reaction and a poke line', () {
      final zayn = ZaynController(random: Random(3));
      zayn.poke();
      expect([ZaynMood.sassy, ZaynMood.wink, ZaynMood.hairflip, ZaynMood.cool, ZaynMood.dance, ZaynMood.eyeroll,
              ZaynMood.vogue, ZaynMood.snap, ZaynMood.kiss, ZaynMood.spin, ZaynMood.strut, ZaynMood.selfie],
          contains(zayn.state.mood));
      expect(zaynPokeQuips, contains(zayn.state.quip));
      zayn.dispose();
    });
  });

  test('every mood has lines (except idle), a still frame, and exists in the 3D page', () {
    final page = File('assets/mascot/zayn.html').readAsStringSync();
    for (final mood in ZaynMood.values) {
      if (mood != ZaynMood.idle) expect(zaynQuips[mood], isNotEmpty, reason: mood.name);
      expect(File('assets/mascot/still/${mood.name}.png').existsSync(), isTrue, reason: mood.name);
      expect(page, contains('    ${mood.name}: '), reason: '${mood.name} missing from zayn.html MOODS');
    }
    expect(File('assets/mascot/three.min.js').lengthSync(), greaterThan(500000));
    expect(File('assets/mascot/zayn_avatar.png').existsSync(), isTrue);
    expect(File('assets/mascot/eyes.html').existsSync() && File('assets/mascot/still/eyes.png').existsSync(), isTrue);
  });

  test('the stylist backend knows every mood the reply can carry', () {
    // backend/services/chat_orchestrator/tools.py MOODS = moods the AI may tag
    final tools = File('../backend/services/chat_orchestrator/tools.py').readAsStringSync();
    final backend = RegExp(r'MOODS = \(([^)]*)\)').firstMatch(tools)!.group(1)!;
    final names = RegExp(r'"(\w+)"').allMatches(backend).map((m) => m.group(1)).toSet();
    // idle / hello / listening come from app events, not the AI
    final expected = ZaynMood.values.map((m) => m.name).toSet()..removeAll(['idle', 'hello', 'listening']);
    expect(names, expected);
  });

  test('moods from the stylist reply', () {
    expect(ZaynMood.fromName('Sassy'), ZaynMood.sassy);
    expect(ZaynMood.fromName('furious'), isNull);
    expect(ZaynMood.fromName(null), isNull);
    final reply = ChatbotReply.fromJson(const {'reply': 'Kamaal!', 'mood': 'love'});
    expect(reply.mood, 'love');
    expect(reply.isError, isFalse);
  });

  group('ZaynHero', () {
    Future<ProviderContainer> pump(WidgetTester tester, {required bool compact}) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: Column(children: [ZaynHero(compact: compact)])),
        ),
      ));
      return container;
    }

    testWidgets('large on a new chat, compact later; still frame when 3D is unavailable', (tester) async {
      await pump(tester, compact: false);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ZaynHero)).height, ZaynHero.expandedHeight);
      expect(find.byType(Image), findsOneWidget); // tests have no WebView: the still frame

      await pump(tester, compact: true);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ZaynHero)).height, ZaynHero.compactHeight);
    });

    testWidgets('shows what Zayn says and reacts to a tap', (tester) async {
      final container = await pump(tester, compact: true);
      container.read(zaynProvider.notifier).react(ZaynMood.sassy, quip: 'Darling, trust me on this one.');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Darling, trust me on this one.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Zayn, your AI stylist, is sassy')), findsOneWidget);

      await tester.tap(find.byType(ZaynHero));
      await tester.pump(const Duration(milliseconds: 400));
      expect(zaynPokeQuips, contains(container.read(zaynProvider).quip));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
