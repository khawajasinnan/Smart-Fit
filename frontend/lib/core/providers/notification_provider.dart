import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartfit/core/notifications/notification_service.dart';

/// One entry in the in-app notification list (home screen bell).
class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.isNew = true,
    this.category = 'system',
    this.route,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool isNew;

  /// recommendations | analysis | tryon | reminder | system
  final String category;

  /// Where tapping it goes (e.g. "/chat"), if anywhere.
  final String? route;

  IconData get icon => switch (category) {
        'recommendations' => Icons.checkroom_rounded,
        'analysis' => Icons.accessibility_new_rounded,
        'tryon' => Icons.auto_awesome_rounded,
        'reminder' => Icons.wb_sunny_outlined,
        _ => Icons.celebration_rounded,
      };

  /// "Just now", "25m ago", "2h ago", "3d ago".
  String get time {
    final d = DateTime.now().difference(createdAt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  AppNotificationItem copyWith({bool? isNew}) => AppNotificationItem(
        id: id, title: title, subtitle: subtitle, createdAt: createdAt,
        isNew: isNew ?? this.isNew, category: category, route: route,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'subtitle': subtitle, 'created_at': createdAt.toIso8601String(),
        'is_new': isNew, 'category': category, 'route': route,
      };

  static AppNotificationItem? fromJson(Map<String, dynamic> j) {
    final created = DateTime.tryParse(j['created_at']?.toString() ?? '');
    if (created == null || j['id'] == null) return null;
    return AppNotificationItem(
      id: j['id'].toString(), title: j['title']?.toString() ?? '', subtitle: j['subtitle']?.toString() ?? '',
      createdAt: created, isNew: j['is_new'] == true, category: j['category']?.toString() ?? 'system',
      route: j['route']?.toString(),
    );
  }
}

class NotificationState {
  const NotificationState({
    this.isEnabled = true,
    this.dailyReminder = true,
    this.reminderTime = const TimeOfDay(hour: 9, minute: 0),
    this.permissionDenied = false,
    this.items = const [],
    this.funEnabled = true,
  });

  /// Master switch (Settings → Notifications): in-app items and system ones.
  final bool isEnabled;
  final bool dailyReminder;
  final TimeOfDay reminderTime;

  /// The OS refused permission; Settings explains how to allow it.
  final bool permissionDenied;
  final List<AppNotificationItem> items;

  /// Zayn's 3-a-day notifications (spec §23.15–23.16): a funny morning nudge
  /// at [reminderTime] that replaces the plain daily reminder, a light roast
  /// in the afternoon, and a chill night check-in carrying the "did you like
  /// it?" / style-quiz answer buttons.
  final bool funEnabled;

  int get unreadCount => isEnabled ? items.where((n) => n.isNew).length : 0;

  NotificationState copyWith({
    bool? isEnabled,
    bool? dailyReminder,
    TimeOfDay? reminderTime,
    bool? permissionDenied,
    List<AppNotificationItem>? items,
    bool? funEnabled,
  }) {
    return NotificationState(
      isEnabled: isEnabled ?? this.isEnabled,
      dailyReminder: dailyReminder ?? this.dailyReminder,
      reminderTime: reminderTime ?? this.reminderTime,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      items: items ?? this.items,
      funEnabled: funEnabled ?? this.funEnabled,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier({NotificationService? service})
      : _service = service ?? NotificationService.instance,
        super(const NotificationState()) {
    _init();
  }

  final NotificationService _service;

  static const _enabledKey = 'outfit_notifications_enabled';
  static const _dailyKey = 'notif_daily_reminder';
  static const _hourKey = 'notif_reminder_hour';
  static const _minuteKey = 'notif_reminder_minute';
  static const _itemsKey = 'notif_items_v2';
  static const _funKey = 'notif_zayn_fun';
  static const _maxItems = 30;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    var items = <AppNotificationItem>[];
    try {
      final raw = prefs.getString(_itemsKey);
      if (raw != null) {
        items = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(AppNotificationItem.fromJson)
            .whereType<AppNotificationItem>()
            .toList();
      }
    } catch (_) {}
    if (items.isEmpty && prefs.getString(_itemsKey) == null) {
      items = [
        AppNotificationItem(
          id: 'welcome',
          title: 'Welcome to SmartFit! 🎉',
          subtitle: 'Chat with your AI stylist to get outfits picked for your body, style and budget.',
          createdAt: DateTime.now(),
          route: '/chat',
        ),
      ];
    }
    state = NotificationState(
      isEnabled: prefs.getBool(_enabledKey) ?? true,
      dailyReminder: prefs.getBool(_dailyKey) ?? true,
      reminderTime: TimeOfDay(hour: prefs.getInt(_hourKey) ?? 9, minute: prefs.getInt(_minuteKey) ?? 0),
      items: items,
      funEnabled: prefs.getBool(_funKey) ?? true,
    );
    await _persistItems();
    await _service.init();
    await _applySchedule();
  }

  Future<void> _persistItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_itemsKey, jsonEncode(state.items.map((i) => i.toJson()).toList()));
  }

  Future<void> _applySchedule() async {
    // Zayn's morning line replaces the plain reminder while fun is on (her
    // plan itself is scheduled by the Zayn scheduler, which knows the user).
    if (state.isEnabled && state.dailyReminder && !state.funEnabled) {
      await _service.scheduleDailyReminder(state.reminderTime);
    } else {
      await _service.cancelDailyReminder();
    }
  }

  /// Master switch. Turning it on asks the OS for permission first.
  Future<bool> setEnabled(bool enabled) async {
    var granted = true;
    if (enabled) granted = await _service.requestPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    state = state.copyWith(isEnabled: enabled, permissionDenied: enabled && !granted);
    if (enabled) {
      await _applySchedule();
    } else {
      await _service.cancelAll();
    }
    return granted;
  }

  Future<void> setDailyReminder(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyKey, on);
    state = state.copyWith(dailyReminder: on);
    if (on && state.isEnabled) {
      final granted = await _service.requestPermission();
      state = state.copyWith(permissionDenied: !granted);
    }
    await _applySchedule();
  }

  Future<void> setFunEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_funKey, on);
    state = state.copyWith(funEnabled: on);
    if (on && state.isEnabled) {
      final granted = await _service.requestPermission();
      state = state.copyWith(permissionDenied: !granted);
    }
    await _applySchedule();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, time.hour);
    await prefs.setInt(_minuteKey, time.minute);
    state = state.copyWith(reminderTime: time);
    await _applySchedule();
  }

  /// Record an event: always in the in-app list; as a system notification
  /// only when the app isn't on screen (otherwise the user already sees it).
  Future<void> notify(
    NotificationKind kind, {
    required String title,
    required String body,
    String? route,
    AppLifecycleState? lifecycle,
  }) async {
    if (!state.isEnabled) return;
    final category = switch (kind) {
      NotificationKind.recommendationsReady => 'recommendations',
      NotificationKind.analysisDone => 'analysis',
      NotificationKind.tryOnReady => 'tryon',
      NotificationKind.dailyReminder => 'reminder',
    };
    final item = AppNotificationItem(
      id: '${kind.name}-${DateTime.now().microsecondsSinceEpoch}',
      title: title, subtitle: body, createdAt: DateTime.now(), category: category, route: route,
    );
    state = state.copyWith(items: [item, ...state.items].take(_maxItems).toList());
    await _persistItems();
    final appState = lifecycle ?? WidgetsBinding.instance.lifecycleState;
    if (appState != AppLifecycleState.resumed) {
      await _service.show(kind, title: title, body: body, route: route);
    }
  }

  void markAsRead(String id) {
    state = state.copyWith(items: [for (final i in state.items) i.id == id ? i.copyWith(isNew: false) : i]);
    _persistItems();
  }

  void markAllAsRead() {
    state = state.copyWith(items: [for (final i in state.items) i.copyWith(isNew: false)]);
    _persistItems();
  }

  void clearAll() {
    state = state.copyWith(items: []);
    _persistItems();
  }
}

final notificationNotifierProvider = StateNotifierProvider<NotificationNotifier, NotificationState>(
  (ref) => NotificationNotifier(),
);
