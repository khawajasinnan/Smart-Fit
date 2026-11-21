import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/shared_widgets/sf_loader.dart';

/// How long a newly opened screen shows the loader (spec §23.19: 2-3 s).
const Duration kPageLoadDuration = Duration(milliseconds: 2200);

/// Every newly opened screen (sign in / up, profile setup, the app's tabs on
/// arrival, settings pages, ...) starts behind the SmartFit loader: the
/// spinning 3D tee in its rounded ring, with a playful line. The screen builds
/// and loads its data underneath, then the cover fades away. Taps wait until
/// it's gone. Switching between bottom tabs never shows it.
class PageLoadingGate extends StatefulWidget {
  const PageLoadingGate({super.key, required this.child, this.duration = kPageLoadDuration});

  final Widget child;
  final Duration duration;

  /// Off in widget tests (a spinner never "settles"); on in the app.
  static bool enabled = true;

  static const lines = [
    'Steaming the fabric…',
    'Picking your perfect fit…',
    'Asking Zayn for a second opinion…',
    'Matching colours to your skin tone…',
    'Ironing out the details…',
    'Raiding the new arrivals…',
  ];

  @override
  State<PageLoadingGate> createState() => _PageLoadingGateState();
}

class _PageLoadingGateState extends State<PageLoadingGate> {
  late bool _covering = PageLoadingGate.enabled;
  late final String _line = PageLoadingGate.lines[Random().nextInt(PageLoadingGate.lines.length)];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_covering) {
      _timer = Timer(widget.duration, () {
        if (mounted) setState(() => _covering = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ClothFrames.precache(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_covering,
            child: AnimatedOpacity(
              opacity: _covering ? 1 : 0,
              duration: reduced ? Duration.zero : const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              child: _covering || !reduced ? _Cover(line: _line) : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Material(
      color: bg,
      child: DecoratedBox(
        decoration: const BoxDecoration(), // flat: no glow behind the loader
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: 'Loading. $line',
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SFLoader(size: 136),
                const SizedBox(height: 18),
                Text(line, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: sf.textMuted,
                  fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
