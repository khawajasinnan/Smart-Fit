import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotificationItem {
  final String id;
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final bool isNew;
  final String? category;

  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
    this.isNew = true,
    this.category,
  });

  AppNotificationItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? time,
    IconData? icon,
    bool? isNew,
    String? category,
  }) {
    return AppNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      time: time ?? this.time,
      icon: icon ?? this.icon,
      isNew: isNew ?? this.isNew,
      category: category ?? this.category,
    );
  }
}

class NotificationState {
  final bool isEnabled;
  final List<AppNotificationItem> items;

  const NotificationState({
    this.isEnabled = true,
    this.items = const [],
  });

  int get unreadCount => isEnabled ? items.where((n) => n.isNew).length : 0;

  NotificationState copyWith({
    bool? isEnabled,
    List<AppNotificationItem>? items,
  }) {
    return NotificationState(
      isEnabled: isEnabled ?? this.isEnabled,
      items: items ?? this.items,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  static const _prefKey = 'outfit_notifications_enabled';

  NotificationNotifier() : super(const NotificationState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefKey) ?? true;

    // Initial rich styling notifications
    final defaultItems = [
      const AppNotificationItem(
        id: '1',
        title: '🔥 New Gen-Z Trends Dropped!',
        subtitle: 'Y2K Cyber Cargo and Desi Fusion looks are trending today.',
        time: 'Just now',
        icon: Icons.auto_awesome,
        isNew: true,
        category: 'trends',
      ),
      const AppNotificationItem(
        id: '2',
        title: '👗 AI Stylist Waiting for Fit Check',
        subtitle: 'Ready to rate your outfit today? Drop a photo in chat!',
        time: '25m ago',
        icon: Icons.chat_bubble_outline_rounded,
        isNew: true,
        category: 'chat',
      ),
      const AppNotificationItem(
        id: '3',
        title: '⚡ Wardrobe Reminder',
        subtitle: 'You saved 3 items this week. Tap to test them in Virtual Try-On.',
        time: '2h ago',
        icon: Icons.checkroom_rounded,
        isNew: true,
        category: 'wardrobe',
      ),
      const AppNotificationItem(
        id: '4',
        title: '✨ Trending in Pakistan',
        subtitle: 'Summer Chikankari & Retro Baggy Fits are blowing up on TikTok.',
        time: '1d ago',
        icon: Icons.trending_up_rounded,
        isNew: false,
        category: 'local',
      ),
      const AppNotificationItem(
        id: '5',
        title: '🎉 Welcome to SmartFit!',
        subtitle: 'Your 3D digital twin is ready to style you in haute couture.',
        time: '3d ago',
        icon: Icons.celebration_rounded,
        isNew: false,
        category: 'system',
      ),
    ];

    state = NotificationState(
      isEnabled: enabled,
      items: defaultItems,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    state = state.copyWith(isEnabled: enabled);
  }

  void markAsRead(String id) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.id == id) {
          return item.copyWith(isNew: false);
        }
        return item;
      }).toList(),
    );
  }

  void markAllAsRead() {
    state = state.copyWith(
      items: state.items.map((item) => item.copyWith(isNew: false)).toList(),
    );
  }

  void clearAll() {
    state = state.copyWith(items: []);
  }

  void addNotification(AppNotificationItem item) {
    state = state.copyWith(
      items: [item, ...state.items],
    );
  }
}

final notificationNotifierProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});
