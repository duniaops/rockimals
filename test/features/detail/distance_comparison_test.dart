import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/distance_comparison.dart';

/// The detail screen's distance-comparison track (`DistanceTrack` / the "How
/// close does it pass?" panel, `index.html:564-566, 590-602`).
///
/// The `DistanceTrack` group pins the one property the prototype's `span`/`min`
/// arithmetic exists to guarantee — the asteroid dot **never leaves the track** —
/// at the maths level, for a hair-close pebble and a distant rock. The widget
/// group then mounts the panel and proves the same thing on-screen: the asteroid
/// marker's centre stays between the track's own left and right edges, whichever
/// end of the distance range it sits at.
void main() {
  group('DistanceTrack — positions stay on the track (index.html:565-566)', () {
    test(
      'a hair-close 0.07-LD flyby lands just inside Earth, not pinned to it',
      () {
        // span = max(1.25, 0.07) = 1.25 — the floor keeps the pebble off the left
        // edge. moon = 1/1.25 = 0.8; ast = 0.07/1.25 = 0.056.
        final DistanceTrack t = DistanceTrack.forMissLunar(0.07);
        expect(t.moonFraction, closeTo(0.8, 1e-9));
        expect(t.asteroidFraction, closeTo(0.056, 1e-9));
        expect(t.asteroidFraction, inInclusiveRange(0, 1));
      },
    );

    test(
      'a distant 50-LD rock is clamped to the far end, not off the right',
      () {
        // span = 50; ast = min(1, 50/50) = 1.0 exactly; moon = 1/50 = 0.02.
        final DistanceTrack t = DistanceTrack.forMissLunar(50);
        expect(t.asteroidFraction, 1.0);
        expect(t.moonFraction, closeTo(0.02, 1e-9));
        expect(t.asteroidFraction, inInclusiveRange(0, 1));
      },
    );

    test('at exactly 1 LD the asteroid sits on the Moon (both at 0.8)', () {
      // span = max(1.25, 1) = 1.25, so moon and ast both = 1/1.25 = 0.8: the rock
      // is passing at the Moon's own distance, so the dots coincide.
      final DistanceTrack t = DistanceTrack.forMissLunar(1);
      expect(t.moonFraction, closeTo(0.8, 1e-9));
      expect(t.asteroidFraction, closeTo(0.8, 1e-9));
    });

    test('Earth is always pinned at the left edge', () {
      expect(DistanceTrack.earthFraction, 0);
    });
  });

  group('DistanceComparison panel', () {
    // 2020 SW — 0.07 Moons, a hair-close flyby: the asteroid dot lands near the
    // left, well inside the track.
    final Asteroid near = kFallbackAsteroids.firstWhere(
      (Asteroid a) => a.name == '2020 SW',
    );

    // 433 Eros — 52 Moons, the farthest of the sample sky: the dot clamps to the
    // track's right edge.
    final Asteroid far = kFallbackAsteroids.firstWhere(
      (Asteroid a) => a.name == '433 Eros',
    );

    Future<void> pump(WidgetTester tester, Asteroid rock) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: DistanceComparison(asteroid: rock),
              ),
            ),
          ),
        ),
      );
    }

    /// The asteroid marker's centre must sit within the track's own horizontal
    /// span — the on-screen form of the Done-when "renders on-track". A 0.5px
    /// slack absorbs the marker-size rounding, nothing more.
    void expectAsteroidOnTrack(WidgetTester tester) {
      final Rect track = tester.getRect(
        find.byKey(const ValueKey<String>('dist-track')),
      );
      final Rect ast = tester.getRect(
        find.byKey(const ValueKey<String>('dist-asteroid')),
      );
      expect(ast.center.dx, greaterThanOrEqualTo(track.left - 0.5));
      expect(ast.center.dx, lessThanOrEqualTo(track.right + 0.5));
    }

    testWidgets('a hair-close flyby renders on-track with its distance tick', (
      tester,
    ) async {
      await pump(tester, near);

      // The header reads through the AnimalSystem's `moonCompare`, shown uppercase
      // (`text-transform`) exactly as the size panel's header is.
      expect(
        find.text(
          'How close does it pass? — ${moonCompare(near.missLunar)}'
              .toUpperCase(),
        ),
        findsOneWidget,
      );

      // The three ticks: Earth, the Moon, and the ☄️ label reading the same
      // Moon-relative distance the "How close" stat tile shows (7% to Moon).
      expect(find.text('Earth'), findsOneWidget);
      expect(find.text('🌙 Moon'), findsOneWidget);
      expect(find.text('☄️ ${distLabel(near.missLunar)}'), findsOneWidget);

      expectAsteroidOnTrack(tester);
    });

    testWidgets('a distant rock clamps to the far edge but stays on-track', (
      tester,
    ) async {
      await pump(tester, far);

      // 52 Moons → the ☄️ tick reads "52× Moon" and the dot clamps to the right.
      expect(find.text('☄️ ${distLabel(far.missLunar)}'), findsOneWidget);
      expect(distLabel(far.missLunar), '52× Moon');

      final Rect track = tester.getRect(
        find.byKey(const ValueKey<String>('dist-track')),
      );
      final Rect ast = tester.getRect(
        find.byKey(const ValueKey<String>('dist-asteroid')),
      );
      // asteroidFraction is exactly 1.0 here, so the dot centres on the track's
      // right edge — on-track, at the far end.
      expect(ast.center.dx, closeTo(track.right, 0.5));

      expectAsteroidOnTrack(tester);
    });

    testWidgets('a distant rock drops the Moon tick rather than garble it', (
      tester,
    ) async {
      // 52 Moons puts the Moon marker 1/52 of the way along the track — a few
      // pixels from Earth, where the two labels would render on top of each
      // other. The label is dropped (the header still gives the distance in
      // Moon terms); the grey Moon *dot* stays, as the prototype places it.
      await pump(tester, far);

      expect(find.text('Earth'), findsOneWidget);
      expect(find.text('🌙 Moon'), findsNothing);
      expect(find.byKey(const ValueKey<String>('dist-moon')), findsOneWidget);
    });

    testWidgets('the header speaks its natural-case label, not the caps', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, near);

      // Display shows caps; the reader hears the words (matching the size panel).
      expect(
        find.bySemanticsLabel(
          'How close does it pass? — ${moonCompare(near.missLunar)}',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('the decorative dots are summarised, not read as emoji', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, near);

      // One concise summary stands in for the 🌙/☄️ ticks, so a reader does not
      // hear "moon face" or "comet".
      expect(
        find.bySemanticsLabel(
          'On a track from Earth to the Moon, this asteroid passes at '
          '${distLabel(near.missLunar)}.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
