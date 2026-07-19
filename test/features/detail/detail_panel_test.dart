import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/detail/detail_panel.dart';

/// The shared detail `.panel` shell (`index.html:105-106`).
///
/// The three panels that use it already assert their own contents, so what this
/// file pins is what only the shared widget can now get wrong — the surface the
/// prototype's CSS specifies, and the two branches of the optional heading. The
/// heading-absent branch matters most: it exists solely for the grown-up facts
/// card, whose own suite reads text rather than structure, so nothing else would
/// notice a stray `h4` appearing above a panel the prototype gives none
/// (`index.html:608`).
void main() {
  Future<void> pumpPanel(WidgetTester tester, DetailPanel panel) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: panel)),
      ),
    );
  }

  testWidgets(
    'wears the `.panel` surface — card fill, 16px radius, line border',
    (WidgetTester tester) async {
      await pumpPanel(
        tester,
        const DetailPanel(children: <Widget>[Text('body')]),
      );

      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(DetailPanel),
          matching: find.byType(DecoratedBox),
        ),
      );
      final BoxDecoration decoration = box.decoration as BoxDecoration;

      expect(decoration.color, Palette.card);
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(16)),
      );
      expect(
        decoration.border,
        const Border.fromBorderSide(BorderSide(color: Palette.line)),
      );

      // `padding:14px` (`index.html:105`) — asserted through the geometry rather
      // than the widget, so a padding moved elsewhere in the tree still counts.
      final Rect panelRect = tester.getRect(find.byType(DetailPanel));
      final Rect bodyRect = tester.getRect(find.text('body'));
      expect(bodyRect.left - panelRect.left, 14);
      expect(panelRect.right - bodyRect.right, 14);
    },
  );

  testWidgets('shows the heading in caps but speaks it in natural case', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpPanel(
      tester,
      const DetailPanel(
        heading: 'How big is it? — car-sized',
        children: <Widget>[Text('body')],
      ),
    );

    // `text-transform:uppercase` (`index.html:106`) is a *paint* — the string a
    // screen reader is handed stays as written, so a child using VoiceOver
    // hears a sentence rather than spelled-out letters.
    expect(find.text('HOW BIG IS IT? — CAR-SIZED'), findsOneWidget);
    expect(find.bySemanticsLabel('How big is it? — car-sized'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a panel given no heading renders none at all', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      const DetailPanel(children: <Widget>[Text('body')]),
    );

    // One Text in the panel, and it is the body: no empty header, and no 10px
    // gap where a header would have been.
    expect(
      find.descendant(
        of: find.byType(DetailPanel),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );

    final Rect panelRect = tester.getRect(find.byType(DetailPanel));
    final Rect bodyRect = tester.getRect(find.text('body'));
    expect(bodyRect.top - panelRect.top, 14);
  });

  testWidgets('the heading sits 10px above the body (`.panel h4`)', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      const DetailPanel(heading: 'Heading', children: <Widget>[Text('body')]),
    );

    final Rect headingRect = tester.getRect(find.text('HEADING'));
    final Rect bodyRect = tester.getRect(find.text('body'));
    expect(bodyRect.top - headingRect.bottom, 10);
  });

  testWidgets('the contents stretch to the panel width', (
    WidgetTester tester,
  ) async {
    // The size panel's centred `.cmp` row depends on this: it is laid out
    // against the full content width, so a nested column (or a `child:` API
    // that introduced one) would shrink-wrap it and re-centre the shapes
    // against the wrong box.
    await pumpPanel(
      tester,
      const DetailPanel(
        heading: 'Heading',
        children: <Widget>[Text('x', textAlign: TextAlign.center)],
      ),
    );

    final Rect panelRect = tester.getRect(find.byType(DetailPanel));
    final Rect bodyRect = tester.getRect(find.text('x'));
    expect(bodyRect.width, panelRect.width - 28);
  });
}
