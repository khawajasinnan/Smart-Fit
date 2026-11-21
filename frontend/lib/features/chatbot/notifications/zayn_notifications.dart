import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/notifications/notification_service.dart';
import 'package:smartfit/core/providers/notification_provider.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_mood.dart';
import 'package:smartfit/features/chatbot/mascot/zayn_voice.dart';
import 'package:smartfit/features/chatbot/notifications/zayn_notification_plan.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/recommendation/providers/loved_fits_provider.dart';
import 'package:smartfit/features/recommendation/providers/taste_feedback_provider.dart';
import 'package:smartfit/features/recommendation/taste_profile.dart';

/// iOS button sets for Zayn's notifications (registered before init).
List<(String, List<(String, String)>)> zaynDarwinCategories() => [
  (feedbackCategory, const [(loveActionId, 'Love it 😍'), (nopeActionId, 'Nope 🙅')]),
  for (final q in tasteQuizzes) (quizCategory(q.id), [(q.a.$1, q.a.$2), (q.b.$1, q.b.$2)]),
];

/// What Zayn says when the app opens from a notification answer.
@visibleForTesting
({ZaynMood mood, String quip})? zaynReactionTo(Map<String, dynamic> data, String? actionId) {
  switch (data['t']) {
    case 'feedback':
      final brand = (data['p'] is Map ? '${(data['p'] as Map)['brand'] ?? ''}' : '').trim();
      if (actionId == loveActionId) {
        return (mood: ZaynMood.love, quip: 'Noted! More like that ${brand.isEmpty ? 'look' : '$brand piece'} coming your way 💜');
      }
      if (actionId == nopeActionId) {
        return (mood: ZaynMood.sassy, quip: 'Okay okay, no more of that. Zayn never forgets 🙅');
      }
      return (mood: ZaynMood.thinking, quip: "Tell me what you're in the mood for and I'll find something even better.");
    case 'quiz':
      final quiz = quizById('${data['q']}');
      if (quiz == null) return null;
      if (actionId == quiz.a.$1 || actionId == quiz.b.$1) {
        return (mood: ZaynMood.happy, quip: '${quiz.labelFor(actionId!)}? Noted, bestie! Your picks just got smarter ✨');
      }
      return (mood: ZaynMood.surprised, quip: quiz.question);
    case 'roast':
      return (mood: ZaynMood.eyeroll, quip: "Okay okay, I roasted you. Now let me fix that fit 😏");
    case 'chill':
      return (mood: ZaynMood.cool, quip: "Chill mode. Tell me tomorrow's plan and I'll sort the fit.");
    default:
      return null; // a funny nudge: the normal hello
  }
}

/// Keeps Zayn's week of notifications up to date and turns notification
/// answers into feedback (spec §23.15).
class ZaynNotifications {
  ZaynNotifications(this._ref);

  final Ref _ref;
  Timer? _debounce;

  NotificationService get _service => NotificationService.instance;

  /// Re-plan soon (several changes in a row are planned once).
  void reschedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () => unawaited(_apply()));
  }

  String _firstName(String userId) {
    final profileName = _ref.read(profileNotifierProvider(userId)).valueOrNull?.fullName;
    final meta = _ref.read(currentUserProvider)?.userMetadata;
    final name = [profileName, meta?['full_name'], meta?['name']]
        .whereType<String>()
        .firstWhere((n) => n.trim().isNotEmpty, orElse: () => '');
    return zaynFirstName(name);
  }

  Future<void> _apply() async {
    try {
      final notif = _ref.read(notificationNotifierProvider);
      final userId = _ref.read(currentUserProvider)?.id;
      await _service.init();
      if (!notif.isEnabled || !notif.funEnabled || userId == null) {
        await _service.cancelBlock(zaynPlanFirstId, zaynPlanLastId);
        return;
      }
      final taste = _ref.read(tasteFeedbackProvider);
      final loved = _ref.read(lovedFitsProvider);
      final plan = planZaynNotifications(
        now: DateTime.now(),
        morning: notif.reminderTime,
        firstName: _firstName(userId),
        askAbout: [
          for (final shown in taste.recent)
            if (!loved.contains(shown.product.key) && !taste.isDisliked(shown.product)) shown.product,
        ],
        openQuizzes: [for (final q in tasteQuizzes) if (!taste.votes.containsKey(q.id)) q],
      );
      await _service.replaceScheduledBlock(
        firstId: zaynPlanFirstId,
        lastId: zaynPlanLastId,
        items: [
          for (final n in plan)
            (
              id: n.id,
              when: n.when,
              title: n.title,
              body: n.body,
              payload: n.payload,
              actions: [for (final a in n.actions) (a.id, a.label)],
              darwinCategory: n.darwinCategory,
            ),
        ],
      );
    } catch (e) {
      debugPrint('[ZaynNotifications] plan failed: $e');
    }
  }

  /// A Zayn notification was tapped ([actionId] null) or a button pressed.
  Future<void> handle(String payload, String? actionId, void Function(String route) go) async {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    } catch (_) {
      return;
    }
    try {
      final actions = _ref.read(feedbackActionsProvider);
      if (data['t'] == 'feedback' && data['p'] is Map && (actionId == loveActionId || actionId == nopeActionId)) {
        final product = ProductRecommendation.fromJson(Map<String, dynamic>.from(data['p'] as Map));
        if (product.key.isNotEmpty) {
          actionId == loveActionId
              ? await actions.setLoved(product, true, source: 'notification')
              : await actions.notForMe(product, source: 'notification');
        }
      } else if (data['t'] == 'quiz' && actionId != null) {
        final quiz = quizById('${data['q']}');
        if (quiz != null && (actionId == quiz.a.$1 || actionId == quiz.b.$1)) {
          await actions.vote(quiz.id, actionId, source: 'notification');
        }
      }
    } catch (e) {
      debugPrint('[ZaynNotifications] saving the answer failed: $e');
    }

    final reaction = zaynReactionTo(data, actionId);
    final zayn = _ref.read(zaynProvider.notifier);
    if (reaction != null) zayn.setPendingIntro(reaction.mood, reaction.quip);
    final route = data['r'];
    go(route is String && route.startsWith('/') ? route : '/chat');
    // If the chat was already open it won't greet again: react here instead.
    if (reaction != null) {
      Timer(const Duration(milliseconds: 1500), () {
        final intro = zayn.takePendingIntro();
        if (intro == null) return;
        zayn.react(intro.mood, quip: intro.quip, hold: const Duration(seconds: 8));
        _ref.read(zaynVoiceProvider.notifier).say(intro.quip);
      });
    }
  }

  void dispose() => _debounce?.cancel();
}

final zaynNotificationsProvider = Provider<ZaynNotifications>((ref) {
  final zayn = ZaynNotifications(ref);
  ref.listen(
    notificationNotifierProvider.select((n) => (n.isEnabled, n.funEnabled, n.reminderTime)),
    (_, _) => zayn.reschedule(),
  );
  ref.listen(tasteFeedbackProvider, (_, _) => zayn.reschedule());
  ref.listen(lovedFitsProvider, (_, _) => zayn.reschedule());
  ref.listen(currentUserProvider.select((u) => u?.id), (_, _) => zayn.reschedule());
  // Coming back to the app re-plans the next 7 days (the week rolls forward).
  final lifecycle = AppLifecycleListener(onResume: zayn.reschedule);
  ref.onDispose(() {
    lifecycle.dispose();
    zayn.dispose();
  });
  zayn.reschedule();
  return zayn;
});
