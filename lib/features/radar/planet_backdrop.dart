import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:rockimals/features/radar/planet_painters.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';

/// How one of the backdrop's bodies is drawn — `PLANETS`' `draw` column
/// (`index.html:790-795`).
///
/// This is the whole reason every painter in `planet_painters.dart` keeps the
/// prototype's own `(c, x, y, r)` shape: the table names a function per row, so
/// the row ports across as a plain reference rather than as a `switch` on a
/// species enum that the prototype does not have.
///
/// **[showLabels] is the one addition the prototype makes implicitly.** Its
/// painters read `Radar.showLabels` off a global (`index.html:755`); a port with
/// no globals passes it, so the Labels chip can switch a planet's name off the
/// same way it does the animals'. It is a named argument so the row still ports
/// as a plain reference and the flag reads for what it is at every call site.
typedef PlanetPainter =
    void Function(
      Canvas canvas,
      Offset at,
      double radius, {
      required bool showLabels,
    });

/// One body in the decorative backdrop: one row of `PLANETS`
/// (`index.html:789-796`), plus the `x` the prototype hangs on that row at
/// runtime (`index.html:646`, `734`).
class Planet {
  Planet._({
    required this.name,
    required this.xf,
    required this.yf,
    required this.r,
    required this.drift,
    required this.bob,
    required this.draw,
  });

  /// **The prototype never reads this, and it is ported anyway.** Each painter
  /// hard-codes its own caption (`index.html:760-787`), so the table's `name`
  /// column is not the label's source and must not become one — Mercury has no
  /// label at all and Saturn's hangs at `r * 1.1` to clear its rings. What it is
  /// is the row's identity: the thing that lets a reader see which line of the
  /// table Jupiter is, and a test say so rather than trusting `planets[3]`.
  ///
  /// This is not the dead state plan decision 1 forbids. That is about values
  /// written by a live system and read by nothing, which make the system look
  /// like it does something it does not. A name column on a static table is a
  /// fact about the row that happens to also be true.
  final String name;

  /// Where the body starts across the field and sits down it, as fractions of
  /// the field's width and height (`index.html:790-795`).
  ///
  /// [xf] is a *starting* place only — [PlanetBackdrop.advance] takes [x] over
  /// from it on the first frame and it is never consulted again. [yf] is
  /// permanent: nothing in the backdrop ever moves vertically except the bob.
  final double xf;
  final double yf;

  /// The body's radius at rest, in pixels — before [PlanetBackdrop.radiusOf]
  /// puts the zoom through it.
  final double r;

  /// How fast it slides left, in the prototype's own units — multiply by
  /// [PlanetBackdrop._driftScale] for pixels per second.
  ///
  /// **The order is the sky's, backwards.** Mercury is the fastest (3.0) and
  /// Neptune the slowest (1.7), which is parallax: the near things sweep past
  /// and the far ones barely move, so a flat backdrop reads as having depth.
  /// It is not orbital speed — nothing here is to scale — but it is the same
  /// ordering, which is why it looks right.
  final double drift;

  /// The period of the vertical bob, in milliseconds — `Math.sin(ts / p.bob)`
  /// (`index.html:810`).
  ///
  /// **Six different periods, none of them a multiple of another** (2600, 3000,
  /// 3400, 4200, 4600, 5200), which is the whole point: shared periods would
  /// have the backdrop breathing in unison like one object, and these six drift
  /// in and out of phase for hours without ever repeating.
  final double bob;

  /// This body's painter, from `planet_painters.dart`.
  final PlanetPainter draw;

  /// Where the body is across the field right now, in pixels, before zoom —
  /// `p.x` (`index.html:646`, `734`, `809`).
  ///
  /// **Null until the field has a width**, which is the prototype's own state:
  /// it places the planets in `homeInit()` *and* guards `if (p.x == null) p.x =
  /// Radar.W * p.xf` at the top of every frame's drift (`index.html:734`),
  /// because a backdrop that wraps at the field's edge cannot be placed before
  /// there is an edge. [PlanetBackdrop.advance] is that guard.
  ///
  /// It is deliberately *not* zoomed and deliberately *not* rotated. The
  /// backdrop is what the field is happening in front of, so a child spinning
  /// the sky spins the animals and the Moon past a Jupiter that stays where it
  /// is — which is what makes the rotation read as the *field* turning rather
  /// than the whole universe lurching.
  double? x;
}

/// The decorative backdrop: where its six planets and the Sun are, and what
/// moves them — `PLANETS`, `SUN`, `drawPlanets` (`index.html:789-814`) and the
/// drift line of `radarLoop` (`index.html:734`).
///
/// **Mutable and integrated rather than a pure function of elapsed time, which
/// is [RadarOrbits]' argument applied again.** `x = start - drift * t` would be
/// equivalent today and wrong the moment the play/pause item lands, since a
/// stopped sky holds the planets still without moving them back — and it is
/// already wrong for the wrap, which throws the overshoot away every time it
/// fires and so cannot be recovered from a clock. The bob is the exception and
/// is not integrated: see [positionOf].
///
/// **Nothing here is data.** The planets are not where they really are, not to
/// scale, and not in the asteroids' plane; they exist so the radar reads as
/// somewhere rather than as a chart (`specs/02-live-radar.md:29`). Every real
/// number on this screen is Earth, the Moon, the rings, and the animals.
class PlanetBackdrop {
  /// The six planets, in the prototype's own table order
  /// (`index.html:789-796`) — which is also the order they are painted in, so
  /// it decides who is in front of whom where they overlap.
  PlanetBackdrop.seed()
    : planets = <Planet>[
        Planet._(name: 'Mercury', xf: 0.86, yf: 0.50, r: 6, drift: 3.0, bob: 2600, draw: paintMercury),
        Planet._(name: 'Venus', xf: 0.14, yf: 0.60, r: 10, drift: 2.4, bob: 3000, draw: paintVenus),
        Planet._(name: 'Mars', xf: 0.56, yf: 0.53, r: 9, drift: 2.0, bob: 3400, draw: paintMars),
        Planet._(name: 'Jupiter', xf: 0.80, yf: 0.73, r: 21, drift: 2.6, bob: 4200, draw: paintJupiter),
        Planet._(name: 'Saturn', xf: 0.27, yf: 0.81, r: 16, drift: 2.2, bob: 4600, draw: paintSaturn),
        Planet._(name: 'Neptune', xf: 0.94, yf: 0.65, r: 12, drift: 1.7, bob: 5200, draw: paintNeptune),
      ];

  final List<Planet> planets;

  /// Slides every planet left by [dt] seconds' worth of its own drift, wrapping
  /// it round the field (`index.html:734`).
  ///
  /// **[dt] is the frame's step and not this class's to derive**, exactly as it
  /// is not [RadarOrbits]'. The prototype takes it once at the top of
  /// `radarLoop` (`index.html:730`) and spends the same number on the animals,
  /// the Moon, and the planets; passing it in is what keeps that one number one
  /// number, and it is what carries [FrameClock]'s clamp — the thing that stops
  /// a backgrounded app flinging the whole backdrop across the field on the
  /// frame it comes back.
  ///
  /// **[width] is the field's, and it is why this cannot be folded into
  /// [positionOf].** The wrap is the only place in the backdrop that needs to
  /// know where the edge is, and it makes [x] a genuine accumulator: the reset
  /// throws the overshoot away, so where a planet is depends on every frame
  /// since it was placed and not on how long it has been drifting.
  void advance(double dt, {required double width}) {
    for (final Planet planet in planets) {
      // `if (p.x == null) p.x = Radar.W * p.xf` — the placement, done on the
      // first frame that knows the field's width rather than at construction,
      // where there is no field yet.
      double x = (planet.x ?? width * planet.xf) - planet.drift * dt * _driftScale;
      // Only leftward, because every `drift` is positive: a planet that walks
      // off the left edge is put back on beyond the right one. It reappears at
      // `width + 70` rather than at `width` so it slides *in* rather than
      // popping into existence at the rim.
      if (x < -_offField) x = width + _offField;
      planet.x = x;
    }
  }

  /// Where a planet is on the frame at [ts], in pixels (`index.html:808-811`).
  ///
  /// Two things happen on top of the drifted [Planet.x], and they are different
  /// in kind:
  ///
  /// **The zoom scales the position out from Earth's centre**, so the backdrop
  /// pulls apart with the field instead of sitting behind it like a printed
  /// sheet. It is the same `cx + (px - cx) * zoom` the rings and the animals
  /// get, which is what makes the whole screen feel like one space being zoomed
  /// rather than two layers sliding over each other.
  ///
  /// **The bob is added after the zoom and is not scaled by it** — five pixels,
  /// always, however far in a child has pinched. That is [RadarOrbit.rOff]'s
  /// argument in a decorative key: it is a drawing nudge and not a distance, so
  /// scaling it would turn a gentle sway at rest into a 10px lurch at the 6.5
  /// ceiling.
  ///
  /// **The bob reads [ts] directly rather than being integrated**, which is the
  /// one place this class is not an accumulator, and it is the prototype's own
  /// shape: `Math.sin(ts / p.bob)` sits in `drawPlanets` and not in the
  /// `if (Radar.playing)` block that the drift is inside (`index.html:731-734`).
  /// So a paused sky keeps breathing while nothing travels — which is the right
  /// answer and worth carrying to the play/pause item: "paused" on this screen
  /// means the sky has stopped *going* anywhere, not that the app has frozen.
  Offset positionOf(
    Planet planet, {
    required RadarGeometry geometry,
    required double zoom,
    required double ts,
  }) => _place(
    // `p.x != null ? p.x : W * p.xf` (`index.html:809`) — the prototype guards
    // it here as well as in the loop, so a frame drawn before the first drift
    // still has every planet somewhere sensible.
    px: planet.x ?? geometry.size.width * planet.xf,
    yf: planet.yf,
    bob: planet.bob,
    amplitude: _planetBobAmplitude,
    geometry: geometry,
    zoom: zoom,
    ts: ts,
  );

  /// How big a planet is drawn (`index.html:811`).
  double radiusOf(Planet planet, {required double zoom}) =>
      planet.r * _zoomScale(zoom);

  /// Where the Sun is (`index.html:801`).
  ///
  /// **It does not drift, and it is the only body that does not.** It is pinned
  /// at 4% across the field, which puts most of a 44px disc off the left edge —
  /// it is bleeding into frame rather than crossing it. That is what makes it
  /// read as the thing everything else is lit *by*, and it is why every sphere
  /// on this screen, Earth included, is lit from the upper left: the light has
  /// a source, and it is on the screen.
  Offset sunPosition({
    required RadarGeometry geometry,
    required double zoom,
    required double ts,
  }) => _place(
    px: geometry.size.width * _sunXf,
    yf: _sunYf,
    bob: _sunBob,
    amplitude: _sunBobAmplitude,
    geometry: geometry,
    zoom: zoom,
    ts: ts,
  );

  /// `SUN.r * (0.8 + 0.2 * zoom)` (`index.html:801`).
  double sunRadius({required double zoom}) => _sunRadius * _zoomScale(zoom);

  /// Zoom from Earth's centre, then bob — the two lines every body in the
  /// backdrop shares (`index.html:801`, `810`), given one home so the Sun and
  /// the planets cannot come apart about what a zoom means.
  static Offset _place({
    required double px,
    required double yf,
    required double bob,
    required double amplitude,
    required RadarGeometry geometry,
    required double zoom,
    required double ts,
  }) {
    final Offset centre = geometry.center;
    return Offset(
      centre.dx + (px - centre.dx) * zoom,
      centre.dy +
          (geometry.size.height * yf - centre.dy) * zoom +
          math.sin(ts / bob) * amplitude,
    );
  }

  /// `0.8 + 0.2 * zoom` (`index.html:801`, `811`) — **not `zoom`**, and the
  /// difference is the depth.
  ///
  /// A body's *position* scales with the full zoom while its *size* scales with
  /// a fifth of it, so pinching in spreads the backdrop apart without inflating
  /// Jupiter into the field. That is exactly what distance does to a real view:
  /// parallax is strong and angular size is not. At the 0.35 floor a planet is
  /// still 87% of its size and at the 6.5 ceiling only 2.1×, so the backdrop
  /// stays scenery across the whole range instead of vanishing at one end and
  /// swallowing the radar at the other.
  static double _zoomScale(double zoom) => 0.8 + 0.2 * zoom;

  /// `p.drift * Radar.speed * dt * 12` (`index.html:734`), with `speed` the
  /// constant 1 (plan decision 1 — the slider it came from has no DOM element).
  ///
  /// So the drift column is in twelfths of a pixel per second, and the range it
  /// spans is 20.4 px/s (Neptune) to 36 px/s (Mercury): Mercury crosses a 390px
  /// field in about fifteen seconds, Neptune in twenty-six. Slow enough that
  /// nothing pulls the eye off the animals, fast enough that a child who looks
  /// up after a game can tell the sky is live.
  static const double _driftScale = 12;

  /// The margin outside the field a planet leaves at and returns from
  /// (`index.html:734`).
  ///
  /// **One number, used twice** — `x < -70` and `x = W + 70`. Ported as a single
  /// constant because the two really are the same fact: it is how far past the
  /// rim a body must be for none of it to show, and 70 clears the 44px Sun and
  /// the 21px Jupiter with room to spare. Split into two constants they could
  /// drift apart, and a planet would pop out of nothing or leave a gap.
  static const double _offField = 70;

  /// `Math.sin(ts / p.bob) * 5` (`index.html:810`) — five pixels of sway, up
  /// and down, for every planet.
  static const double _planetBobAmplitude = 5;

  /// `SUN` (`index.html:797`) and its own bob (`index.html:801`).
  ///
  /// **The Sun's bob is its own datum and is gentler than the planets'** — a
  /// 4200ms period and four pixels against their five. It is the biggest thing
  /// on the screen by a factor of two, and the same five pixels on a 44px disc
  /// would read as a wobble rather than as a drift.
  static const double _sunXf = 0.04;
  static const double _sunYf = 0.30;
  static const double _sunRadius = 44;
  static const double _sunBob = 4200;
  static const double _sunBobAmplitude = 4;
}
