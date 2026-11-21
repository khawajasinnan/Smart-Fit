import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/router/route_paths.dart';

/// Goes back if there is a previous screen, otherwise to Home. Safe on tab
/// root screens and on screens opened with `go`, where a plain `pop` would
/// remove the only page.
void goBackOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(RoutePaths.home);
  }
}

/// App-bar back button that uses [goBackOrHome].
class SFBackButton extends StatelessWidget {
  const SFBackButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(Icons.arrow_back_rounded, color: color),
      onPressed: () => goBackOrHome(context),
    );
  }
}
