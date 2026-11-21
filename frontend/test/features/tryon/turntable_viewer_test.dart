import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/tryon/widgets/turntable_viewer.dart';

// 1x1 transparent PNG
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

List<TurntableFrame> _frames(List<String> labels) => [
  for (final l in labels) TurntableFrame(image: MemoryImage(_png), label: l),
];

Widget _host(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900), disableAnimations: true),
    child: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
    ),
  ),
);

void main() {
  const sides = ['Front', 'Right side', 'Back', 'Left side'];

  testWidgets('dragging turns the figure to the next side', (tester) async {
    await tester.pumpWidget(_host(TurntableViewer(frames: _frames(sides), initialAutoSpin: false)));
    expect(find.text('360° · Front'), findsOneWidget);

    // A quarter of the width = one side.
    await tester.drag(find.byType(AspectRatio), const Offset(-95, 0));
    await tester.pumpAndSettle();
    expect(find.text('360° · Right side'), findsOneWidget);

    // Dragging the other way turns back, wrapping around past the front.
    await tester.drag(find.byType(AspectRatio), const Offset(190, 0));
    await tester.pumpAndSettle();
    expect(find.text('360° · Left side'), findsOneWidget);
  });

  testWidgets('tapping a side jumps to it', (tester) async {
    await tester.pumpWidget(_host(TurntableViewer(frames: _frames(sides), initialAutoSpin: false)));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('360° · Back'), findsOneWidget);
  });

  testWidgets('one image is a plain zoomable picture, no spin controls', (tester) async {
    await tester.pumpWidget(_host(TurntableViewer(frames: _frames(['Front']))));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Drag to turn around'), findsNothing);
    expect(find.byTooltip('Zoom'), findsOneWidget);
  });

  testWidgets('the zoom page opens with pinch-zoom', (tester) async {
    await tester.pumpWidget(_host(TurntableViewer(frames: _frames(sides), initialAutoSpin: false)));
    await tester.tap(find.byTooltip('Zoom'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsWidgets);
    expect(find.textContaining('pinch to zoom'), findsOneWidget);
  });

  // ── it keeps turning (20 Nov 2026) ──────────────────────────────────────────

  Widget moving(Widget child) => MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 900)), // animations on
      child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 360, child: child))),
    ),
  );

  String side(WidgetTester tester) =>
      tester.widgetList<Text>(find.textContaining('360° · ')).first.data!.replaceFirst('360° · ', '');

  testWidgets('turns by itself, side after side', (tester) async {
    await tester.pumpWidget(moving(TurntableViewer(frames: _frames(sides))));
    expect(side(tester), 'Front');
    final seen = <String>{};
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      seen.add(side(tester));
    }
    expect(seen, containsAll(sides)); // a full turn in 8 s (1.6 s a side)
    await tester.pumpWidget(const SizedBox()); // stop the ticker
  });

  testWidgets('a drag pauses it only for a moment, then it keeps turning', (tester) async {
    await tester.pumpWidget(moving(TurntableViewer(frames: _frames(sides), resumeAfter: const Duration(seconds: 2))));
    await tester.drag(find.byType(AspectRatio), const Offset(-95, 0));
    await tester.pump(const Duration(milliseconds: 400)); // snap finished
    final heldAt = side(tester);
    await tester.pump(const Duration(milliseconds: 1200)); // still inside the pause
    expect(side(tester), heldAt);
    await tester.pump(const Duration(seconds: 1)); // the pause is over
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(side(tester), isNot(heldAt));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the pause button keeps it still until play is pressed', (tester) async {
    await tester.pumpWidget(moving(TurntableViewer(frames: _frames(sides))));
    await tester.tap(find.byTooltip('Stop spinning'));
    await tester.pump();
    final stoppedAt = side(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(side(tester), stoppedAt);
    await tester.tap(find.byTooltip('Spin'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(side(tester), isNot(stoppedAt));
    await tester.pumpWidget(const SizedBox());
  });
}
