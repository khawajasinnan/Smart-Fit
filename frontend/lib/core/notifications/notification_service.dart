import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// What a system notification is about. Each kind has a fixed id, so a newer
/// one replaces the older one instead of stacking up.
enum NotificationKind {
  dailyReminder(1001, 'style_reminders'),
  recommendationsReady(2001, 'updates'),
  analysisDone(2002, 'updates'),
  tryOnReady(2003, 'updates');

  const NotificationKind(this.id, this.channel);
  final int id;
  final String channel;
}

/// Local (on-device) notifications: no server, no Firebase (decision 24 Oct
/// 2026). Wraps flutter_local_notifications; every call is safe to make on a
/// platform without notification support (it just does nothing).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  void Function(String route)? _onTapRoute;
  void Function(String payload, String? actionId)? _onAction;

  /// A tap or button press that arrived before its handler was set (the app
  /// was launched by the notification); delivered when the handler is set.
  NotificationResponse? _pending;

  /// Called with a notification's route when the user taps it.
  set onTapRoute(void Function(String route)? handler) {
    _onTapRoute = handler;
    _deliverPending();
  }

  /// Called for JSON-payload notifications (Zayn's): the payload and the
  /// button pressed (null when the notification itself was tapped).
  set onAction(void Function(String payload, String? actionId)? handler) {
    _onAction = handler;
    _deliverPending();
  }

  /// iOS button sets: (category id, [(action id, label)]). Set before [init].
  List<(String, List<(String, String)>)> darwinCategories = const [];

  static const _channels = {
    'style_reminders': ('Style reminders', 'A daily nudge to plan your outfit'),
    'updates': ('Updates', 'Recommendations, body analysis and try-on results'),
    'zayn': ("Zayn's daily fun", 'Funny mornings, light roasts and chill nights, with 1-tap "did you like it?" and style quizzes'),
  };

  void _deliverPending() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _dispatch(pending);
  }

  @visibleForTesting
  void debugDispatch(NotificationResponse response) => _dispatch(response);

  void _dispatch(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('/')) {
      final handler = _onTapRoute;
      handler == null ? _pending = response : handler(payload);
    } else if (payload.startsWith('{')) {
      final handler = _onAction;
      final action = response.actionId;
      handler == null ? _pending = response : handler(payload, action == null || action.isEmpty ? null : action);
    }
  }

  bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void>? _initializing;

  /// Safe to call many times (and concurrently): initialises once.
  Future<void> init() {
    if (_ready || !_supported) return Future.value();
    return _initializing ??= _init().whenComplete(() => _initializing = null);
  }

  Future<void> _init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Karachi')); // the app's home market
      }
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_smartfit'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: [
              for (final (id, actions) in darwinCategories)
                DarwinNotificationCategory(id, actions: [
                  for (final (actionId, label) in actions)
                    DarwinNotificationAction.plain(actionId, label,
                        options: {DarwinNotificationActionOption.foreground}),
                ]),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: _dispatch,
      );
      // Opened from a notification while the app was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && launchResponse != null) _dispatch(launchResponse);
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final entry in _channels.entries) {
        await android?.createNotificationChannel(AndroidNotificationChannel(
          entry.key,
          entry.value.$1,
          description: entry.value.$2,
          importance: entry.key == 'updates' ? Importance.high : Importance.defaultImportance,
        ));
      }
      _ready = true;
    } catch (e) {
      debugPrint('[Notifications] init failed: $e');
    }
  }

  /// Asks the OS for permission (Android 13+, iOS). True when allowed.
  Future<bool> requestPermission() async {
    if (!_ready) await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('[Notifications] permission request failed: $e');
    }
    return false;
  }

  /// Opens the phone's notification settings for SmartFit (after the user
  /// refused permission). True if a settings screen opened.
  Future<bool> openSystemSettings() async {
    if (!_ready) await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _details(NotificationKind kind) {
    final channel = _channels[kind.channel]!;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        kind.channel,
        channel.$1,
        channelDescription: channel.$2,
        icon: 'ic_stat_smartfit',
        color: Color(0xFF0A7D3B),
        importance: kind.channel == 'updates' ? Importance.high : Importance.defaultImportance,
        priority: kind.channel == 'updates' ? Priority.high : Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  Future<void> show(NotificationKind kind, {required String title, required String body, String? route}) async {
    if (!_ready) return;
    try {
      await _plugin.show(id: kind.id, title: title, body: body, notificationDetails: _details(kind), payload: route);
    } catch (e) {
      debugPrint('[Notifications] show failed: $e');
    }
  }

  /// The next [time] today, or tomorrow if it has passed.
  static tz.TZDateTime nextInstanceOf(TimeOfDay time, tz.TZDateTime now) {
    var at = tz.TZDateTime(now.location, now.year, now.month, now.day, time.hour, time.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  /// Repeats every day at [time] (inexact: no special alarm permission).
  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: NotificationKind.dailyReminder.id);
      await _plugin.zonedSchedule(
        id: NotificationKind.dailyReminder.id,
        scheduledDate: nextInstanceOf(time, tz.TZDateTime.now(tz.local)),
        notificationDetails: _details(NotificationKind.dailyReminder),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        title: 'Need an outfit for today? ✨',
        body: 'Tell your AI stylist where you are going and get looks that fit you.',
        payload: '/chat',
      );
    } catch (e) {
      debugPrint('[Notifications] schedule failed: $e');
    }
  }

  Future<void> cancelDailyReminder() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: NotificationKind.dailyReminder.id);
    } catch (_) {}
  }

  /// Replace every scheduled notification with an id in [firstId]..[lastId]
  /// by [items] on the 'zayn' channel (inexact timing, no alarm permission).
  Future<void> replaceScheduledBlock({
    required int firstId,
    required int lastId,
    required List<
            ({int id, DateTime when, String title, String body, String payload, List<(String, String)> actions, String? darwinCategory})>
        items,
  }) async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final r in pending) {
        if (r.id >= firstId && r.id <= lastId) await _plugin.cancel(id: r.id);
      }
      final channel = _channels['zayn']!;
      for (final item in items) {
        final details = NotificationDetails(
          android: AndroidNotificationDetails(
            'zayn',
            channel.$1,
            channelDescription: channel.$2,
            icon: 'ic_stat_smartfit',
            color: Color(0xFF0A7D3B),
            styleInformation: BigTextStyleInformation(item.body),
            actions: [
              for (final (id, label) in item.actions)
                AndroidNotificationAction(id, label, showsUserInterface: true, cancelNotification: true),
            ],
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: item.darwinCategory),
        );
        await _plugin.zonedSchedule(
          id: item.id,
          scheduledDate: tz.TZDateTime.from(item.when, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: item.title,
          body: item.body,
          payload: item.payload,
        );
      }
    } catch (e) {
      debugPrint('[Notifications] block schedule failed: $e');
    }
  }

  Future<void> cancelBlock(int firstId, int lastId) async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final r in pending) {
        if (r.id >= firstId && r.id <= lastId) await _plugin.cancel(id: r.id);
      }
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
