import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a product's retailer page ("View on store").
///
/// No `canLaunchUrl` gate: on Android 11+ it answers false unless the manifest
/// declares the query, and `launchUrl` already reports failure itself. Tries an
/// in-app browser tab first, then the default browser app.
Future<void> openStoreLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final valid = uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  var opened = false;
  if (valid) {
    for (final mode in const [LaunchMode.inAppBrowserView, LaunchMode.externalApplication]) {
      try {
        opened = await launchUrl(uri, mode: mode);
      } catch (_) {
        opened = false;
      }
      if (opened) break;
    }
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text("Couldn't open the store page. Check that a browser is installed."),
      ),
    );
  }
}
