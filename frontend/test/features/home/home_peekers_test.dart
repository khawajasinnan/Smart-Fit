import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/home/widgets/home_peekers.dart';

/// The home-screen eyes buddy (spec §23.16).
void main() {
  testWidgets('shows the still eyes without WebGL, follows taps, reacts and gets sleepy', (tester) async {
    final controller = PeekersController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Listener(
          onPointerDown: (e) => controller.lookAt(e.position),
          child: Column(children: [HomePeekers(controller: controller), const Expanded(child: SizedBox.expand())]),
        ),
      ),
    ));
    // tests have no WebView: the still frame is shown
    expect(find.byType(Image), findsOneWidget);
    expect(find.bySemanticsLabel('SmartFit buddy eyes. Tap for a trick, hold for love.'), findsOneWidget);
    expect(tester.getSize(find.byType(HomePeekers)), const Size(150, 76));

    await tester.tapAt(const Offset(300, 500)); // look somewhere else
    await tester.tap(find.byType(HomePeekers)); // react
    await tester.longPress(find.byType(HomePeekers)); // love
    controller.react('star');
    await tester.pump(const Duration(seconds: 26)); // idle -> sleepy timer fires without errors
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every tap plays a different trick until all have been shown', (tester) async {
    final controller = PeekersController();
    addTearDown(controller.dispose);
    final key = GlobalKey<State<HomePeekers>>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HomePeekers(key: key, controller: controller)),
    ));

    // The reaction is what the page is told to play; read it off the command list.
    String current() {
      final view = tester.widget<HomePeekers>(find.byType(HomePeekers));
      expect(view.controller, controller);
      return (key.currentState! as dynamic).debugReaction as String;
    }

    final seen = <String>{};
    for (var i = 0; i < HomePeekers.reactions.length; i++) {
      await tester.tap(find.byType(HomePeekers));
      await tester.pump();
      seen.add(current());
    }
    // one full shuffled pass covers every trick exactly once
    expect(seen, HomePeekers.reactions.toSet());
    expect(seen, contains('jump'));
    expect(seen, contains('star'));
  });
}
