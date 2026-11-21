import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/router/app_shell.dart';

/// A tab page with a counter, to prove each tab keeps its own state.
class _Counter extends StatefulWidget {
  const _Counter(this.name);
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${widget.name}: $taps'),
          TextButton(onPressed: () => setState(() => taps++), child: Text('tap ${widget.name}')),
          TextButton(onPressed: () => context.push('/${widget.name}/detail'), child: Text('open ${widget.name}')),
        ]),
      );
}

GoRouter _router() {
  StatefulShellBranch branch(String name) => StatefulShellBranch(routes: [
        GoRoute(
          path: '/$name',
          builder: (_, _) => _Counter(name),
          routes: [GoRoute(path: 'detail', builder: (_, _) => Text('$name detail'))],
        ),
      ]);
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughBranchContainer(currentIndex: shell.currentIndex, children: children),
        branches: [for (final n in ['home', 'tryon', 'hair', 'chat', 'saved', 'profile']) branch(n)],
      ),
    ],
  );
}

Future<void> _settle(WidgetTester tester) async {
  // The nav bar has a looping "breathing" animation, so pumpAndSettle would
  // never finish; pump past the 260 ms tab transition instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('tabs switch, keep their state, and reset on re-tap', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);

    expect(find.text('Home'), findsOneWidget); // nav labels (SRDS order)
    expect(find.text('Try-On'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('tap home'));
    await tester.tap(find.text('tap home'));
    await _settle(tester);
    expect(find.text('home: 2'), findsOneWidget);

    // Switch to Saved (index 4) and back: Home's counter survives.
    await tester.tap(find.text('Saved'));
    await _settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/saved');
    await tester.tap(find.text('Home'));
    await _settle(tester);
    expect(find.text('home: 2'), findsOneWidget);

    // Open a detail page inside Home, then re-tap Home -> back to its root.
    await tester.tap(find.text('open home'));
    await _settle(tester);
    expect(find.text('home detail'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await _settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('hidden tabs ignore taps', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    await tester.tap(find.text('Profile'));
    await _settle(tester);
    // Home is still built (state kept) but must not be hittable.
    expect(find.text('tap home', skipOffstage: false), findsOneWidget);
    expect(find.text('tap home').hitTestable(), findsNothing);
    expect(find.text('tap profile').hitTestable(), findsOneWidget);
  });

  testWidgets('a tab you leave becomes invisible (it must not cover the next tab)', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);

    // Opacity actually painted for the tab containing [text].
    double opacityOf(String text) => tester
        .renderObject<RenderAnimatedOpacity>(
          find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity
        .value;

    // Profile is the last tab, painted on top of all others.
    await tester.tap(find.text('Profile'));
    await _settle(tester);
    expect(opacityOf('profile: 0'), 1);

    await tester.tap(find.text('Home'));
    await _settle(tester);
    expect(opacityOf('home: 0'), 1);
    expect(opacityOf('profile: 0'), 0, reason: 'hidden Profile tab would still cover Home');
  });
}
