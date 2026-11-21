import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfit/core/providers/notification_provider.dart';

/// "Notify me" on a feature that isn't live yet: turns SmartFit notifications
/// on (asking the phone for permission) so the user hears when the feature
/// produces something for them.
Future<void> notifyMeTapped(BuildContext context, WidgetRef ref, String feature) async {
  HapticFeedback.mediumImpact();
  final messenger = ScaffoldMessenger.of(context);
  final granted = await ref.read(notificationNotifierProvider.notifier).setEnabled(true);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(granted
          ? "Notifications are on 🔔 We'll let you know as soon as $feature is ready for you."
          : 'Allow notifications for SmartFit in your phone settings, then tap Notify me again.'),
    ));
}
