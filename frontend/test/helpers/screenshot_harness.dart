import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

/// Developer screenshot harness (not a CI test).
///
/// Renders widgets with the app's real fonts and theme at phone size and
/// saves PNGs, so UI can be reviewed without an emulator:
///
///   SF_SCREENSHOT_DIR=/some/dir flutter test test/screenshots
///
/// Without SF_SCREENSHOT_DIR every screenshot test is skipped.
///
/// Tests can't reach the network, so network photos render as the branded
/// fallback — unless SF_SCREENSHOT_IMAGES points at a folder of downloaded
/// Unsplash photos named `<photo-id>.jpg` (e.g. photo-1515886657613-9f3515b0c78f.jpg).
final String? screenshotDir = Platform.environment['SF_SCREENSHOT_DIR'];
final bool screenshotsEnabled = screenshotDir != null && screenshotDir!.isNotEmpty;
final String? _imagesDir = Platform.environment['SF_SCREENSHOT_IMAGES'];

final _photoId = RegExp(r'photo-[0-9a-f]+-[0-9a-f]+');

/// Resolves a network URL to a local file from SF_SCREENSHOT_IMAGES, or to
/// an undecodable image (→ SafeNetworkImage's fallback) when there is none.
ImageProvider _localImage(String url) {
  final id = _photoId.firstMatch(url)?.group(0);
  if (_imagesDir != null && id != null) {
    final file = File('${_imagesDir!}/$id.jpg');
    if (file.existsSync()) return FileImage(file);
  }
  return MemoryImage(Uint8List(0));
}

const _boundaryKey = ValueKey('sf-screenshot-boundary');
bool _fontsLoaded = false;

/// Loads every font in the app's FontManifest (Space Grotesk, Inter and
/// Material Icons) instead of the test-only "Ahem" boxes.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

/// Pumps [child] inside the app theme on a phone-sized screen.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 844),
  bool wrapInScaffold = false,
  List<Override> overrides = const [],
}) async {
  await loadAppFonts();
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SafeNetworkImage.debugImageProviderOverride = _localImage;
  addTearDown(() => SafeNetworkImage.debugImageProviderOverride = null);
  await _warmLocalImages(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: wrapInScaffold ? Scaffold(body: child) : child,
        ),
      ),
    ),
  );
}

/// Decodes the SF_SCREENSHOT_IMAGES photos into the image cache with real
/// async before anything is pumped. Decoding started inside the fake test
/// zone never finishes, so Image widgets must find them already cached.
Future<void> _warmLocalImages(WidgetTester tester) async {
  final dir = _imagesDir;
  if (dir == null || !Directory(dir).existsSync()) return;
  await tester.runAsync(() async {
    for (final entry in Directory(dir).listSync().whereType<File>()) {
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.jpg')) continue;
      // Same path spelling as _localImage, so the FileImage cache keys match.
      final stream = FileImage(File('$dir/$name')).resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      final listener = ImageStreamListener(
        (_, _) => done.isCompleted ? null : done.complete(),
        onError: (_, _) => done.isCompleted ? null : done.complete(),
      );
      stream.addListener(listener);
      await done.future;
      stream.removeListener(listener);
    }
  });
}

/// Advances [total] time in real frames. Use instead of `pumpAndSettle` when
/// ambient loops (orbs, shimmer) never settle, and instead of one long
/// `pump` so timer-started entrance animations actually run.
Future<void> pumpFrames(WidgetTester tester, [Duration total = const Duration(seconds: 2)]) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Saves the current frame as `<name>.png` in SF_SCREENSHOT_DIR.
Future<void> saveScreenshot(WidgetTester tester, String name, {double pixelRatio = 1.5}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${screenshotDir!}/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
