import 'package:flutter/material.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/drifting_orbs.dart';

/// The standard SmartFit page: theme background, drifting gradient orbs and
/// the clothing-icon pattern behind the content (design.md §1).
class SFScaffold extends StatelessWidget {
  const SFScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showOrbs = true,
    this.showPattern = true,
    this.orbIntensity = 1,
    this.patternOpacity,
    this.safeArea = true,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showOrbs;
  final bool showPattern;
  final double orbIntensity;
  final double? patternOpacity;

  /// Wrap the body in a SafeArea (off for full-bleed hero layouts).
  final bool safeArea;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: appBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (showOrbs) Positioned.fill(child: DriftingOrbs(intensity: orbIntensity)),
          if (showPattern) Positioned.fill(child: ClothingPatternBackground(opacity: patternOpacity)),
          if (safeArea) SafeArea(bottom: false, child: body) else body,
        ],
      ),
    );
  }
}
