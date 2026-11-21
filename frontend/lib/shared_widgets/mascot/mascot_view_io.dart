import 'dart:convert';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A bundled three.js page (assets/mascot/*.html) in a WebView on Android /
/// iOS. [commands] are posted to the page (window.postMessage) whenever they
/// change; [active] false pauses its rendering. Desktop, tests, or a device
/// without WebGL get [fallback].
class MascotView extends StatefulWidget {
  const MascotView({
    super.key,
    required this.asset,
    required this.commands,
    required this.active,
    required this.fallback,
    this.title = '',
  });

  final String asset;
  final List<Map<String, Object>> commands;
  final bool active;
  final Widget fallback;

  /// The iframe title on the web (screen readers); unused here.
  final String title;

  @override
  State<MascotView> createState() => _MascotViewState();
}

class _MascotViewState extends State<MascotView> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;
  Timer? _readyTimeout;

  /// A WebView is a platform view: it paints over anything Flutter draws, so a
  /// page that loads but never reports "ready" would sit as an empty box on
  /// top of the still frame. Give up after this and show the still frame only.
  static const _readyDeadline = Duration(seconds: 8);
  String _sent = '';

  static bool get _supported =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (!_supported) {
      _failed = true;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('MascotChannel', onMessageReceived: (message) {
        if (!mounted) return;
        if (message.message == 'ready') {
          _readyTimeout?.cancel();
          setState(() => _ready = true);
          _push(force: true);
        } else if (message.message == 'nowebgl') {
          _giveUp();
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        // Only the bundled page: never navigate to the network.
        onNavigationRequest: (request) => request.url.startsWith('file:') || request.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (error) {
          if (mounted && (error.isForMainFrame ?? true)) _giveUp();
        },
      ))
      ..loadFlutterAsset(widget.asset);
    _readyTimeout = Timer(_readyDeadline, () {
      if (!_ready) _giveUp();
    });
  }

  @override
  void dispose() {
    _readyTimeout?.cancel();
    super.dispose();
  }

  /// Keep the still frame instead of an empty WebView.
  void _giveUp() {
    _readyTimeout?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  @override
  void didUpdateWidget(MascotView old) {
    super.didUpdateWidget(old);
    _push();
  }

  List<Map<String, Object>> get _all => [
        ...widget.commands,
        {'mascot': widget.active ? 'resume' : 'pause'},
      ];

  void _push({bool force = false}) {
    final c = _controller;
    if (c == null || !_ready) return;
    final all = _all;
    final key = jsonEncode(all);
    if (!force && key == _sent) return;
    _sent = key;
    final script = all.map((m) => 'window.postMessage(${jsonEncode(m)}, "*");').join();
    c.runJavaScript(script).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null) return widget.fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Taps go to the Flutter widget around it, not into the page.
        IgnorePointer(child: WebViewWidget(controller: c)),
        if (!_ready) widget.fallback,
      ],
    );
  }
}
