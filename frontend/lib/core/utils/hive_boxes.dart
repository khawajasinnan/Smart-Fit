import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// Deletes a local Hive box (every app box holds strings). Never throws and never hangs.
///
/// The box is closed first: on the web, Hive deletes the box's IndexedDB database without
/// closing its own open connection, and the browser then waits for that connection forever
/// (found by the E2E run, 20 Nov 2026: "Delete account" spun for good after the server had
/// already deleted everything). The time limit is a last safety net.
Future<void> deleteLocalBox(String name, {Duration timeout = const Duration(seconds: 5)}) async {
  try {
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close().timeout(timeout);
  } catch (_) {}
  try {
    await Hive.deleteBoxFromDisk(name).timeout(timeout);
  } catch (_) {}
}
