import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';

/// Where the decorative backdrop puts its bodies, and what moves them.
///
/// **Every number below is the prototype's own output, not a reading of it.**
/// `index.html:741-814` — the six painters, `PLANETS`, `SUN` and `drawPlanets`
/// — was sliced out of the file and `eval`-ed over a recording canvas stub at a
/// 390×700 field, dumping every placement it computed and every call it made.
/// That is the technique this plan has used since the FALLBACK item, for the
/// reason it keeps earning: a table of hand-copied coordinates is exactly where
/// a careful read fails silently. A planet in the wrong place does not throw. It
/// just looks slightly wrong, forever, and nobody can say why.
///
/// `planet_painters_test.dart` owns what each body *looks* like. This file owns
/// where it is and how it moves.
void main() {
  group('PlanetBackdrop — the table', () {
    test('is the prototype\'s six, in the prototype\'s own order', () {
      // The order is not cosmetic: it is paint order (`index.html:808`), so it
      // decides who is in front of whom where two planets drift past each other.
      expect(
        PlanetBackdrop.seed().planets.map((Planet p) => p.name),
        <String>['Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Neptune'],
      );
    });

    test('gives the near planets the faster drift', () {
      // `index.html:790-795` — Mercury 3.0 down to Neptune 1.7. It is parallax,
      // not orbital speed: nothing here is to scale, but the near things sweeping
      // past the far ones is what gives a flat backdrop any depth at all. A
      // shared drift would make the six read as one sheet sliding by.
      final List<double> drifts =
          PlanetBackdrop.seed().planets.map((Planet p) => p.drift).toList();

      expect(drifts, <double>[3.0, 2.4, 2.0, 2.6, 2.2, 1.7]);
      expect(drifts.first, greaterThan(drifts.last), reason: 'Mercury outruns Neptune');
    });

    test('gives every planet a bob period of its own', () {
      // Six periods, no two alike and none a multiple of another
      // (`index.html:790-795`). Shared periods would have the whole backdrop
      // breathing in unison like one object; these drift in and out of phase for
      // hours without repeating.
      final List<double> bobs =
          PlanetBackdrop.seed().planets.map((Planet p) => p.bob).toList();

      expect(bobs, <double>[2600, 3000, 3400, 4200, 4600, 5200]);
      expect(bobs.toSet(), hasLength(6));
    });
  });

  group('PlanetBackdrop — placement', () {
    test('puts every body where the prototype puts it', () {
      // The whole capture at rest: `zoom = 1`, `ts = 0`, a 390×700 field. These
      // are `drawPlanets`' own `x`, `y` and `rr` for each of the six, dumped
      // from the prototype rather than recomputed here.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();

      for (final (String name, Offset at, double radius) expected in <(String, Offset, double)>[
        ('Mercury', const Offset(335.4, 350), 6),
        ('Venus', const Offset(54.6, 420), 10),
        ('Mars', const Offset(218.4, 371), 9),
        ('Jupiter', const Offset(312, 511), 21),
        ('Saturn', const Offset(105.3, 567), 16),
        ('Neptune', const Offset(366.6, 455), 12),
      ]) {
        final Planet planet = _named(backdrop, expected.$1);
        _expectOffset(
          backdrop.positionOf(planet, geometry: _geometry, zoom: 1, ts: 0),
          expected.$2,
          reason: expected.$1,
        );
        expect(backdrop.radiusOf(planet, zoom: 1), closeTo(expected.$3, 1e-9),
            reason: expected.$1);
      }
    });

    test('bleeds the Sun in from off the left edge', () {
      // `SUN = {xf: 0.04, yf: 0.30, r: 44}` (`index.html:797`) — 15.6px across a
      // 390px field, with a 44px radius. So more than half the disc is off
      // screen: it is not a body in the scene, it is the light the scene is lit
      // by, which is why every sphere on this screen is lit from the upper left.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();

      _expectOffset(
        backdrop.sunPosition(geometry: _geometry, zoom: 1, ts: 0),
        const Offset(15.6, 210),
      );
      expect(backdrop.sunRadius(zoom: 1), closeTo(44, 1e-9));
      expect(15.6 - 44, lessThan(0), reason: 'its left limb is off the field');
    });

    test('places from the field\'s width only once it has one', () {
      // The prototype's own laziness: `PLANETS.forEach(p => p.x = Radar.W * p.xf)`
      // at init (`index.html:646`), guarded again by `if (p.x == null)` at the
      // top of every frame's drift (`index.html:734`). A backdrop that wraps at
      // the field's edge cannot be placed before there is an edge — and the app
      // really does paint a frame before it can measure itself, because a
      // `Ticker` fires before the layout of the frame it fires in.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      expect(backdrop.planets.every((Planet p) => p.x == null), isTrue);

      // Unplaced, a frame still draws every planet somewhere sensible —
      // `p.x != null ? p.x : W * p.xf` (`index.html:809`).
      _expectOffset(
        backdrop.positionOf(_named(backdrop, 'Mercury'), geometry: _geometry, zoom: 1, ts: 0),
        const Offset(335.4, 350),
      );

      backdrop.advance(0, width: 390);
      expect(_named(backdrop, 'Mercury').x, closeTo(335.4, 1e-9));
    });

    test('does not re-place a planet that has already drifted', () {
      // The `??` is a placement, not a reset. If it fired every frame the
      // backdrop would be pinned to its start and nothing would ever move.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed()..advance(1, width: 390);
      final double afterOneSecond = _named(backdrop, 'Mercury').x!;

      backdrop.advance(1, width: 390);

      expect(_named(backdrop, 'Mercury').x, lessThan(afterOneSecond));
    });
  });

  group('PlanetBackdrop — drift', () {
    test('slides each planet left by its own drift × 12', () {
      // One second of frames, against the prototype's own dump of the same. The
      // `* 12` (`index.html:734`) is what turns the table's column into pixels
      // per second — Mercury 36, Neptune 20.4 — and `Radar.speed` is the
      // constant 1 (plan decision 1: the slider it came from has no DOM
      // element).
      final PlanetBackdrop backdrop = _driftedFor(seconds: 1);

      for (final (String name, double x) expected in <(String, double)>[
        ('Mercury', 299.4),
        ('Venus', 25.8),
        ('Mars', 194.4),
        ('Jupiter', 280.8),
        ('Saturn', 78.9),
        ('Neptune', 346.2),
      ]) {
        expect(_named(backdrop, expected.$1).x, closeTo(expected.$2, 1e-6),
            reason: expected.$1);
      }
    });

    test('leaves the Sun where it is', () {
      // It is the one body with no `drift` column, because it is not crossing
      // the field — it is the corner the light comes from. A Sun that drifted
      // off would take the scene's only light source with it and leave every
      // planet lit from a direction with nothing in it.
      final PlanetBackdrop backdrop = _driftedFor(seconds: 30);

      _expectOffset(
        backdrop.sunPosition(geometry: _geometry, zoom: 1, ts: 0),
        const Offset(15.6, 210),
      );
    });

    test('takes the step it is given rather than reading a clock', () {
      // Ten frames of 100ms and one of a second are the same second — which is
      // what lets `FrameClock`'s clamp reach the backdrop at all. A backdrop
      // that integrated its own elapsed time would fling itself across the field
      // on the frame a backgrounded app came back, which is the jolt
      // `specs/02-live-radar.md:28` exists to forbid.
      final PlanetBackdrop stepped = PlanetBackdrop.seed();
      for (int i = 0; i < 10; i++) {
        stepped.advance(0.1, width: 390);
      }
      final PlanetBackdrop leapt = PlanetBackdrop.seed()..advance(1, width: 390);

      expect(_named(stepped, 'Jupiter').x, closeTo(_named(leapt, 'Jupiter').x!, 1e-9));
    });

    test('is not touched by the zoom', () {
      // `x` is the field's own pixels; the zoom is applied at placement
      // (`index.html:809`). Folding zoom into the drift would make a pinched-in
      // sky's backdrop tear past at six times the speed, and — worse — would
      // wrap the planets at a rate that depended on how far the child had
      // pinched.
      final PlanetBackdrop backdrop = _driftedFor(seconds: 1);
      final Planet mercury = _named(backdrop, 'Mercury');

      expect(mercury.x, closeTo(299.4, 1e-6));
      // The zoom still moves where it is *drawn*, from Earth's centre out.
      _expectOffset(
        backdrop.positionOf(mercury, geometry: _geometry, zoom: 2, ts: 0),
        const Offset(195 + (299.4 - 195) * 2, 322 + (350 - 322) * 2),
      );
    });
  });

  group('PlanetBackdrop — the wrap', () {
    test('sends a planet off the left edge back round the right', () {
      // Mercury starts at 335.4 and runs at 36px/s, so it needs 405.4px to reach
      // -70 — 675.7 frames at 60fps. The prototype's own dump says it wraps on
      // frame 676, from -69.6, to 460. All three numbers are asserted, because
      // each is a different way to get this wrong.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mercury = _named(backdrop, 'Mercury');

      for (int i = 0; i < 675; i++) {
        backdrop.advance(1 / 60, width: 390);
      }
      expect(mercury.x, closeTo(-69.6, 1e-6), reason: 'still off screen, not yet wrapped');

      backdrop.advance(1 / 60, width: 390);
      expect(mercury.x, 460, reason: 'W + 70, on the far side');
    });

    test('throws the overshoot away rather than carrying it', () {
      // **This is why `x` is an accumulator and not a formula**, and it is the
      // whole argument for this class being mutable. The reset is to a flat
      // `W + 70` (`index.html:734`), discarding however far past -70 the frame
      // happened to carry the planet — so where a planet is depends on every
      // frame since it was placed, not on how long it has been drifting. A
      // `start - drift * t` wrapped with a modulo would be off by the overshoot
      // and would drift further off with every lap.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mercury = _named(backdrop, 'Mercury')..x = -69;

      // A big step: 10px past the edge in one frame.
      backdrop.advance(11 / 36, width: 390);

      expect(mercury.x, 460, reason: 'exactly W + 70 — the 10px of overshoot is gone');
    });

    test('wraps at the edge and not before it', () {
      // 70px of margin, used twice and ported as one constant: it is how far past
      // the rim a body must be for none of it to show. A planet exactly *at* -70
      // has not gone yet — `if (p.x < -70)` is strict.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mercury = _named(backdrop, 'Mercury')..x = -70 + 36 / 60;

      backdrop.advance(1 / 60, width: 390);
      expect(mercury.x, closeTo(-70, 1e-9), reason: 'at -70 exactly, still not wrapped');

      backdrop.advance(1 / 60, width: 390);
      expect(mercury.x, 460);
    });

    test('clears the widest body at both ends', () {
      // The margin has to be bigger than the biggest thing that uses it or a
      // planet pops out of nothing at one edge and vanishes at the other. The
      // widest body in the backdrop is Jupiter at 21px — and at the 6.5 zoom
      // ceiling it is drawn at 2.1×, i.e. 44.1px, still inside 70.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final double widest = backdrop.planets
          .map((Planet p) => backdrop.radiusOf(p, zoom: 6.5))
          .reduce(math.max);

      expect(widest, lessThan(70));
    });
  });

  group('PlanetBackdrop — the bob', () {
    test('sways each planet five pixels either way, on its own period', () {
      // `Math.sin(ts / p.bob) * 5` (`index.html:810`). A quarter period in, the
      // sine is at 1 and the planet is at the top of its sway.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mercury = _named(backdrop, 'Mercury');

      final double top = backdrop
          .positionOf(mercury, geometry: _geometry, zoom: 1, ts: 2600 * math.pi / 2)
          .dy;
      final double bottom = backdrop
          .positionOf(mercury, geometry: _geometry, zoom: 1, ts: 2600 * 3 * math.pi / 2)
          .dy;

      expect(top, closeTo(350 + 5, 1e-6));
      expect(bottom, closeTo(350 - 5, 1e-6));
    });

    test('sways the Sun more gently than the planets', () {
      // Four pixels on a 4200ms period, against the planets' five
      // (`index.html:801`) — its own datum, and the Sun is the one body big
      // enough for the difference to matter. The same five pixels on a 44px disc
      // would read as a wobble rather than as a drift.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();

      final double top = backdrop
          .sunPosition(geometry: _geometry, zoom: 1, ts: 4200 * math.pi / 2)
          .dy;

      expect(top, closeTo(210 + 4, 1e-6));
    });

    test('does not move the planet sideways', () {
      // The bob is a `y` term only (`index.html:810`). Drift is the horizontal
      // motion and it belongs to `advance`; a bob that touched `x` would be a
      // second, invisible drift that no wrap ever caught.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet venus = _named(backdrop, 'Venus');

      expect(
        backdrop.positionOf(venus, geometry: _geometry, zoom: 1, ts: 3000 * math.pi / 2).dx,
        closeTo(backdrop.positionOf(venus, geometry: _geometry, zoom: 1, ts: 0).dx, 1e-9),
      );
    });

    test('keeps breathing while nothing drifts', () {
      // **The one place this class is not an accumulator, and it is the
      // prototype's own shape.** `Math.sin(ts / p.bob)` lives in `drawPlanets`,
      // outside the `if (Radar.playing)` block that the drift is inside
      // (`index.html:731-734`). So a paused sky keeps swaying while nothing
      // travels — which is the right answer, and the play/pause item should keep
      // it: "paused" on this screen means the sky has stopped *going* anywhere,
      // not that the app has frozen.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mars = _named(backdrop, 'Mars');

      // No `advance` at all — the sky is stopped dead.
      final Offset still = backdrop.positionOf(mars, geometry: _geometry, zoom: 1, ts: 0);
      final Offset later =
          backdrop.positionOf(mars, geometry: _geometry, zoom: 1, ts: 3400 * math.pi / 2);

      expect(later.dy, isNot(closeTo(still.dy, 1)));
      expect(later.dx, closeTo(still.dx, 1e-9), reason: 'still not going anywhere');
    });

    test('is not scaled by the zoom', () {
      // Added after the zoom, exactly as `RadarOrbit.rOff` is
      // (`index.html:810`): it is a drawing nudge, not a distance. Scaling it
      // would turn a gentle five-pixel sway at rest into a lurch at the 6.5
      // ceiling.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet mercury = _named(backdrop, 'Mercury');

      final double restY =
          backdrop.positionOf(mercury, geometry: _geometry, zoom: 4, ts: 0).dy;
      final double topY = backdrop
          .positionOf(mercury, geometry: _geometry, zoom: 4, ts: 2600 * math.pi / 2)
          .dy;

      expect(topY - restY, closeTo(5, 1e-6), reason: 'five pixels at any zoom');
    });
  });

  group('PlanetBackdrop — the zoom', () {
    test('scales every body out from Earth\'s centre', () {
      // `cx + (px - cx) * zoom` (`index.html:801`, `810`) — the same transform
      // the rings and the animals get, which is what makes the screen read as one
      // space being zoomed rather than as two layers sliding over each other.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();

      // Captured from the prototype at `zoom = 2, ts = 1000`: Mercury at
      // 475.8, and the Sun flung right off the left edge to -163.8.
      expect(
        backdrop.positionOf(_named(backdrop, 'Mercury'), geometry: _geometry, zoom: 2, ts: 1000).dx,
        closeTo(475.8, 1e-6),
      );
      expect(
        backdrop.sunPosition(geometry: _geometry, zoom: 2, ts: 1000).dx,
        closeTo(-163.8, 1e-6),
      );
    });

    test('carries the bob through untouched at a zoom', () {
      // The rest of the `zoom = 2, ts = 1000` capture — every `y`, which is the
      // half that has the sine in it. If the port had the bob inside the zoom,
      // or read the period off the wrong column, this is where it would show.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();

      for (final (String name, double y) expected in <(String, double)>[
        ('Mercury', 379.876013240213),
        ('Venus', 519.6359734839807),
        ('Mars', 421.4494774993576),
        ('Jupiter', 701.1792601438416),
        ('Saturn', 813.0784153198875),
        ('Neptune', 588.9556227685306),
      ]) {
        expect(
          backdrop
              .positionOf(_named(backdrop, expected.$1), geometry: _geometry, zoom: 2, ts: 1000)
              .dy,
          closeTo(expected.$2, 1e-9),
          reason: expected.$1,
        );
      }

      expect(
        backdrop.sunPosition(geometry: _geometry, zoom: 2, ts: 1000).dy,
        closeTo(98.94340811507324, 1e-9),
      );
    });

    test('grows a body by a fifth of what it moves it', () {
      // `r * (0.8 + 0.2 * zoom)` (`index.html:801`, `811`) — **not** `r * zoom`,
      // and the difference is the depth. Position takes the full zoom and size
      // takes a fifth of it, so pinching in spreads the backdrop apart without
      // inflating Jupiter into the field. That is what distance does to a real
      // view: parallax is strong, angular size is not.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet jupiter = _named(backdrop, 'Jupiter');

      expect(backdrop.radiusOf(jupiter, zoom: 1), closeTo(21, 1e-9));
      expect(backdrop.radiusOf(jupiter, zoom: 2), closeTo(25.2, 1e-9));
      expect(backdrop.sunRadius(zoom: 2), closeTo(52.8, 1e-9));
    });

    test('keeps the backdrop scenery across the whole zoom range', () {
      // The clamp a child can actually reach is 0.35–6.5 (`index.html:689`). At
      // the floor a planet is still 87% of its size and at the ceiling only
      // 2.1×, so the scenery never vanishes at one end nor swallows the radar at
      // the other. A plain `r * zoom` would give 0.35× and 6.5× — a speck, then
      // a 136px Jupiter straight through the middle of the field.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      final Planet jupiter = _named(backdrop, 'Jupiter');

      expect(backdrop.radiusOf(jupiter, zoom: 0.35), closeTo(21 * 0.87, 1e-9));
      expect(backdrop.radiusOf(jupiter, zoom: 6.5), closeTo(21 * 2.1, 1e-9));
    });
  });
}

/// The field the capture was taken against: a phone-shaped radar, so every
/// coordinate here is one the prototype computed rather than one this test
/// invented. Its centre is `(195, 322)` — `cx = W/2`, `cy = H*0.46`.
const RadarGeometry _geometry = RadarGeometry(size: Size(390, 700), maxLd: 60);

Planet _named(PlanetBackdrop backdrop, String name) =>
    backdrop.planets.singleWhere((Planet p) => p.name == name);

/// A backdrop that has been drifting for [seconds], a frame at a time at 60fps —
/// the way the app really does it, rather than in one leap.
PlanetBackdrop _driftedFor({required int seconds}) {
  final PlanetBackdrop backdrop = PlanetBackdrop.seed();
  for (int i = 0; i < 60 * seconds; i++) {
    backdrop.advance(1 / 60, width: 390);
  }
  return backdrop;
}

void _expectOffset(Offset actual, Offset expected, {String? reason}) {
  expect(actual.dx, closeTo(expected.dx, 1e-6), reason: reason);
  expect(actual.dy, closeTo(expected.dy, 1e-6), reason: reason);
}
