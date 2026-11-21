import 'package:flutter/material.dart';
import 'package:smartfit/shared_widgets/mascot/mascot_view.dart';

import 'zayn_mood.dart';

/// Zayn's 3D page (assets/mascot/zayn.html): mood, reduced motion and the
/// talking animation, sent to the page whenever they change.
class ZaynSurface extends StatelessWidget {
  const ZaynSurface({
    super.key,
    required this.mood,
    required this.reducedMotion,
    required this.active,
    required this.fallback,
    this.speaking = false,
  });

  static const asset = 'assets/mascot/zayn.html';

  final ZaynMood mood;
  final bool reducedMotion;

  /// False while the chat is off screen: the page stops rendering.
  final bool active;
  final Widget fallback;

  /// Talking mouth + sound waves while Zayn's voice plays.
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    return MascotView(
      asset: asset,
      title: 'Zayn, your AI stylist',
      active: active,
      fallback: fallback,
      commands: [
        {'zayn': 'setMood', 'mood': mood.name},
        {'zayn': 'reduced', 'value': reducedMotion},
        {'zayn': 'speaking', 'value': speaking},
      ],
    );
  }
}
