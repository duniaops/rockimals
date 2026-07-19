import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The shared `.btn` (`index.html:51-56`).
///
/// Two screens wear this — the animal detail's Follow / Show on radar row and
/// the four games' Play again / Back to games / Reveal stacks — and both of
/// their suites already tap it by semantics label and assert what the tap did.
/// What this file pins is what only the shared widget can now get wrong, and
/// what neither caller would notice: the prototype's exact fill (the
/// `accent2`→`accent` gradient, the 14px radius, the `.32` accent halo), the
/// ghost variant that must drop all three, the 48dp tap floor, and the
/// transparency [Material] the [Scaffold]-less callers depend on.
///
/// **The ghost half is the one worth having.** Both callers pass `ghost: true`
/// for their secondary action, but a ghost that quietly kept the filled
/// gradient would still be tappable, still be labelled, and still pass every
/// route test in the app — the difference is only in pixels, and pixels are what
/// this app cannot check on a device yet (the HUMAN-GATED toolchain item).
void main() {
  /// Pumps the button bare — no [Scaffold], no [MaterialApp] chrome — because
  /// that is what the games' end screen and the detail body both give it.
  Future<void> pumpButton(
    WidgetTester tester, {
    String label = '⭐ Follow',
    String? semanticLabel,
    bool ghost = false,
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // The stretch [Column] both callers put it in — the button is
        // full-width by its caller's layout, not by its own.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ActionButton(
              label: label,
              semanticLabel: semanticLabel,
              ghost: ghost,
              onTap: onTap ?? () {},
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    final DecoratedBox box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(ActionButton),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return box.decoration as BoxDecoration;
  }

  testWidgets('fills with the accent2 → accent vertical gradient', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester);

    // `background:linear-gradient(180deg,var(--accent2),var(--accent))`
    // (`index.html:52`) — 180deg is top-to-bottom, and the order matters: the
    // lighter `accent2` is the top stop.
    expect(
      decorationOf(tester).gradient,
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Palette.accent2, Palette.accent],
      ),
    );
    expect(
      decorationOf(tester).borderRadius,
      const BorderRadius.all(Radius.circular(14)),
    );
  });

  testWidgets('carries the `.btn` halo — accent at .32, 8 down, 22 blurred', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester);

    // `box-shadow:0 8px 22px rgba(232,87,31,.32)` (`index.html:52`).
    final List<BoxShadow> shadows = decorationOf(tester).boxShadow!;
    expect(shadows, hasLength(1));
    expect(shadows.single.color, Palette.accent.withValues(alpha: 0.32));
    expect(shadows.single.offset, const Offset(0, 8));
    expect(shadows.single.blurRadius, 22);
  });

  testWidgets('the ghost drops the fill and the halo for a line border', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester, ghost: true);

    // `.btn.ghost{background:transparent;border:1px solid var(--line);
    // box-shadow:none}` (`index.html:56`). All three, because a ghost that kept
    // any one of them reads as a second primary action beside the real one.
    final BoxDecoration decoration = decorationOf(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.color, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, Border.all(color: Palette.line));
    // The radius is the one thing both variants share.
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(14)),
    );
  });

  testWidgets('sets the label in 15px/800 on dark ink over the fill', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester);

    // `.btn{color:#1a0d05;font-weight:800;font-size:15px;letter-spacing:.3px}`
    // (`index.html:51`). [Palette.onAccent] is that `#1a0d05` — near-black on
    // orange, not white, which is what keeps the contrast on the filled button.
    final Text text = tester.widget<Text>(find.text('⭐ Follow'));
    expect(text.style?.color, Palette.onAccent);
    expect(text.style?.fontSize, 15);
    expect(text.style?.fontWeight, FontWeight.w800);
    expect(text.style?.letterSpacing, 0.3);
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('the ghost writes in ink instead', (WidgetTester tester) async {
    await pumpButton(tester, ghost: true);

    // `.btn.ghost{color:var(--ink)}` (`index.html:56`) — the dark-on-orange
    // colour above would be invisible on the ghost's transparent fill.
    expect(
      tester.widget<Text>(find.text('⭐ Follow')).style?.color,
      Palette.ink,
    );
  });

  testWidgets('grows itself to the 48dp floor rather than staying 43', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester);

    // 14px padding twice around a 15px line is 43 — 5 short. Unlike the `‹ Back`
    // pill, whose painted shape must stay small, this button's fill *is* the
    // shape a child aims at, so the [TapTarget] grows the button itself and the
    // whole visible bar is tappable.
    final Rect painted = tester.getRect(find.byType(ActionButton));
    expect(painted.height, greaterThanOrEqualTo(kMinTapTarget));
  });

  testWidgets('speaks as one button, and as the label by default', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpButton(tester, label: 'Play again');

    // Every button the games raise is plain text, so [semanticLabel] is null
    // there and the visible label is what is spoken.
    expect(find.bySemanticsLabel('Play again'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a decorative glyph is spoken as its semanticLabel, not read', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    // `pumpButton`'s default label is the glyph-led '⭐ Follow'.
    await pumpButton(tester, semanticLabel: 'Follow');

    // The detail screen's two buttons lead with an emoji. The visible text is
    // [ExcludeSemantics]'d so a screen reader is handed one node saying
    // "Follow" rather than that plus a star it cannot usefully describe.
    expect(find.bySemanticsLabel('Follow'), findsOneWidget);
    expect(find.bySemanticsLabel('⭐ Follow'), findsNothing);
    handle.dispose();
  });

  testWidgets('carries its own Material, so a Scaffold-less caller still inks', (
    WidgetTester tester,
  ) async {
    // Both callers are bare [Column]s under no [Scaffold]. An [InkWell] with no
    // [Material] ancestor throws on tap, so the button supplies a transparent
    // one of its own.
    await pumpButton(tester);

    final Material material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ActionButton),
        matching: find.byType(Material),
      ),
    );
    // Transparent, not [MaterialType.canvas] — a canvas Material fills itself
    // with the theme's background, which would paint an opaque slab straight
    // over the gradient this button exists to show.
    expect(material.type, MaterialType.transparency);
  });

  testWidgets('a tap on the bar runs the callback', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await pumpButton(tester, onTap: () => taps++);

    await tester.tap(find.byType(ActionButton));
    await tester.pump();

    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
