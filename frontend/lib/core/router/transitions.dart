import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/shared_widgets/page_loading_gate.dart';

/// Page transitions (design.md §5.2): shared-axis for moving forward through
/// a flow, fade-through for switching between unrelated screens. Both are
/// skipped when the OS "reduce motion" setting is on. Every page opened this
/// way starts behind the 2-3 s SmartFit loader (PageLoadingGate) unless
/// [loading] is false (the splash, which has its own).

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Forward navigation through a flow (e.g. welcome -> login -> register).
CustomTransitionPage<void> sharedAxisPage(
  GoRouterState state,
  Widget child, {
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
  bool loading = true,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: loading ? PageLoadingGate(child: child) : child,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (_reduceMotion(context)) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: type,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      );
    },
  );
}

/// Switching to an unrelated destination (e.g. into the app after sign-in).
CustomTransitionPage<void> fadeThroughPage(GoRouterState state, Widget child, {bool loading = true}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: loading ? PageLoadingGate(child: child) : child,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (_reduceMotion(context)) return child;
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      );
    },
  );
}
