import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// A bundled three.js page (assets/mascot/*.html) in an iframe on Flutter
/// web. Same API as the mobile WebView version.
///
/// On web an iframe is a platform view, and the browser paints it *over*
/// anything Flutter draws — so a blank or broken iframe would cover the still
/// fallback instead of the other way round. The iframe is therefore kept
/// hidden until the page says "ready", and if it never does (no WebGL, an
/// asset that didn't load, a stale build) it is dropped from the tree
/// entirely and only the still frame is shown.
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
  final String title;

  @override
  State<MascotView> createState() => _MascotViewState();
}

class _MascotViewState extends State<MascotView> {
  static int _views = 0;

  late final String _viewType = 'smartfit-mascot-${_views++}';
  web.HTMLIFrameElement? _frame;
  JSFunction? _listener;
  bool _ready = false;
  bool _failed = false;
  String _sent = '';
  Timer? _readyTimeout;

  /// How long the page gets to load before we give up and show the still frame.
  static const _readyDeadline = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    final src = ui_web.assetManager.getAssetUrl(widget.asset);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final frame = web.HTMLIFrameElement()
        ..src = src
        ..title = widget.title;
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        ..background = 'transparent'
        ..pointerEvents = 'none' // taps go to Flutter
        // hidden until the page reports "ready", so a blank or broken iframe
        // never covers the still frame underneath it
        ..visibility = _ready ? 'visible' : 'hidden';
      _frame = frame;
      return frame;
    });
    _listener = ((web.MessageEvent event) {
      if (!mounted || event.source != _frame?.contentWindow) return;
      final data = event.data;
      if (data == null || !data.isA<JSObject>()) return;
      final message = (data as JSObject).getProperty<JSAny?>('mascotEvent'.toJS);
      if (message == null || !message.isA<JSString>()) return;
      final text = (message as JSString).toDart;
      if (text == 'ready') {
        _readyTimeout?.cancel();
        _frame?.style.visibility = 'visible';
        setState(() => _ready = true);
        _push(force: true);
      } else if (text == 'nowebgl') {
        _giveUp();
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    // the page never answered: show the still frame instead of an empty box
    _readyTimeout = Timer(_readyDeadline, () {
      if (!_ready) _giveUp();
    });
  }

  /// Drop the iframe and keep the still frame: build() stops returning the
  /// platform view, so the element goes away and can't paint over Flutter.
  void _giveUp() {
    _readyTimeout?.cancel();
    _frame?.style.display = 'none';
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
    if (!_ready) return;
    final all = _all;
    final key = jsonEncode(all);
    if (!force && key == _sent) return;
    _sent = key;
    final target = _frame?.contentWindow;
    if (target == null) return;
    for (final m in all) {
      target.postMessage(m.jsify(), '*'.toJS);
    }
  }

  @override
  void dispose() {
    _readyTimeout?.cancel();
    if (_listener != null) web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready) widget.fallback,
      ],
    );
  }
}
