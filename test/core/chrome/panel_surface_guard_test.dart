import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'panel_surface_scan.dart';

/// The guard that keeps `.panel` from re-fragmenting, and the tests that keep
/// the guard honest.
///
/// `kPanelSurface` exists because the same four CSS values (`index.html:105`)
/// were written out four times across three features. `panel_test.dart` and
/// `games_hub_test.dart` between them pin the two callers that read the token
/// today — what neither can see is a *new* caller hand-rolling a fifth copy,
/// which is exactly how the first four happened.
///
/// `featured_gradient_test.dart` closes the same gap for its token with a
/// substring grep. That approach does not transfer here: `.panel`'s values are
/// shared, number for number, with four surfaces that are deliberately *not*
/// this one, so the check has to be scoped to a single widget. See
/// `panel_surface_scan.dart` for why that means an AST walk.
///
/// **The false-positive side is the load-bearing half of this file.** A guard
/// that fires on `.acard` would be deleted within a week, so every near-miss
/// named in `panel.dart`'s doc is pinned below as a fixture — if one of them
/// starts tripping the scan, that is a bug in the guard, not in the app.
void main() {
  group('the scan catches a real fifth copy', () {
    test('written as a DecoratedBox, the way `panel.dart` paints it', () {
      expect(
        findPanelSurfaceCopies('''
class _Rogue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: const Padding(padding: EdgeInsets.all(14), child: Text('x')),
    );
  }
}
'''),
        <Matcher>[_copyIn('_Rogue.build')],
      );
    });

    test('written as Material + Ink, the way a *tappable* copy would be', () {
      // The likeliest shape for the next copy, because it is the one shape
      // `Panel` cannot take — `Material`'s `color`/`shape` pair will not accept
      // a `BoxDecoration`, which is why `games_hub.dart` reads the token
      // instead of the widget. A scan keyed on `BoxDecoration` would miss it.
      expect(
        findPanelSurfaceCopies('''
class _RogueTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Palette.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: const Padding(padding: EdgeInsets.all(14), child: Text('x')),
      ),
    );
  }
}
'''),
        <Matcher>[_copyIn('_RogueTile.build')],
      );
    });

    test('spelled `BorderRadius.circular(16)` and `Border.all`', () {
      // Same four values, different spelling. Pinned because a guard that only
      // knows one way of writing a corner is a guard someone routes around by
      // accident.
      expect(
        findPanelSurfaceCopies('''
Widget rogueCard() {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Palette.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Palette.line),
    ),
  );
}
'''),
        <Matcher>[_copyIn('rogueCard')],
      );
    });

    test('as a field initialiser rather than a build method', () {
      expect(
        findPanelSurfaceCopies('''
const Widget rogue = Padding(
  padding: EdgeInsets.all(14),
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.card,
      borderRadius: BorderRadius.all(Radius.circular(16)),
      border: Border.fromBorderSide(BorderSide(color: Palette.line)),
    ),
  ),
);
'''),
        <Matcher>[_copyIn('rogue')],
      );
    });

    test('reported once, not once per nested closure', () {
      // The copy below is inside a `Builder` inside the build method, so both
      // declarations contain all four values. One widget, one finding — a
      // guard that double-counts reads as two problems.
      expect(
        findPanelSurfaceCopies('''
class _Rogue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.line),
          ),
        );
      },
    );
  }
}
'''),
        hasLength(1),
      );
    });
  });

  group('the scan clears every near-miss `panel.dart` names', () {
    // Each fixture is the shape of the real widget, trimmed to the four values
    // under test. The citations are `panel.dart`'s own list.

    test('`.tile` / `.stat` — radius 14, padding 12', () {
      expect(
        findPanelSurfaceCopies('''
Widget tile() => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: Palette.card,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: Palette.line),
  ),
);
'''),
        isEmpty,
      );
    });

    test('`.acard` — the same three surface values, but padding 12', () {
      // The sharpest near-miss in the app: fill, corner *and* border all match
      // `.panel` exactly (`animal_card.dart:93`), and only the padding differs.
      // It is the reason the scan needs all four values rather than the three
      // that make up `kPanelSurface` — a three-value check would call the
      // animal card a copy and be wrong.
      expect(
        findPanelSurfaceCopies('''
Widget acard() => Material(
  color: Palette.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: Palette.line),
  ),
  child: InkWell(
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    onTap: onTap,
    child: const Padding(padding: EdgeInsets.all(12), child: Text('x')),
  ),
);
'''),
        isEmpty,
      );
    });

    test('`.dcard` — border colour follows the answer', () {
      expect(
        findPanelSurfaceCopies('''
Widget dcard() => Material(
  color: Palette.card,
  shape: RoundedRectangleBorder(
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    side: BorderSide(
      color: switch (winner) {
        true => Palette.good,
        false => Palette.bad,
        null => Palette.line,
      },
    ),
  ),
  child: const Padding(padding: EdgeInsets.all(14), child: Text('x')),
);
'''),
        isEmpty,
      );
    });

    test('`.chcard` — border colour is a local that follows the answer', () {
      expect(
        findPanelSurfaceCopies('''
Widget chcard() => Material(
  color: Palette.card,
  shape: RoundedRectangleBorder(
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: borderColour),
  ),
  child: const Padding(padding: EdgeInsets.all(14), child: Text('x')),
);
'''),
        isEmpty,
      );
    });

    test("the radar's `.chip` — fill follows its toggle", () {
      // `_chipSurface` is `Palette.card.withValues(alpha: 0.85)`. A scan that
      // accepted "anything derived from `Palette.card`" would fold the chip,
      // the zoom buttons and the home strip into `.panel` — three surfaces
      // that are translucent on purpose because the radar draws underneath.
      expect(
        findPanelSurfaceCopies('''
Widget chip() => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: _chipSurface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Palette.line),
  ),
);
'''),
        isEmpty,
      );
    });

    test('two unrelated widgets in one file are not one widget', () {
      // The failure mode that killed the grep. Neither declaration has all
      // four; between them the file does. `radar_view.dart` is this fixture at
      // full size, which is why the unit had to become the declaration.
      expect(
        findPanelSurfaceCopies('''
Widget pill() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  decoration: BoxDecoration(
    color: Palette.card,
    borderRadius: const BorderRadius.all(Radius.circular(20)),
    border: Border.all(color: Palette.line),
  ),
);

Widget spacer() => const Padding(
  padding: EdgeInsets.all(14),
  child: SizedBox(),
);
'''),
        isEmpty,
      );
    });

    test('a caller that reads the tokens is not a copy', () {
      // `games_hub.dart`'s plain `.gcard`, in miniature: the whole point of the
      // token is that this shape stays legal forever.
      expect(
        findPanelSurfaceCopies('''
Widget gcard() => Ink(
  decoration: kPanelSurface,
  child: const Padding(padding: kPanelPadding, child: Text('x')),
);
'''),
        isEmpty,
      );
    });
  });

  group('`.panel` — the only copy in the app', () {
    test('no widget outside `panel.dart` restates all four values', () {
      final List<PanelSurfaceCopy> offenders = <PanelSurfaceCopy>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // The definition itself, excluded for the same reason
        // `featured_gradient_test.dart` excludes its token's file. It does not
        // trip the scan today — the four values live in three separate
        // top-level tokens, none of which holds all of them — but inlining
        // them back into `Panel.build` would be a tidy-up, not a regression.
        if (entity.path.endsWith('core/chrome/panel.dart')) continue;
        offenders.addAll(
          findPanelSurfaceCopies(entity.readAsStringSync(), path: entity.path),
        );
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these widgets write out the `.panel` surface again instead of '
            'reading kPanelSurface / kPanelPadding from core/chrome/panel.dart '
            '— the duplication that token exists to end. If one of them is a '
            'genuine near-miss rather than a copy, add it to the near-miss '
            "list in `panel.dart`'s doc *and* as a fixture above, so the next "
            'reader does not have to re-derive the distinction.',
      );
    });
  });
}

/// A single finding, named by its declaration. The line number is not asserted
/// — it moves with unrelated edits, and the declaration is what identifies the
/// widget.
Matcher _copyIn(String declaration) => isA<PanelSurfaceCopy>().having(
  (PanelSurfaceCopy c) => c.declaration,
  'declaration',
  declaration,
);
