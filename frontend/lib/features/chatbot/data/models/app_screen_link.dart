import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/router/route_paths.dart';

/// A screen Zayn can send the user to when he answers "how do I…?" / "where
/// is…?" (the backend's `open` field; chat_orchestrator/tools.py SCREENS).
/// Only these: any other value from the server is ignored, never followed.
enum AppScreenLink {
  home('home', 'Open Home', Icons.home_rounded, RoutePaths.home),
  tryOn('tryon', 'Open Virtual Try-On', Icons.checkroom_rounded, RoutePaths.tryOn),
  hairstyle('hairstyle', 'Open AI Hairstyle', Icons.face_retouching_natural, RoutePaths.hairstyle),
  chat('chat', 'Chat with Zayn', Icons.auto_awesome_rounded, RoutePaths.chat),
  wardrobe('wardrobe', 'Open Saved', Icons.favorite_rounded, RoutePaths.wardrobe),
  profile('profile', 'Open Profile', Icons.person_rounded, RoutePaths.profile),
  editProfile('edit_profile', 'Edit my profile', Icons.tune_rounded, RoutePaths.profileSetup, opensAbove: true),
  help('help', 'Open Help & support', Icons.help_outline_rounded, RoutePaths.help, opensAbove: true),
  privacy('privacy', 'Open Privacy & security', Icons.lock_outline_rounded, RoutePaths.privacy, opensAbove: true);

  const AppScreenLink(this.key, this.label, this.icon, this.route, {this.opensAbove = false});

  /// The value the backend sends.
  final String key;
  final String label;
  final IconData icon;
  final String route;

  /// Opens on top of the tabs (back returns to the chat) instead of switching tab.
  final bool opensAbove;

  /// Where it is kept on a saved chat message.
  static const metadataKey = 'open_screen';

  static AppScreenLink? fromKey(String? key) {
    if (key == null) return null;
    for (final link in values) {
      if (link.key == key) return link;
    }
    return null;
  }

  void open(BuildContext context) {
    if (opensAbove) {
      context.push(route);
    } else {
      context.go(route);
    }
  }
}
