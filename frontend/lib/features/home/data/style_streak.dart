import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';

/// Daily style streak + challenge on Home (spec §23.19). Kept on the device
/// per account: opening the app on consecutive days grows the streak; a
/// missed day starts it again. One small challenge a day, rotating.
class StreakState {
  const StreakState({this.streak = 0, this.best = 0, this.lastVisit, this.doneToday = false, this.week = const {}});

  final int streak;
  final int best;
  final DateTime? lastVisit;
  final bool doneToday;

  /// Days of the last 7 (0 = today ... 6 = six days ago) the app was opened.
  final Set<int> week;

  StreakState copyWith({int? streak, int? best, DateTime? lastVisit, bool? doneToday, Set<int>? week}) => StreakState(
        streak: streak ?? this.streak,
        best: best ?? this.best,
        lastVisit: lastVisit ?? this.lastVisit,
        doneToday: doneToday ?? this.doneToday,
        week: week ?? this.week,
      );
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// The streak after opening the app on [today] (pure; tested).
StreakState visit(StreakState s, DateTime today, {required List<DateTime> visitDays, DateTime? doneDay}) {
  final day = _day(today);
  final last = s.lastVisit == null ? null : _day(s.lastVisit!);
  int streak;
  if (last == day) {
    streak = s.streak == 0 ? 1 : s.streak;
  } else if (last != null && day.difference(last).inDays == 1) {
    streak = s.streak + 1;
  } else {
    streak = 1;
  }
  final week = <int>{
    for (final v in [...visitDays, day])
      if (day.difference(_day(v)).inDays >= 0 && day.difference(_day(v)).inDays < 7) day.difference(_day(v)).inDays,
  };
  return StreakState(
    streak: streak,
    best: streak > s.best ? streak : s.best,
    lastVisit: day,
    doneToday: doneDay != null && _day(doneDay) == day,
    week: week,
  );
}

/// Today's challenge (rotates daily).
String challengeFor(DateTime today) => styleChallenges[today.difference(DateTime(2026)).inDays.abs() % styleChallenges.length];

const styleChallenges = [
  'Wear one colour you never pick. Bonus points for confidence.',
  'Style one piece three different ways this week. Start today.',
  'Ask Zayn for an outfit for your next plan, then actually wear it.',
  'Swap your usual sneakers for something unexpected.',
  'Add one accessory you have been ignoring: a watch, chain or scarf.',
  'Do a 10-second mirror fit check before you leave. Fix one thing.',
  'Try an Eastern-Western fusion look: kurta with jeans counts.',
  'Save 3 looks you love from the AI Stylist to your wardrobe.',
  'Wear something that matches your skin tone palette from your profile.',
  'Plan tomorrow\'s outfit tonight. Future you says thanks.',
];

class StyleStreakNotifier extends StateNotifier<StreakState> {
  StyleStreakNotifier(this._userId, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(const StreakState()) {
    if (_userId != null) _load();
  }

  final String? _userId;
  final DateTime Function() _clock;

  String get _prefix => 'streak_${_userId}_';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = StreakState(
        streak: prefs.getInt('${_prefix}count') ?? 0,
        best: prefs.getInt('${_prefix}best') ?? 0,
        lastVisit: DateTime.tryParse(prefs.getString('${_prefix}last') ?? ''),
      );
      final days = [
        for (final d in prefs.getStringList('${_prefix}days') ?? const <String>[]) ?DateTime.tryParse(d),
      ];
      final now = _clock();
      final next = visit(saved, now, visitDays: days, doneDay: DateTime.tryParse(prefs.getString('${_prefix}done') ?? ''));
      if (mounted) state = next;
      await prefs.setInt('${_prefix}count', next.streak);
      await prefs.setInt('${_prefix}best', next.best);
      await prefs.setString('${_prefix}last', _day(now).toIso8601String());
      final keep = {...days.where((d) => _day(now).difference(_day(d)).inDays < 7).map(_day), _day(now)};
      await prefs.setStringList('${_prefix}days', [for (final d in keep) d.toIso8601String()]);
    } catch (_) {
      // a convenience: never break Home over it
    }
  }

  /// "I did it!" for today's challenge.
  Future<void> completeChallenge() async {
    if (state.doneToday) return;
    state = state.copyWith(doneToday: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_prefix}done', _day(_clock()).toIso8601String());
    } catch (_) {}
  }
}

final styleStreakProvider = StateNotifierProvider<StyleStreakNotifier, StreakState>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  return StyleStreakNotifier(userId);
});
