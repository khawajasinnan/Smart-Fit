import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/shared_widgets/sf_bottom_nav_bar.dart';

/// The 6-tab app frame (Home, Try-On, Hair, Stylist, Saved, Profile). Each tab keeps its own navigation
/// stack and scroll position; tapping the current tab again returns it to
/// its first screen.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // Hide the bar while typing (e.g. the stylist chat input).
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: keyboardOpen
          ? null
          : SFBottomNavBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            ),
    );
  }
}

/// Shows the active tab with a fade-through (fade + slight scale) when
/// switching tabs. Inactive tabs stay alive (state kept) but don't paint,
/// receive taps, or run animations.
class FadeThroughBranchContainer extends StatelessWidget {
  const FadeThroughBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Branch(
            active: i == currentIndex,
            duration: duration,
            child: children[i],
          ),
      ],
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.active, required this.duration, required this.child});

  final bool active;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TickerMode must sit INSIDE the fade: placed outside, it also froze the
    // fade-out itself, so a tab you left stayed fully opaque and (being
    // higher in the Stack) covered the tab you switched to.
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: duration,
        curve: active ? const Interval(0.3, 1, curve: Curves.easeOut) : Curves.easeIn,
        child: AnimatedScale(
          scale: active ? 1 : 0.96,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: TickerMode(
            enabled: active,
            // Hidden tabs are excluded from accessibility (screen readers).
            child: ExcludeSemantics(excluding: !active, child: child),
          ),
        ),
      ),
    );
  }
}
