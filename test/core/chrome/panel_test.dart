import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The shared `.panel` card surface (`index.html:105`).
///
/// This file exists because the surface now has two unrelated callers — the
/// three detail panels through `DetailPanel`, and the About block at the foot of
/// Settings — so a change to the radius or the padding lands on a screen whose
/// own suite nobody was looking at. `detail_panel_test.dart` still asserts the
/// surface from the detail side; what is pinned *here* is the widget itself, and
/// the two properties that are only true of the shared version: that it imposes
/// no layout of its own, and that it can be built in a `const` context.
void main() {
  Future<void> pumpPanel(WidgetTester tester, Widget panel) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: panel)),
      ),
    );
  }

  testWidgets('wears the `.panel` surface — card fill, 16px radius, border', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester, const Panel(child: Text('body')));

    final DecoratedBox box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(Panel),
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
  });

  testWidgets('is exactly the surface other callers read', (
    WidgetTester tester,
  ) async {
    // The assertions above pin the three values; this one ties them to the
    // *name* the other caller imports. `games_hub.dart`'s plain `.gcard` cannot
    // be a [Panel] — it is tappable, so it paints through [Ink] — so it reads
    // [kPanelSurface] directly, and `games_hub_test.dart` asserts the card
    // equals that token. This test is the other half of that pair: without it,
    // both files could agree on a token that no longer matches what the panel
    // actually renders.
    //
    // **Deliberately `equals` and not `same`, which does not mean what it looks
    // like it means here.** Dart canonicalises `const` objects, so two
    // identical `const BoxDecoration` literals in different files *are* the
    // same instance — a re-typed copy would pass an identity check. Identity
    // cannot detect duplication in this language; only drift is detectable, and
    // equality is what detects it.
    await pumpPanel(tester, const Panel(child: Text('body')));

    final DecoratedBox box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(Panel),
        matching: find.byType(DecoratedBox),
      ),
    );

    expect(box.decoration, kPanelSurface);
  });

  testWidgets('pads its child by 14px on all four sides', (
    WidgetTester tester,
  ) async {
    // Asserted through the geometry rather than the widget, so a padding moved
    // elsewhere in the tree still counts — and so all four edges are checked
    // rather than the single `EdgeInsets.all` that produced them.
    await pumpPanel(tester, const Panel(child: Text('body')));

    final Rect panelRect = tester.getRect(find.byType(Panel));
    final Rect bodyRect = tester.getRect(find.text('body'));

    expect(bodyRect.left - panelRect.left, 14);
    expect(panelRect.right - bodyRect.right, 14);
    expect(bodyRect.top - panelRect.top, 14);
    expect(panelRect.bottom - bodyRect.bottom, 14);
  });

  testWidgets('imposes no column, no stretch, no alignment of its own', (
    WidgetTester tester,
  ) async {
    // The reason the surface is separate from `DetailPanel` at all. The detail
    // panels want a stretch [Column]; `about_block.dart` builds its own
    // start-aligned one. If [Panel] inserted either, one of its two callers
    // would be fighting it — and the About block's leading emoji column would
    // silently re-align.
    await pumpPanel(
      tester,
      const Panel(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[Text('x')],
        ),
      ),
    );

    expect(
      find.descendant(of: find.byType(Panel), matching: find.byType(Column)),
      findsNothing,
    );

    // A shrink-wrapping child still shrink-wraps: the panel is exactly the
    // child plus its padding, not the full width a stretch column would take.
    final Rect panelRect = tester.getRect(find.byType(Panel));
    final Rect bodyRect = tester.getRect(find.text('x'));
    expect(panelRect.width, bodyRect.width + 28);
    expect(
      panelRect.width,
      lessThan(tester.getRect(find.byType(Scaffold)).width),
    );
  });

  test('is const-constructible', () {
    // Not a runtime assertion so much as a compile-time one: this line does not
    // compile if [Panel]'s constructor stops being const. `about_block.dart` is
    // deliberately const the whole way down — every line on it is a
    // compile-time string — and that property would be lost silently, with no
    // failing test and no analyzer complaint, the moment this widget grew a
    // non-const field.
    const Widget panel = Panel(child: SizedBox());
    expect(panel, isA<Panel>());
  });
}
