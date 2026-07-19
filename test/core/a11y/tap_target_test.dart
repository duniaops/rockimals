import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';

/// [TapTarget] — the one widget the app-wide 48dp floor is built out of.
///
/// Worth its own suite rather than leaning on the audit that uses it, because
/// the audit only ever asks "is this box ≥48". Every bug this widget can have is
/// invisible to that question: it can make the box *too big*, it can stretch the
/// picture it was supposed to leave alone, or it can grow the layout without
/// growing what actually responds to a touch. One of those three shipped during
/// the accessibility item and is pinned below.
void main() {
  testWidgets('raises a short child to the minimum', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(width: 100, height: 20)));

    expect(tester.getSize(find.byType(TapTarget)).height, kMinTapTarget);
  });

  testWidgets('leaves a child that already clears the bar alone', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SizedBox(width: 100, height: 70)));

    expect(tester.getSize(find.byType(TapTarget)).height, 70);
  });

  testWidgets('does not resize the child it wraps', (tester) async {
    // The whole point: the painted thing keeps the prototype's dimensions and
    // only the region around it grows. A [TapTarget] that stretched its child
    // would meet the guideline by redrawing the design.
    await tester.pumpWidget(_wrap(const SizedBox(width: 100, height: 20)));

    expect(tester.getSize(find.byType(SizedBox).first), const Size(100, 20));
  });

  group('width', () {
    testWidgets('hugs the child by default, however wide the parent is', (
      tester,
    ) async {
      // A [TapTarget] in a `Row` beside other things must not eat the row.
      await tester.pumpWidget(_wrap(const SizedBox(width: 100, height: 20)));

      expect(tester.getSize(find.byType(TapTarget)).width, 100);
    });

    testWidgets('with expandWidth, reaches the minimum but goes no further', (
      tester,
    ) async {
      // **The regression this file exists for.** The first draft expressed
      // "grow when asked to" as `widthFactor: expandWidth ? null : 1` — and a
      // null factor makes [Center] *fill* its parent rather than hug its child.
      // The radar's 38dp zoom buttons became 790dp wide: a full-width invisible
      // band down the middle of the sky that swallowed every drag aimed at the
      // field behind it, which is how it was found. The fix is that both factors
      // stay 1 and [ConstrainedBox]'s `minWidth` raises the floor, so the
      // assertion that matters is the *upper* bound, not the lower one.
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 38, height: 38), expandWidth: true),
      );

      final Size size = tester.getSize(find.byType(TapTarget));
      expect(size.width, kMinTapTarget);
      expect(size.height, kMinTapTarget);
    });

    testWidgets('with expandWidth, still hugs a child wider than the minimum', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 300, height: 20), expandWidth: true),
      );

      expect(tester.getSize(find.byType(TapTarget)).width, 300);
    });
  });

  testWidgets('the grown region really does respond to a tap', (tester) async {
    // Layout and hit testing are different questions, and this is the one the
    // guideline is actually about: a box that measures 48 but only answers
    // within its inner 20 has changed nothing for the finger that missed.
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InkWell(
              onTap: () => taps++,
              child: const TapTarget(child: SizedBox(width: 100, height: 20)),
            ),
          ),
        ),
      ),
    );

    // 22dp above centre is outside the 20dp painted child and inside the 48dp
    // target — the exact band this widget adds.
    final Offset centre = tester.getCenter(find.byType(TapTarget));
    await tester.tapAt(centre + const Offset(0, 22));
    await tester.pump();

    expect(taps, 1);
  });
}

Widget _wrap(Widget child, {bool expandWidth = false}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: TapTarget(expandWidth: expandWidth, child: child),
    ),
  ),
);
