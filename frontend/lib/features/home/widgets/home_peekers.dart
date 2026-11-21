import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/mascot/mascot_view.dart';

/// Tells the home-screen eyes where the user tapped (spec §23.16).
class PeekersController extends ChangeNotifier {
  Offset? _target;
  int _lookSeq = 0;
  String? _reaction;
  int _reactSeq = 0;

  /// Look toward a point on the screen (global coordinates).
  void lookAt(Offset global) {
    _target = global;
    _lookSeq++;
    notifyListeners();
  }

  /// happy | surprised | wink | love | sleepy, or a big "solid" action:
  /// jump | spin | dizzy | roll | cross | laugh | peek | star.
  void react(String name) {
    _reaction = name;
    _reactSeq++;
    notifyListeners();
  }
}

/// Lets any home card make the eyes react: `PeekersScope.maybeOf(context)?.react('star')`.
class PeekersScope extends InheritedWidget {
  const PeekersScope({super.key, required this.controller, required super.child});

  final PeekersController controller;

  static PeekersController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeekersScope>()?.controller;

  @override
  bool updateShouldNotify(PeekersScope old) => old.controller != controller;
}

/// "Peekers": a pair of 3D cartoon eyes peeking over the home header. They
/// blink, glance around, follow taps anywhere on the home screen, get sleepy
/// when the user is idle, and do big "solid" actions: on their own every few
/// seconds, when tapped (a different one each time), and when something
/// happens on the home screen (a challenge done, another tip...).
class HomePeekers extends StatefulWidget {
  const HomePeekers({super.key, required this.controller, this.width = 150, this.height = 76});

  final PeekersController controller;
  final double width;
  final double height;

  static const asset = 'assets/mascot/eyes.html';

  /// What a tap does, in turn (shuffled): the big actions plus a few expressions.
  static const reactions = ['jump', 'spin', 'dizzy', 'roll', 'cross', 'laugh', 'peek', 'star', 'wink', 'love'];

  @override
  State<HomePeekers> createState() => _HomePeekersState();
}

class _HomePeekersState extends State<HomePeekers> with WidgetsBindingObserver {
  final _random = Random();
  double _x = 0, _y = 0;
  int _lookSeq = 0;
  String _reaction = 'happy';
  int _reactSeq = 0;
  Timer? _idle;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onController);
    // say hi when the home screen opens
    _reactSeq = 1;
    _armIdle();
  }

  @override
  void didUpdateWidget(HomePeekers old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.controller.removeListener(_onController);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible != _appVisible) setState(() => _appVisible = visible);
  }

  /// Sleepy after 25 s without a tap.
  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 25), () {
      if (mounted) setState(() => _react('sleepy'));
    });
  }

  void _react(String name) {
    _reaction = name;
    _reactSeq++;
  }

  /// The trick currently being played (tests).
  @visibleForTesting
  String get debugReaction => _reaction;

  void _onController() {
    final c = widget.controller;
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      if (c._lookSeq != _lookSeq && c._target != null && box != null && box.hasSize) {
        final centre = box.localToGlobal(box.size.center(Offset.zero));
        final screen = MediaQuery.sizeOf(context);
        _x = ((c._target!.dx - centre.dx) / (screen.width / 2)).clamp(-1.0, 1.0);
        _y = (-(c._target!.dy - centre.dy) / (screen.height / 2)).clamp(-1.0, 1.0);
        _lookSeq = c._lookSeq;
        if (_reaction == 'sleepy') _react('surprised'); // a tap wakes them up
      }
      if (c._reactSeq > 0 && c._reaction != null && c._reactSeq != _lastControllerReact) {
        _lastControllerReact = c._reactSeq;
        _react(c._reaction!);
      }
    });
    _armIdle();
  }

  int _lastControllerReact = 0;
  final List<String> _tapQueue = [];

  /// A different action on every tap until all have been shown, then reshuffled.
  String _nextTapReaction() {
    if (_tapQueue.isEmpty) {
      _tapQueue.addAll(HomePeekers.reactions);
      _tapQueue.shuffle(_random);
      if (_tapQueue.first == _reaction && _tapQueue.length > 1) _tapQueue.add(_tapQueue.removeAt(0));
    }
    return _tapQueue.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final active = _appVisible && TickerMode.valuesOf(context).enabled;
    return Semantics(
      label: 'SmartFit buddy eyes. Tap for a trick, hold for love.',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() => _react(_nextTapReaction()));
          _armIdle();
        },
        onLongPress: () {
          HapticFeedback.heavyImpact();
          setState(() => _react('love'));
          _armIdle();
        },
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: MascotView(
            asset: HomePeekers.asset,
            title: 'SmartFit buddy eyes',
            active: active,
            fallback: Image.asset(
              // one still frame for both themes; the live eyes take their colours from {'eyes': 'theme'}
              'assets/mascot/still/eyes.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            commands: [
              {'eyes': 'reduced', 'value': reduced},
              {'eyes': 'theme', 'dark': context.isDark},
              {'eyes': 'look', 'x': _x, 'y': _y, 'seq': _lookSeq},
              {'eyes': 'react', 'name': _reaction, 'seq': _reactSeq},
            ],
          ),
        ),
      ),
    );
  }
}
