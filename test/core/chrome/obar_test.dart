import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/chrome/obar.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The shared `.obar` back-bar (`index.html:92-94`).
///
/// Four screens wear this — the animal detail, the Play hub, [GameShell], and
/// Settings — and each of their suites already asserts that a `‹ Back` pill is
/// there and pops. What this file pins is what only the shared widget can now
/// get wrong, and what none of those four would notice: the prototype's exact
/// surface (the `line2` rule, the 36px + notch pad, the 16px/800 ellipsised
/// title), the 48dp tap floor, and the transparency [Material] the three
/// [Scaffold]-less callers depend on.
///
/// **The notch case is the one worth having.** Three of the four callers are
/// pushed routes whose tests pump at a fixed zero-inset surface, so the
/// `+ MediaQuery.padding.top` term could be deleted and every existing suite
/// would stay green while the bar rode under the notch on real hardware — which
/// is precisely the class of thing this app cannot verify on a device yet (the
/// HUMAN-GATED toolchain item).
void main() {
  /// Pumps the bar bare — no [Scaffold], no [MaterialApp] chrome — because
  /// three of the four callers give it exactly that.
  Future<void> pumpObar(
    WidgetTester tester, {
    String title = 'Rusty the Fox',
    EdgeInsets viewPadding = EdgeInsets.zero,
  }) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(padding: viewPadding),
        child: Directionality(
          textDirection: TextDirection.ltr,
          // The stretch [Column] every caller puts it in — without it the bar
          // is handed the tight full-screen constraints `pumpWidget` gives its
          // root and stops shrink-wrapping, which makes the padding
          // measurements below meaningless rather than wrong.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[Obar(title: title)],
          ),
        ),
      ),
    );
  }

  testWidgets('rules the bar off with a `line2` bottom border', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester);

    final DecoratedBox box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(Obar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final BoxDecoration decoration = box.decoration as BoxDecoration;

    expect(
      decoration.border,
      const Border(bottom: BorderSide(color: Palette.line2)),
    );
  });

  testWidgets('pads 36px above the pill and 10px below it, plus the notch', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester);

    final Rect bar = tester.getRect(find.byType(Obar));
    final Rect pill = tester.getRect(find.byType(TapTarget));

    // `.obar{padding:36px 14px 10px}` (`index.html:92`).
    expect(pill.top - bar.top, 36);
    expect(bar.bottom - pill.bottom, 10);
    expect(pill.left - bar.left, 14);
  });

  testWidgets('adds the device inset to the 36px so it clears a notch', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester, viewPadding: const EdgeInsets.only(top: 47));

    final Rect bar = tester.getRect(find.byType(Obar));
    final Rect pill = tester.getRect(find.byType(TapTarget));

    // The prototype's 36 clears a status bar it assumed; a real notch is added
    // to it rather than replacing it, so the bar never sits *under* the cutout.
    expect(pill.top - bar.top, 36 + 47);
  });

  testWidgets('sets the title in 16px/800, ellipsised on one line', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester);

    // `.otitle{font-weight:800;font-size:16px}` (`index.html:94`).
    final Text title = tester.widget<Text>(find.text('Rusty the Fox'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w800);
    expect(title.style?.color, Palette.ink);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a long title truncates instead of pushing the pill off', (
    WidgetTester tester,
  ) async {
    const String long =
        'Sparkle the Extremely Enormous Intergalactic Space Whale of Wonder';
    await pumpObar(tester, title: long);

    final Rect bar = tester.getRect(find.byType(Obar));
    final Rect titleRect = tester.getRect(find.text(long));
    final Rect pill = tester.getRect(find.byType(TapTarget));

    // The pill keeps its place and the title takes what is left, `gap:12px`
    // away from it (`index.html:92`) — the reason the title is [Expanded] and
    // not the pill.
    expect(titleRect.left - pill.right, 12);
    expect(bar.right - titleRect.right, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paints the `.back` pill in card over a line border', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester);

    // `.back` (`index.html:93`) — the pill inside the tap target, not the
    // bar's own rule, which is why this searches under [TapTarget].
    final DecoratedBox pill = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(TapTarget),
        matching: find.byType(DecoratedBox),
      ),
    );
    final BoxDecoration decoration = pill.decoration as BoxDecoration;

    expect(decoration.color, Palette.card);
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(11)),
    );
    expect(
      decoration.border,
      const Border.fromBorderSide(BorderSide(color: Palette.line)),
    );
    expect(find.text('‹ Back'), findsOneWidget);
  });

  testWidgets('keeps the painted pill small but the tap target 48dp tall', (
    WidgetTester tester,
  ) async {
    await pumpObar(tester);

    final Rect target = tester.getRect(find.byType(TapTarget));
    final Rect painted = tester.getRect(find.text('‹ Back'));

    expect(target.height, greaterThanOrEqualTo(kMinTapTarget));
    // The point of [TapTarget]: the thumb region grew, the drawing did not. A
    // pill padded out to 48 would be visibly heavier than the 16px title.
    expect(painted.height, lessThan(kMinTapTarget));
  });

  testWidgets('speaks as one button labelled Back, not as its glyph', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpObar(tester);

    // Route tests across the radar, the hub, and the games tap this by label —
    // there is no Material [BackButton] here for `tester.pageBack()` to find,
    // so the label is load-bearing. The `‹` is [ExcludeSemantics]'d so a screen
    // reader is not handed the chevron as a second, meaningless node.
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.bySemanticsLabel('‹ Back'), findsNothing);
    handle.dispose();
  });

  testWidgets('pops the route it sits on when the pill is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Obar(title: 'Pushed'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a tap on the last route is a no-op, not a crash', (
    WidgetTester tester,
  ) async {
    // [Navigator.maybePop], not `pop` — the bar is a plain widget and nothing
    // stops a future screen from mounting it as a root. `pop` would tear the
    // last route out from under the app.
    await tester.pumpWidget(const MaterialApp(home: Obar(title: 'Root')));

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('carries its own Material, so a Scaffold-less caller still inks', (
    WidgetTester tester,
  ) async {
    // Three of the four callers are bare [Column]s under no [Scaffold]. An
    // [InkWell] with no [Material] ancestor throws on tap, so the bar supplies
    // a transparent one of its own — neither `pumpObar` nor the [MaterialApp]
    // below provides a [Scaffold], so this failing means the extraction
    // dropped it.
    await pumpObar(tester);

    final Material material = tester.widget<Material>(
      find.descendant(of: find.byType(Obar), matching: find.byType(Material)),
    );
    // Transparent, not [MaterialType.canvas] — a canvas Material fills itself
    // with the theme's background, which on these three unthemed screens paints
    // an opaque slab across the bar behind the pill. Nothing else in the app
    // would fail on that, because a `Material` of *some* kind is all the ink
    // needs.
    expect(material.type, MaterialType.transparency);

    // And it really inks. A [Navigator] is needed for the pop, so this half
    // runs under a Scaffold-less [MaterialApp].
    await tester.pumpWidget(const MaterialApp(home: Obar(title: 'Root')));
    await tester.tap(find.byType(TapTarget));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
