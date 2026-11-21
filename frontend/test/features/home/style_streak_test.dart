import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/features/home/data/style_streak.dart';
import 'package:smartfit/features/home/widgets/home_cards.dart';

/// Home's style streak and daily content (spec §23.19).
void main() {
  final mon = DateTime(2026, 11, 9, 10);

  test('first visit starts a 1-day streak', () {
    final s = visit(const StreakState(), mon, visitDays: const []);
    expect(s.streak, 1);
    expect(s.best, 1);
    expect(s.week, {0});
  });

  test('consecutive days grow it; the same day twice does not', () {
    var s = visit(const StreakState(), mon, visitDays: const []);
    s = visit(s, mon.add(const Duration(hours: 5)), visitDays: [mon]);
    expect(s.streak, 1);
    final tue = mon.add(const Duration(days: 1));
    s = visit(s, tue, visitDays: [mon]);
    expect(s.streak, 2);
    expect(s.week, {0, 1});
  });

  test('a missed day starts again but keeps the best', () {
    final s = visit(StreakState(streak: 5, best: 5, lastVisit: mon), mon.add(const Duration(days: 2)), visitDays: [mon]);
    expect(s.streak, 1);
    expect(s.best, 5);
  });

  test("today's challenge counts as done only on the day it was done", () {
    final s = visit(const StreakState(), mon, visitDays: const [], doneDay: mon);
    expect(s.doneToday, isTrue);
    final next = visit(s, mon.add(const Duration(days: 1)), visitDays: [mon], doneDay: mon);
    expect(next.doneToday, isFalse);
  });

  test('challenge and tip rotate daily; "another tip" moves on', () {
    expect(challengeFor(mon), isNot(challengeFor(mon.add(const Duration(days: 1)))));
    expect(tipFor(mon), isNot(tipFor(mon.add(const Duration(days: 1)))));
    expect(tipFor(mon, 1), tipFor(mon.add(const Duration(days: 1))));
  });

  test('the notifier remembers per account and completes the challenge', () async {
    SharedPreferences.setMockInitialValues({});
    final a = StyleStreakNotifier('user-a', clock: () => mon);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(a.state.streak, 1);
    await a.completeChallenge();
    expect(a.state.doneToday, isTrue);
    final b = StyleStreakNotifier('user-a', clock: () => mon.add(const Duration(days: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(b.state.streak, 2);
    expect(b.state.doneToday, isFalse);
    a.dispose();
    b.dispose();
  });
}
