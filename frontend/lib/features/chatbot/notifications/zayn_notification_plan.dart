import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/taste_profile.dart';

/// Zayn's daily notifications (spec §23.15–23.16): three a day, planned a week ahead.
///   morning (the user's reminder time): something funny
///   afternoon (14:00): a light, friendly roast (clothes and habits only,
///     never body, skin, religion or money)
///   night (21:00): a chill check-in that carries the feedback buttons:
///     - "did you like it?" about a product the stylist showed (Love it / Nope)
///     - a one-tap style quiz (Eastern or Western? ...)
///     - otherwise just a chill line
/// Answers from the buttons are stored as feedback and teach the
/// recommendations (taste profile + the offline dataset).

/// One notification button.
class ZaynAction {
  const ZaynAction(this.id, this.label);
  final String id;
  final String label;
}

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
    this.actions = const [],
    this.darwinCategory,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;

  /// JSON: {"r": route, "t": "fun" | "roast" | "chill" | "feedback" | "quiz", "p": product, "q": quiz id}
  final String payload;
  final List<ZaynAction> actions;

  /// iOS notification category with the same buttons (registered at start-up).
  final String? darwinCategory;

  String get type => (jsonDecode(payload) as Map)['t'] as String;
}

/// Ids 3000-3099 belong to this plan (cancelled and replaced as a block).
const zaynPlanFirstId = 3000;
const zaynPlanLastId = 3099;
const zaynPlanDays = 7;
const zaynSlotsPerDay = 3;

const loveActionId = 'love';
const nopeActionId = 'nope';
const feedbackCategory = 'zayn_feedback';
String quizCategory(String quizId) => 'zayn_quiz_$quizId';

const _funnyLines = <(String, String)>[
  ('Good morning {name}! ☀️', "Your wardrobe called. It said it's bored. Let's fix that 💅"),
  ('{name}, outfit emergency? 🚨', 'Relax, Zayn is on duty with looks that actually fit you.'),
  ('Plot twist 👀', "That outfit you're about to repeat? Let's give it a day off, {name}."),
  ('Chai first, fit check second ☕', "Tell me where you're going today and I'll style you in 30 seconds."),
  ('Zayn here, being dramatic 💜', 'I stalked the new arrivals all night. Come see before they sell out!'),
  ('Main character energy only ✨', "{name}, today's look deserves a soundtrack. Want some picks?"),
  ('Shaadi season brain? 💃', "Mehndi, baraat or walima: I've got a look for each. Just ask."),
  ('Weather check 🌤️', "Lawn, khaddar or a light jacket? I'll decide so you don't have to."),
  ('Bestie alert 📣', '{name}, your style era is loading... tap to speed it up.'),
  ('Not to be dramatic, but... 😌', "You'd look amazing in something new today. Just saying."),
];

/// Light roasts: about clothes and habits only. Never body, skin, weight,
/// religion or money.
const _roastLines = <(String, String)>[
  ("Roast o'clock 🔥", '{name}, that hoodie has seen more of you than your friends have. Let it rest 😭'),
  ('Respectfully... 😬', 'Your style has been on airplane mode lately. Let me switch it back on.'),
  ('Fashion police here 🚓', "The same three outfits on rotation isn't a personality, {name}. I can help."),
  ('Not me judging 👀', 'Your shoes are begging for a better outfit to stand under. Hear them out.'),
  ('Bold of you to... 💅', '...ignore me for this long when I have picks this good. Come look.'),
  ('Quick roast, with love 🔥', '{name}, black on black again? Iconic. Also a cry for help. Let me add colour.'),
  ('Honest review ⭐⭐', "Your wardrobe: great potential, zero plot. Let's write the next chapter."),
  ('Zayn has notes 📝', "That \"I'll just wear whatever\" energy? We can do better. Two minutes, promise."),
];

const _chillLines = <(String, String)>[
  ('Chill mode on 🌙', "Feet up, chai in hand. Want me to plan tomorrow's fit while you relax?"),
  ('Soft night vibes ✨', "No pressure, just saying: comfy co-ords exist and they're calling you."),
  ('Lo-fi and outfits 🎧', 'Scrolling anyway? Scroll some looks I picked for you.'),
  ('Wind-down check 💜', "Today's done. Tomorrow's outfit can be sorted in one tap."),
];

const _feedbackTitles = [
  'Chill question 🌙',
  'Before you sleep... 💭',
  'Quick vibe check 🛋️',
];

String _fill(String text, String firstName) {
  final name = firstName.isEmpty ? 'bestie' : firstName;
  return text.replaceAll('{name}', name);
}

/// Product fields kept in a notification payload (small, enough for feedback).
Map<String, dynamic> compactProduct(ProductRecommendation p) => {
  'id': p.id,
  'brand': p.brand,
  'title': p.title,
  'category': ?p.category,
  'price_pkr': ?p.pricePkr,
  'image_url': ?p.imageUrl,
  'product_url': p.productUrl,
  if (p.colors.isNotEmpty) 'colors': p.colors,
  if (p.tags.isNotEmpty) 'tags': p.tags.take(6).toList(),
};

String _shortTitle(ProductRecommendation p) {
  final t = p.title.trim();
  return t.length <= 40 ? t : '${t.substring(0, 37).trimRight()}...';
}

int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// The first candidate at least 2 hours from every time in [avoid].
TimeOfDay _pick(List<TimeOfDay> candidates, List<TimeOfDay> avoid) {
  for (final c in candidates) {
    if (avoid.every((a) => (_minutes(c) - _minutes(a)).abs() >= 120)) return c;
  }
  return candidates.last;
}

/// The roast and chill slots for a morning time: 14:00 and 21:00 unless the
/// morning reminder is within 2 hours of them.
({TimeOfDay roast, TimeOfDay chill}) zaynSlots(TimeOfDay morning) {
  final roast = _pick(
      const [TimeOfDay(hour: 14, minute: 0), TimeOfDay(hour: 17, minute: 0), TimeOfDay(hour: 11, minute: 30)], [morning]);
  final chill = _pick(
      const [TimeOfDay(hour: 21, minute: 0), TimeOfDay(hour: 22, minute: 30), TimeOfDay(hour: 19, minute: 30)],
      [morning, roast]);
  return (roast: roast, chill: chill);
}

/// Plan the next [zaynPlanDays] days. [askAbout]: products shown recently that
/// the user hasn't loved or rejected yet (newest first). [openQuizzes]: style
/// quizzes not answered yet. Deterministic for the same inputs.
List<PlannedNotification> planZaynNotifications({
  required DateTime now,
  required TimeOfDay morning,
  required String firstName,
  required List<ProductRecommendation> askAbout,
  required List<TasteQuiz> openQuizzes,
}) {
  final slots = zaynSlots(morning);
  final products = askAbout.take(zaynPlanDays).toList();
  final quizzes = [...openQuizzes];
  final plan = <PlannedNotification>[];
  final dayIndex = DateTime(now.year, now.month, now.day).difference(DateTime(2026)).inDays;

  DateTime at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);
  String route(String type) => jsonEncode({'r': '/chat', 't': type});

  for (var d = 0; d < zaynPlanDays; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final rotate = dayIndex + d;
    final firstId = zaynPlanFirstId + d * zaynSlotsPerDay;

    final m = at(day, morning);
    if (m.isAfter(now)) {
      final line = _funnyLines[rotate % _funnyLines.length];
      plan.add(PlannedNotification(
          id: firstId, when: m, title: _fill(line.$1, firstName), body: _fill(line.$2, firstName), payload: route('fun')));
    }

    final r = at(day, slots.roast);
    if (r.isAfter(now)) {
      final line = _roastLines[rotate % _roastLines.length];
      plan.add(PlannedNotification(
          id: firstId + 1, when: r, title: _fill(line.$1, firstName), body: _fill(line.$2, firstName), payload: route('roast')));
    }

    final c = at(day, slots.chill);
    if (!c.isAfter(now)) continue;
    // Alternate product feedback and quizzes while both remain.
    final preferQuiz = d.isOdd && quizzes.isNotEmpty;
    if (!preferQuiz && products.isNotEmpty) {
      final p = products.removeAt(0);
      plan.add(PlannedNotification(
        id: firstId + 2,
        when: c,
        title: _feedbackTitles[rotate % _feedbackTitles.length],
        body: 'Still thinking about the ${p.brand} ${_shortTitle(p)}? Love it or nope? Your answer trains my picks 💜',
        payload: jsonEncode({'r': '/chat', 't': 'feedback', 'p': compactProduct(p)}),
        actions: const [ZaynAction(loveActionId, 'Love it 😍'), ZaynAction(nopeActionId, 'Nope 🙅')],
        darwinCategory: feedbackCategory,
      ));
    } else if (quizzes.isNotEmpty) {
      final q = quizzes.removeAt(0);
      plan.add(PlannedNotification(
        id: firstId + 2,
        when: c,
        title: 'One-tap style quiz 🌙',
        body: q.question,
        payload: jsonEncode({'r': '/chat', 't': 'quiz', 'q': q.id}),
        actions: [ZaynAction(q.a.$1, q.a.$2), ZaynAction(q.b.$1, q.b.$2)],
        darwinCategory: quizCategory(q.id),
      ));
    } else {
      final line = _chillLines[rotate % _chillLines.length];
      plan.add(PlannedNotification(
          id: firstId + 2, when: c, title: _fill(line.$1, firstName), body: _fill(line.$2, firstName), payload: route('chill')));
    }
  }
  return plan;
}
