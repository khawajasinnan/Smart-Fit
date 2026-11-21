import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// One side of the turntable: a 2D try-on image and its label.
class TurntableFrame {
  const TurntableFrame({required this.image, required this.label});

  final ImageProvider image;
  final String label;
}

/// Drag-to-spin 360° view built from 2D images taken around the user
/// (front, right, back, left). It turns by itself and keeps turning: a drag,
/// a tap on a side or the zoom only pause it for a moment ([resumeAfter]),
/// and only the pause button stops it until play is pressed (20 Nov 2026:
/// "it should keep rotating"). Between two sides the images cross-fade while
/// sliding a little, so it reads as the figure turning. Dragging across the
/// full width turns the figure once; releasing snaps to the nearest side.
/// Tap the zoom button for full-screen pinch-zoom (SFR-028).
///
/// With one frame it is a plain zoomable image. Auto-spin is off whenever the
/// OS "reduce motion" setting is on.
class TurntableViewer extends StatefulWidget {
  const TurntableViewer({
    super.key,
    required this.frames,
    this.aspectRatio = 3 / 4,
    this.initialAutoSpin = true,
    this.resumeAfter = const Duration(milliseconds: 2500),
  });

  final List<TurntableFrame> frames;
  final double aspectRatio;
  final bool initialAutoSpin;

  /// How long a drag, a side tap or the zoom pauses the spin before it turns again.
  final Duration resumeAfter;

  @override
  State<TurntableViewer> createState() => _TurntableViewerState();
}

class _TurntableViewerState extends State<TurntableViewer> with TickerProviderStateMixin {
  /// Continuous position in frames: 0 = first side, 1.5 = half way from the second to the third.
  double _pos = 0;

  /// The pause button: stays paused until play is pressed.
  bool _paused = false;

  /// A drag, side tap or zoom: paused only until [_resumeTimer] fires.
  bool _held = false;
  Timer? _resumeTimer;
  bool _dragging = false;
  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Animation<double>? _snapAnim;
  late final Ticker _spinTicker = createTicker(_onSpinTick);
  Duration _lastTick = Duration.zero;

  static const _secondsPerSide = 1.6;

  /// How far (share of the width) a side slides while the figure turns.
  static const _slide = 0.06;

  int get _n => widget.frames.length;

  @override
  void initState() {
    super.initState();
    _snap.addListener(() {
      final a = _snapAnim;
      if (a != null) setState(() => _pos = a.value);
    });
    _paused = !widget.initialAutoSpin;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final f in widget.frames) {
      precacheImage(f.image, context, onError: (_, _) {}); // a broken frame shows the placeholder
    }
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TurntableViewer old) {
    super.didUpdateWidget(old);
    if (old.frames.length != _n) {
      _pos = _pos.clamp(0, math.max(0, _n - 1)).toDouble();
      _syncTicker();
    }
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Spinning wanted (what the play/pause button shows).
  bool get _spinning => !_paused && _n > 1 && !_reduceMotion;

  void _syncTicker() {
    final shouldRun = _spinning && !_held && !_dragging && !_snap.isAnimating;
    if (shouldRun && !_spinTicker.isActive) {
      _lastTick = Duration.zero;
      _spinTicker.start();
    } else if (!shouldRun && _spinTicker.isActive) {
      _spinTicker.stop();
    }
  }

  void _onSpinTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 0.0 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() => _pos = (_pos + dt / _secondsPerSide) % _n);
  }

  void _animateTo(double target) {
    _snapAnim = Tween<double>(
      begin: _pos,
      end: target,
    ).animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    _snap
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) setState(() => _pos = target % _n);
      });
  }

  /// Pause for a moment (drag, side tap, zoom); turn again after [TurntableViewer.resumeAfter].
  void _hold() {
    _resumeTimer?.cancel();
    _held = true;
    _syncTicker();
  }

  void _resumeLater([Duration? after]) {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(after ?? widget.resumeAfter, () {
      if (!mounted) return;
      _held = false;
      _syncTicker();
    });
  }

  void _goTo(int index) {
    _hold();
    _resumeLater(widget.resumeAfter * 1.5); // time to look at the side that was asked for
    // shortest way round
    var delta = (index - _pos) % _n;
    if (delta > _n / 2) delta -= _n;
    _animateTo(_pos + delta);
  }

  void _setPaused(bool value) {
    if (_paused == value) return;
    setState(() => _paused = value);
    if (!value) {
      _resumeTimer?.cancel();
      _held = false;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _spinTicker.dispose();
    _snap.dispose();
    super.dispose();
  }

  int get _nearest => _n == 0 ? 0 : _pos.round() % _n;

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final base = _pos.floor() % _n;
    final next = (base + 1) % _n;
    final t = _pos - _pos.floorToDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _n < 2
                  ? null
                  : (_) {
                      _snap.stop();
                      _dragging = true;
                      _hold();
                    },
              onHorizontalDragUpdate: _n < 2
                  ? null
                  : (d) => setState(() => _pos = (_pos - d.delta.dx * _n / width) % _n),
              onHorizontalDragEnd: _n < 2
                  ? null
                  : (d) {
                      _dragging = false;
                      // a flick carries on to the next side
                      final flick = -(d.primaryVelocity ?? 0) / width * _n * 0.25;
                      _animateTo((_pos + flick.clamp(-1.0, 1.0)).roundToDouble());
                      HapticFeedback.selectionClick();
                      _resumeLater();
                    },
              onTap: () => _openZoom(context),
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: context.cs.surfaceContainerHigh),
                      // Turning: the side going away slides out a little, the next one slides in.
                      Transform.translate(
                        offset: Offset(-t * width * _slide, 0),
                        child: Image(
                          image: widget.frames[base].image,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: _broken,
                        ),
                      ),
                      if (_n > 1 && t > 0.001)
                        Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset((1 - t) * width * _slide, 0),
                            child: Image(
                              image: widget.frames[next].image,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: _broken,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _Chip(
                          icon: _n > 1 ? Icons.threesixty_rounded : Icons.image_outlined,
                          label: _n > 1 ? '360° · ${widget.frames[_nearest].label}' : widget.frames.first.label,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          tooltip: 'Zoom',
                          onPressed: () => _openZoom(context),
                          icon: const Icon(Icons.zoom_in_rounded),
                        ),
                      ),
                      if (_n > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _Chip(icon: Icons.swipe_rounded, label: 'Drag to turn around'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (_n > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _n; i++)
                      ChoiceChip(
                        label: Text(widget.frames[i].label),
                        selected: i == _nearest,
                        onSelected: (_) => _goTo(i),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              if (!_reduceMotion)
                IconButton(
                  tooltip: _paused ? 'Spin' : 'Stop spinning',
                  onPressed: () => _setPaused(!_paused),
                  icon: Icon(_paused ? Icons.play_circle_rounded : Icons.pause_circle_rounded),
                  color: context.cs.primary,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openZoom(BuildContext context) async {
    _hold();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _ZoomPage(frames: widget.frames, initial: _nearest),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (mounted) _resumeLater();
  }
}

Widget _broken(BuildContext context, Object error, StackTrace? stack) => ColoredBox(
  color: Colors.black12,
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 6),
        Text("Couldn't load this image", style: AppTextStyles.bodySm),
      ],
    ),
  ),
);

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.labelSm.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Full-screen pinch-zoom (up to 5x), one side per page (SFR-028).
class _ZoomPage extends StatefulWidget {
  const _ZoomPage({required this.frames, required this.initial});

  final List<TurntableFrame> frames;
  final int initial;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.frames.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image(image: widget.frames[i].image, fit: BoxFit.contain, errorBuilder: _broken),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  _Chip(icon: Icons.pinch_rounded, label: '${widget.frames[_index].label} · pinch to zoom'),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
