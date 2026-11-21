import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_hero.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_mood.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_voice.dart';
import 'package:smartfit/features/chatbot/notifications/zayn_notification_plan.dart';
import 'package:smartfit/features/chatbot/notifications/zayn_notifications.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/data/services/scraper_api_service.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/recommendation/providers/taste_feedback_provider.dart';
import 'package:smartfit/features/recommendation/taste_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Zayn's voice, learning from feedback, and her daily notifications (spec §23.15).

class FakeTts implements ZaynTtsEngine {
  final spoken = <String>[];
  int stops = 0;
  int configures = 0;
  VoidCallback? start;
  VoidCallback? done;

  @override
  Future<void> configure() async => configures++;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    start?.call();
  }

  @override
  Future<void> stop() async => stops++;
  @override
  void onStart(VoidCallback callback) => start = callback;
  @override
  void onDone(VoidCallback callback) => done = callback;
}

ProductRecommendation product(String id, String brand,
        {String? category = 'kurta', List<String> colors = const ['black'], int? price = 5000}) =>
    ProductRecommendation(
      id: id,
      brand: brand,
      title: '$brand Lawn Kurta $id',
      category: category,
      pricePkr: price,
      productUrl: 'https://${brand.toLowerCase()}.pk/products/$id',
      colors: colors,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('voice', () {
    test('says clean text, tracks speaking, respects mute', () async {
      final tts = FakeTts();
      final voice = ZaynVoice(engine: tts, loadPrefs: false);
      await voice.say('**Hello** Ayesha! 💜 See https://zeen.pk/x for more');
      expect(tts.spoken.single, 'Hello Ayesha! See for more');
      expect(tts.configures, 1);
      expect(voice.state.speaking, isTrue);
      tts.done!();
      expect(voice.state.speaking, isFalse);

      await voice.setMuted(true);
      await voice.say('This should stay silent');
      expect(tts.spoken, hasLength(1));
      expect((await SharedPreferences.getInstance()).getBool(ZaynVoice.mutedKey), isTrue);
      voice.dispose();
    });

    test('picks a male English voice, South-Asian English first', () {
      expect(pickZaynVoice(const [('Samantha', 'en-US'), ('Daniel', 'en-GB'), ('Rishi', 'en-IN')]), 2);
      expect(pickZaynVoice(const [('Microsoft Zira', 'en-US'), ('Microsoft David', 'en-US')]), 1);
      expect(pickZaynVoice(const [('Daniel', 'fr-FR')]), isNull);
      expect(pickZaynVoice(const [('Samantha', 'en-US')]), isNull); // no male voice: keep the default
    });

    test('long replies are cut at a sentence end', () {
      final text = List.filled(40, 'This kurta is lovely.').join(' ');
      final line = ZaynVoice.speakable(text);
      expect(line.length, lessThanOrEqualTo(ZaynVoice.maxLength));
      expect(line, endsWith('.'));
    });

    test('greets by the first name from onboarding', () {
      expect(zaynGreeting('ayesha khan'), 'Hello Ayesha! What kind of clothes are you looking for today?');
      expect(zaynGreeting('  '), 'Hello! What kind of clothes are you looking for today?');
    });

    testWidgets('the hero shows the sound animation while Zayn talks', (tester) async {
      final tts = FakeTts();
      final container = ProviderContainer(overrides: [
        zaynVoiceProvider.overrideWith((ref) => ZaynVoice(engine: tts, loadPrefs: false)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Column(children: [ZaynHero(compact: true)])),
        ),
      ));
      AnimatedScale bars() => tester.widget<AnimatedScale>(
          find.ancestor(of: find.byType(ZaynSoundBars), matching: find.byType(AnimatedScale)));
      expect(bars().scale, 0);

      await container.read(zaynVoiceProvider.notifier).say('Hello!');
      await tester.pump(const Duration(milliseconds: 300));
      expect(bars().scale, 1);
      expect(find.bySemanticsLabel(RegExp('and talking')), findsOneWidget);

      tts.done!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(bars().scale, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('taste profile', () {
    test('nothing known yet -> no taste', () {
      expect(buildTasteProfile(loved: const [], disliked: const [], votes: const {}), isNull);
    });

    test('loves, repeated misses and quiz answers become ranking signals', () {
      final taste = buildTasteProfile(
        loved: [product('a', 'Saya', colors: ['pink']), product('b', 'Saya', colors: ['pink'], price: 7000)],
        disliked: [
          product('c', 'Zeen', category: 'tees', colors: ['grey']),
          product('d', 'Zeen', category: 'tees', colors: ['grey']),
          product('e', 'Lulusar', colors: ['red']), // one miss: about that product only
        ],
        votes: const {'eastern_western': 'eastern', 'palette': 'pastels'},
      )!;
      expect(taste['liked_brands'], ['saya']);
      expect(taste['liked_colors'], containsAll(['pink', 'mint', 'lilac']));
      expect(taste['liked_categories'], ['kurta']);
      expect(taste['disliked_brands'], ['zeen']);
      expect(taste['disliked_colors'], ['grey']);
      expect(taste['disliked_categories'], ['tees']);
      expect(taste['style_lean'], 'eastern');
      expect(taste['price_point'], 6000); // average loved price
      expect(taste['excluded_product_ids'],
          containsAll(['c', 'https://zeen.pk/products/c', 'e', 'https://lulusar.pk/products/e']));
      expect(tasteProfileText(taste), allOf(contains('Brands they loved: saya'), contains('Style lean')));
    });

    test('a budget answer beats the average loved price', () {
      final taste = buildTasteProfile(loved: [product('a', 'Saya', price: 20000)], disliked: const [],
          votes: const {'budget': 'under5k'})!;
      expect(taste['price_point'], 4000);
    });

    test('love and "not for me" are mutually exclusive and feed the request taste', () async {
      final container = ProviderContainer(overrides: [
        supabaseClientProvider.overrideWithValue(SupabaseClient('http://localhost:1', 'anon')),
        currentUserProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);
      final actions = container.read(feedbackActionsProvider);
      final p = product('x', 'Saya');

      expect(await actions.toggleLove(p), isTrue);
      await actions.notForMe(p);
      expect(container.read(lovedFitsProvider), isNot(contains(p.key)));
      expect(container.read(tasteFeedbackProvider).isDisliked(p), isTrue);
      expect(actions.tasteProfile()!['excluded_product_ids'], contains('x'));

      await actions.setLoved(p, true);
      expect(container.read(tasteFeedbackProvider).isDisliked(p), isFalse);
      expect(container.read(lovedFitsProvider), contains(p.key));

      await actions.vote('palette', 'bold');
      expect(container.read(tasteFeedbackProvider).votes, {'palette': 'bold'});
      await actions.vote('not_a_quiz', 'x');
      expect(container.read(tasteFeedbackProvider).votes, {'palette': 'bold'});
    });

    test('recently shown products are remembered newest first, without repeats', () async {
      final store = TasteFeedbackNotifier(null, null);
      await store.recordShown([product('a', 'Saya'), product('b', 'Zeen')], at: DateTime(2026, 11, 8));
      await store.recordShown([product('a', 'Saya')], at: DateTime(2026, 11, 9));
      expect(store.state.recent.map((s) => s.product.id), ['a', 'b']);
      store.dispose();
    });

    test('the recommendation request sends taste, never brand names in the text', () async {
      Map<String, dynamic>? sent;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          sent = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(Response(requestOptions: options, data: {'products': <dynamic>[]}));
        }));
      await ScraperApiService(dio).searchProducts(
        profile: const UserProfileModel(id: 'u1', gender: 'female'),
        userMessage: 'lawn kurta',
        taste: const {'liked_brands': ['saya'], 'excluded_product_ids': ['x']},
      );
      expect(sent!['taste'], {'liked_brands': ['saya'], 'excluded_product_ids': ['x']});
      expect(sent!['user_message'], isNot(contains('saya')));
      expect(sent!['user_message'], isNot(contains('loved')));
    });
  });

  group('notification plan', () {
    final askAbout = [product('a', 'Saya'), product('b', 'Zeen'), product('c', 'Lulusar')];

    test('three a day for a week: funny morning, roast at 2 pm, chill night with the buttons', () {
      final plan = planZaynNotifications(
        now: DateTime(2026, 11, 8, 8),
        morning: const TimeOfDay(hour: 9, minute: 0),
        firstName: 'Ayesha',
        askAbout: askAbout,
        openQuizzes: tasteQuizzes,
      );
      expect(plan, hasLength(21));
      expect(plan.map((n) => n.id), [for (var i = 0; i < 21; i++) zaynPlanFirstId + i]);
      expect(plan.where((n) => n.when.hour == 9 && n.type == 'fun'), hasLength(7));
      expect(plan.where((n) => n.when.hour == 14 && n.type == 'roast'), hasLength(7));
      expect(plan.where((n) => n.when.hour == 21), hasLength(7));
      expect(plan.map((n) => '${n.title} ${n.body}').join(), isNot(contains('{name}')));
      expect(plan.where((n) => n.type == 'fun' || n.type == 'roast').every((n) => n.actions.isEmpty), isTrue);

      final nights = plan.where((n) => n.when.hour == 21).toList();
      expect(nights.map((n) => n.type).take(6), ['feedback', 'quiz', 'feedback', 'quiz', 'feedback', 'quiz']);
      expect(nights.last.type, 'chill'); // everything asked: just a chill line

      final feedback = nights.first;
      expect(feedback.actions.map((a) => a.id), [loveActionId, nopeActionId]);
      expect(feedback.darwinCategory, feedbackCategory);
      expect(feedback.body, contains('Saya'));
      final payload = jsonDecode(feedback.payload) as Map<String, dynamic>;
      expect(ProductRecommendation.fromJson(Map<String, dynamic>.from(payload['p'] as Map)).key, 'a');

      final quiz = nights[1];
      expect(quiz.actions.map((a) => a.id), ['eastern', 'western']);
      expect(quiz.darwinCategory, quizCategory('eastern_western'));
    });

    test('roasts stay about clothes and habits', () {
      final plan = planZaynNotifications(now: DateTime(2026, 11, 1), morning: const TimeOfDay(hour: 9, minute: 0),
          firstName: 'Ali', askAbout: const [], openQuizzes: const []);
      final roasts = plan.where((n) => n.type == 'roast').map((n) => '${n.title} ${n.body}'.toLowerCase()).join(' ');
      for (final word in ['fat', 'weight', 'skin', 'dark', 'ugly', 'poor', 'religion', 'body']) {
        expect(roasts, isNot(contains(word)), reason: word);
      }
    });

    test('past slots are skipped; slots move away from the morning reminder', () {
      final late = planZaynNotifications(now: DateTime(2026, 11, 8, 22), morning: const TimeOfDay(hour: 9, minute: 0),
          firstName: '', askAbout: const [], openQuizzes: const []);
      expect(late, hasLength(18));
      expect(late.first.when, DateTime(2026, 11, 9, 9));

      expect(zaynSlots(const TimeOfDay(hour: 9, minute: 0)), (roast: const TimeOfDay(hour: 14, minute: 0), chill: const TimeOfDay(hour: 21, minute: 0)));
      expect(zaynSlots(const TimeOfDay(hour: 13, minute: 0)).roast, const TimeOfDay(hour: 17, minute: 0));
      final night = zaynSlots(const TimeOfDay(hour: 20, minute: 30));
      expect(night.chill, const TimeOfDay(hour: 22, minute: 30));
      expect(night.roast, const TimeOfDay(hour: 14, minute: 0));
    });

    test('Zayn reacts to the answer when the app opens', () {
      final feedback = {'t': 'feedback', 'p': {'brand': 'Saya'}};
      expect(zaynReactionTo(feedback, loveActionId)!.mood, ZaynMood.love);
      expect(zaynReactionTo(feedback, loveActionId)!.quip, contains('Saya'));
      expect(zaynReactionTo(feedback, nopeActionId)!.mood, ZaynMood.sassy);
      expect(zaynReactionTo({'t': 'quiz', 'q': 'palette'}, 'bold')!.quip, contains('Bold'));
      expect(zaynReactionTo({'t': 'quiz', 'q': 'palette'}, null)!.quip, quizById('palette')!.question);
      expect(zaynReactionTo({'t': 'fun'}, null), isNull);
      expect(zaynReactionTo({'t': 'roast'}, null)!.mood, ZaynMood.eyeroll);
      expect(zaynReactionTo({'t': 'chill'}, null)!.mood, ZaynMood.cool);
    });

    test('every quiz has its iOS button set', () {
      final ids = zaynDarwinCategories().map((c) => c.$1).toSet();
      expect(ids, {feedbackCategory, for (final q in tasteQuizzes) quizCategory(q.id)});
    });

    test('a button press that launched the app waits for its handler', () {
      final service = NotificationService.instance;
      final calls = <(String, String?)>[];
      service.onAction = null;
      service.debugDispatch(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        payload: '{"t":"quiz","q":"palette"}',
        actionId: 'bold',
      ));
      expect(calls, isEmpty);
      service.onAction = (payload, action) => calls.add((payload, action));
      expect(calls, [('{"t":"quiz","q":"palette"}', 'bold')]);
      service.onAction = null;
    });
  });
}
