import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_labels.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';
import 'package:rockimals/features/radar/radar_painter.dart';

import '../../support/radar_frame.dart';

/// What the radar's base layer actually puts on the screen.
///
/// Split by what each thing can honestly be checked with. The dash pattern is
/// path geometry, so it is measured. Earth is a stack of circles, so the
/// recorded draw calls are asserted. And the whole frame is rasterised and
/// probed, because everything above would pass just as happily for a canvas
/// that painted all of it off the bottom of the screen — the technique
/// `loading_screen_test.dart` established, for the same reason: there is no
/// device here to look at (no Xcode, no Android SDK — see the plan's
/// human-gated item).
void main() {
  group('dashedCircle', () {
    test('lays dashes along the circumference, not around the angle', () {
      // The distinction the port hinges on. `setLineDash([3, 5])` measures in
      // pixels of arc, so doubling the radius gives twice as many dashes of the
      // same length — not the same dashes stretched. Getting this backwards
      // looks fine on one ring and wrong across six.
      final small = dashedCircle(Offset.zero, 50, on: 3, off: 5).computeMetrics().toList();
      final big = dashedCircle(Offset.zero, 100, on: 3, off: 5).computeMetrics().toList();

      expect(small.length, closeTo(2 * math.pi * 50 / 8, 1));
      expect(big.length, closeTo(2 * math.pi * 100 / 8, 1));

      // All but the last, which the loop cuts short — its own test, below.
      for (final ui.PathMetric dash in small.take(small.length - 1)) {
        expect(dash.length, closeTo(3, 0.01));
      }
      for (final ui.PathMetric dash in big.take(big.length - 1)) {
        expect(dash.length, closeTo(3, 0.01));
      }
    });

    test('honours the gap as well as the dash', () {
      // A pattern of [2, 7] is a period of 9, not of 2.
      final dashes = dashedCircle(Offset.zero, 90, on: 2, off: 7).computeMetrics().toList();

      expect(dashes.length, closeTo(2 * math.pi * 90 / 9, 1));
      expect(dashes.first.length, closeTo(2, 0.01));
    });

    test('closes the loop exactly once, without overlapping itself', () {
      // The one deliberate deviation from `index.html:829`, whose `arc(…, 0, 7)`
      // sweeps 0.72 radians past a full turn. On a solid stroke that overshoot
      // is invisible; under a dash pattern it lays a second run of dashes over
      // the first at a different phase, brightening an arc of every ring. So
      // what is ported is the circle that `0, 7` means.
      //
      // Measured as: total dash length is the circumference's 3/8 (the pattern
      // is 3 on, 5 off), not 7/2π of it.
      const double radius = 80;
      final dashes = dashedCircle(Offset.zero, radius, on: 3, off: 5);
      final double inked = dashes
          .computeMetrics()
          .fold(0.0, (double sum, ui.PathMetric m) => sum + m.length);

      expect(inked, closeTo(2 * math.pi * radius * 3 / 8, 1.5));
    });

    test('cuts the last dash at the top of the loop rather than wrapping it', () {
      // Canvas restarts a dash pattern per sub-path and simply stops at the
      // path's end, so the final dash is whatever is left. 2π×50 = 314.16, and
      // 314.16 / 8 = 39.27 periods — the last one has 0.27×8 = 2.16px of room
      // for a 3px dash.
      final dashes = dashedCircle(Offset.zero, 50, on: 3, off: 5).computeMetrics().toList();

      expect(dashes.last.length, closeTo(2.16, 0.05));
      expect(dashes.last.length, lessThan(3));
    });
  });

  group('ringLabelText', () {
    test('names the Moon, then counts against it', () {
      // `CLAUDE.md:66`: every distance in this app is a Moon-distance and
      // nothing else. There is no unit to learn here and no big number to be
      // scared of — "20× Moon" is twenty times as far as the thing in the sky
      // tonight.
      expect(ringLabelText(1), '🌙 Moon');
      expect(ringLabelText(2), '2× Moon');
      expect(ringLabelText(50), '50× Moon');
    });

    test('says nothing an astronomer would say', () {
      // The guardrail, pinned so no future edit reintroduces "LD", "lunar
      // distances", or a raw kilometre count onto the one screen every child
      // opens the app to.
      for (final int ld in <int>[1, 2, 5, 10, 20, 50]) {
        final String label = ringLabelText(ld).toLowerCase();
        expect(label, isNot(contains('lunar')));
        expect(label, isNot(contains('ld')));
        expect(label, isNot(contains('km')));
      }
    });
  });

  group('RadarPainter', () {
    testWidgets(
        'draws space, then the backdrop, then the rings, then the Moon, then Earth on top',
        (tester) async {
      // `index.html:818-877` — the prototype's order, and every step of it is a
      // decision about what may cover what. The scenery goes down before
      // anything a child has to read, and Earth is last because it is the
      // smallest and most important object on the screen, so nothing is allowed
      // to cover it. The order *is* the assertion.
      //
      // **Asserted on the recorded call sequence rather than with a `paints`
      // pattern, and the backdrop is exactly why.** `paints` walks forward to
      // the next call of the method named and then matches its arguments
      // strictly, so it can only describe a canvas on which nothing else draws
      // in between — which stopped being true the moment scenery landed
      // underneath (every planet draws circles; Saturn strokes paths). The old
      // pattern passed because the layer happened to be alone on the frame.
      // Indices say the same thing without needing it to be.
      final PlanetBackdrop backdrop = PlanetBackdrop.seed();
      await _radar(tester, backdrop: backdrop);

      final List<({Symbol method, List<dynamic> args})> calls = _calls(tester);
      int at(bool Function(({Symbol method, List<dynamic> args}) call) test, String what) {
        final int i = calls.indexWhere(test);
        expect(i, isNonNegative, reason: 'no $what on the frame');
        return i;
      }

      bool circleAt(({Symbol method, List<dynamic> args}) call, Offset where, double r) =>
          call.method == #drawCircle &&
          ((call.args[0] as Offset) - where).distance < 0.01 &&
          ((call.args[1] as double) - r).abs() < 0.01;

      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      // Neptune is the last row of `PLANETS` (`index.html:795`) and so the last
      // thing the backdrop paints — if *it* is behind the rings, all of the
      // scenery is. Its glow: 2.3 × a 12px disc.
      final Offset neptune = backdrop.positionOf(
        backdrop.planets.last,
        geometry: geometry,
        zoom: 1,
        ts: 0,
      );

      final int space = at((c) => c.method == #drawRect, 'space');
      final int sun = at(
        (c) => circleAt(c, backdrop.sunPosition(geometry: geometry, zoom: 1, ts: 0), 44 * 2.3),
        "the Sun's glow",
      );
      final int scenery = at((c) => circleAt(c, neptune, 12 * 2.3), "Neptune's glow");
      final int rings = at(
        (c) =>
            c.method == #drawPath &&
            (((c.args[0] as Path).getBounds().center) - _centre).distance < 1,
        'a distance ring',
      );
      // The Moon, out on the 1× ring rather than at the centre — it is the only
      // thing on the field that is neither scale nor planet.
      final int moon = at((c) => c.method == #drawCircle && c.args[1] == 5.0, 'the Moon');
      final int glow = at((c) => circleAt(c, _centre, 27.5), "Earth's glow");
      final int earth = at((c) => circleAt(c, _centre, 15), 'Earth');

      expect(
        <int>[space, sun, scenery, rings, moon, glow, earth],
        orderedEquals(<int>[space, sun, scenery, rings, moon, glow, earth]..sort()),
        reason: 'space, the Sun, the last planet, the rings, the Moon, then Earth',
      );
    });

    testWidgets('breathes the glow without moving the planet', (tester) async {
      // The "calm" of `specs/02-live-radar.md:28`, made literal: a ~1.9s breath
      // over three pixels, `26 + pulse*3` where `pulse = (sin(ts/300)+1)/2`
      // (`index.html:820`, `873`). At rest the sine is 0, so the glow starts
      // mid-breath at 27.5 — a quarter period later (471ms) it is at its 29px
      // peak. The planet underneath never moves: it is 15px however far in you
      // are (`index.html:874`).
      await _radar(tester);
      expect(_painterOf(tester), _drawsCircle(radius: closeTo(27.5, 0.001)));

      await tester.pump(const Duration(milliseconds: 471));
      expect(_painterOf(tester), _drawsCircle(radius: closeTo(29, 0.001)));
      // The planet is untouched by the breath — same 15px, same frame.
      expect(_painterOf(tester), _drawsCircle(radius: equals(15.0)));
    });

    testWidgets('paints the rings the sky reaches and no others', (tester) async {
      // One path around Earth per visible ring, so the count is the legend's
      // honesty: a sky that only reaches 8.4 Moon-distances must not be drawn
      // with a 50× ring on it.
      await _radar(tester, maxLd: 8.4);
      expect(
        _ringPaths(tester),
        hasLength(3),
        reason: 'maxLd 8.4 reaches 1×, 2× and 5×',
      );

      // The default field reaches 60, where every ring the prototype offers
      // exists.
      await _radar(tester);
      expect(_ringPaths(tester), hasLength(6));
    });

    testWidgets('strokes the rings dashed, the Moon\'s more solidly than the rest',
        (tester) async {
      // `setLineDash([3,5])` on the 1× and `[2,7]` on the others
      // (`index.html:828`) — the Moon's own ring gets longer dashes and smaller
      // gaps, so it reads as the one real thing out there and the rest as the
      // measuring marks they are.
      //
      // Asserted through the painter rather than on `dashedCircle` alone,
      // because the pure function being right says nothing about this file
      // calling it with the prototype's numbers: solid rings would satisfy
      // every other test here.
      await _radar(tester);

      final List<List<double>> rings = _ringDashes(tester);
      final List<double> radii = _ringRadii(tester);
      expect(rings, hasLength(6));

      for (int i = 0; i < rings.length; i++) {
        // The 1× ring is [3, 5]; every ring beyond it is [2, 7] — shorter
        // marks, wider gaps.
        final double on = i == 0 ? 3 : 2;
        final double period = i == 0 ? 8 : 9;

        // The dash length, on every dash but the last (which the loop cuts).
        expect(
          rings[i].take(rings[i].length - 1),
          everyElement(closeTo(on, 0.01)),
          reason: 'ring $i dash length',
        );
        // And the gap, which only shows up as *how many* dashes fit round the
        // ring — the dash length alone is the same for two different patterns.
        expect(
          rings[i].length,
          closeTo(2 * math.pi * radii[i] / period, 1),
          reason: 'ring $i dash count',
        );
      }
    });

    testWidgets('zooms the rings without zooming Earth', (tester) async {
      // The prototype scales ring radii by `zoom` (`index.html:826`) and strokes
      // Earth at a flat 15px (`index.html:874`). So zooming in spreads the
      // animals out to read them, and the planet they are measured against stays
      // put — a radar that scaled Earth too would swallow the field at 6.5.
      await _radar(tester, zoom: 2);

      expect(_painterOf(tester), _drawsCircle(radius: equals(15.0)));
      // The 1× ring at 78.68 × 2. Measured off the path the painter drew.
      expect(_ringRadii(tester).first, closeTo(78.68 * 2, 0.5));
    });

    testWidgets('renders as an Earth the right size in the right place', (
      tester,
    ) async {
      // The rasterised frame, read back byte by byte. Everything above this
      // asserts what the painter *asked* the canvas for; this is the only thing
      // in the file that knows whether any of it landed.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      // The planet: a 15px disc. Lit from up and to the left, so its own centre
      // is not its brightest point — what is pinned is that it is bright, blue,
      // and opaque, at a radius where nothing else on this layer draws.
      final Color surface = px.at(_centre.dx, _centre.dy);
      expect(surface.a, 1.0);
      expect(surface.b, greaterThan(surface.g), reason: 'a blue planet');
      expect(surface.g, greaterThan(surface.r));
      expect(surface.b, greaterThan(0.5), reason: 'daylight, not deep space');

      // Just outside the disc but inside the glow — dimmer than the planet, and
      // still brighter than the space beyond it.
      final Color glow = px.at(_centre.dx, _centre.dy - 20);
      final Color space = px.at(_centre.dx, _centre.dy - 60);
      expect(glow.b, lessThan(surface.b));
      expect(glow.b, greaterThan(space.b));
    });

    testWidgets('leaves the inner floor clear for the closest animals', (
      tester,
    ) async {
      // Why `radiusFor` has a floor at all, verified in pixels rather than
      // argued: at 42px from Earth — where a zero-distance animal is drawn —
      // the planet and its glow are both finished, so an animal chip there
      // lands on clean space rather than on the planet.
      //
      // Probed as a *step*, not as an absolute colour, because space is itself
      // a gradient: two points at different radii differ slightly no matter
      // what Earth does. The glow is a flat disc, so its edge is a hard jump —
      // find the jump, and show there is none at the floor. Straight up from
      // Earth, which is clear all the way to the 1× ring at ~79px.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      double blueAt(double up) => px.at(_centre.dx, _centre.dy - up).b;

      // Across the glow's edge (27.5px): the atmosphere is 12% of a near-white
      // blue over near-black space, so this is a large, unmistakable step.
      expect(blueAt(24) - blueAt(32), greaterThan(0.05));
      // Across the inner floor: nothing. Whatever tiny difference is left is
      // the space gradient, which drifts by well under a percent over 4px.
      expect((blueAt(42) - blueAt(46)).abs(), lessThan(0.01));
      expect((blueAt(32) - blueAt(42)).abs(), lessThan(0.01));
    });

    testWidgets('fills the field with space rather than leaving it blank', (
      tester,
    ) async {
      // `.radarwrap`'s own background (`index.html:170`), which the prototype
      // puts behind the canvas rather than on it. Painted here so the radar is
      // one self-contained thing; the corner is where its gradient bottoms out,
      // and `#040a17` is the darkest colour in the app.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      expect(px.at(1, _size.height - 2), const Color(0xFF040A17));
      // Brighter towards the middle, which is what makes it a glow.
      expect(px.at(_size.width / 2, _size.height * 0.44 - 60).b,
          greaterThan(px.at(1, _size.height - 2).b));
    });
  });

  group('RadarPainter — layers', () {
    // The Sun's glow is a 44px disc's halo at 2.3×, i.e. 101.2px — a radius
    // nothing else on the frame draws, so it stands in for "the backdrop is
    // painted".
    const double sunGlow = 44 * 2.3;
    bool hasCircle(WidgetTester tester, double radius) => _circles(tester).any(
      (({Offset at, double radius, Paint paint}) c) =>
          (c.radius - radius).abs() < 0.01,
    );

    testWidgets('the Planets chip clears the Sun and the six planets', (tester) async {
      // `if (Radar.showPlanets)` wraps the whole of `drawPlanets`, Sun included
      // (`index.html:818`) — so the chip must clear the 44px orange glare in the
      // corner along with the planets, not leave it bleeding across a
      // switched-off backdrop.
      await _radar(tester);
      expect(hasCircle(tester, sunGlow), isTrue, reason: 'the premise: the Sun is on');

      await _radar(tester, layers: const RadarLayers(planets: false));
      expect(hasCircle(tester, sunGlow), isFalse, reason: 'no Sun, and no planets with it');
    });

    testWidgets('the Rings chip clears the distance rings', (tester) async {
      await _radar(tester);
      expect(_ringPaths(tester), hasLength(6));

      // Moon off as well, so its fallback track cannot stand in for a ring and
      // make an empty chip look like it did nothing.
      await _radar(tester, layers: const RadarLayers(rings: false, moon: false));
      expect(_ringPaths(tester), isEmpty);
    });

    testWidgets('keeps the Moon\'s track when the rings are off but the Moon is not',
        (tester) async {
      // The coupling this item owns (`index.html:835`): Rings off, Moon on —
      // the 1× ring is still stroked so the Moon is never floating on nothing.
      await _radar(tester, layers: const RadarLayers(rings: false));

      final List<Path> track = _ringPaths(tester);
      expect(track, hasLength(1), reason: 'exactly the Moon\'s own track');
      // It rides the 1× ring — same radius the Moon disc does.
      expect(
        _ringRadii(tester).first,
        closeTo(const RadarGeometry(size: _size, maxLd: 60).radiusFor(1), 0.5),
      );
      // And it is dashed on the Moon's own [3, 5] pattern, not a solid stroke.
      final List<double> dashes = <double>[
        for (final ui.PathMetric d in track.first.computeMetrics()) d.length,
      ];
      expect(dashes.length, greaterThan(1));
      expect(dashes.first, closeTo(3, 0.01));
    });

    testWidgets('the Moon chip clears the Moon, and draws no track in its place',
        (tester) async {
      await _radar(tester);
      expect(hasCircle(tester, 5), isTrue, reason: 'the premise: the 5px Moon disc');

      await _radar(tester, layers: const RadarLayers(moon: false));
      expect(hasCircle(tester, 5), isFalse, reason: 'no Moon');
      // Rings are still on, so the six real rings remain — and none of them is a
      // stray Moon track, which only appears when the Moon itself is drawn.
      expect(_ringPaths(tester), hasLength(6));
    });

    testWidgets('the Close-flybys chip thins the sky to the animals that are waving',
        (tester) async {
      // `if (Radar.showHaz && !a.hazardous)` (`index.html:843`), read through the
      // tag (plan decision 2). Counted by the 2px stroke that is the animals'
      // rings alone (the halo is 2.5, the distance rings 1, Saturn's arcs paths).
      final Asteroid waving = _rock(name: '2020 AA', ld: 0.4);
      final Asteroid passing = _rock(name: '2020 BB', ld: 30);

      List<({Offset at, double radius, Paint paint})> animalRings() => <({Offset at, double radius, Paint paint})>[
        for (final ({Offset at, double radius, Paint paint}) c in _circles(tester))
          if (c.paint.style == PaintingStyle.stroke && c.paint.strokeWidth == 2) c,
      ];

      await _radar(tester, sky: <Asteroid>[waving, passing], maxLd: 31.5);
      expect(animalRings(), hasLength(2), reason: 'the premise: both are on');

      await _radar(
        tester,
        sky: <Asteroid>[waving, passing],
        maxLd: 31.5,
        layers: const RadarLayers(closeFlybysOnly: true),
      );
      expect(animalRings(), hasLength(1), reason: 'only the one waving');
    });

    testWidgets('the Labels chip clears the planets\', the Sun\'s, and the animals\' names',
        (tester) async {
      // The Labels chip is one chip over three layers (`index.html:755`, `806`,
      // `864`). Isolated by differencing counts rather than reading text a
      // paragraph does not carry: the planet/Sun names show up as (empty on −
      // empty off), and the animal name as the extra paragraph a waving animal
      // adds beyond its own emoji.
      const RadarLayers off = RadarLayers(labels: false);
      final Asteroid waving = _rock(name: '2020 AA', ld: 0.4);

      await _radar(tester, maxLd: 31.5);
      final int emptyOn = _paragraphOffsets(tester).length;
      await _radar(tester, sky: <Asteroid>[waving], maxLd: 31.5);
      final int wavingOn = _paragraphOffsets(tester).length;

      await _radar(tester, maxLd: 31.5, layers: off);
      final int emptyOff = _paragraphOffsets(tester).length;
      await _radar(tester, sky: <Asteroid>[waving], maxLd: 31.5, layers: off);
      final int wavingOff = _paragraphOffsets(tester).length;

      // Five planet names and the Sun's (Mercury has none) go quiet — the ring
      // labels, "Earth" and "Moon" are not label-gated and stay.
      expect(emptyOn - emptyOff, 6, reason: 'the planets and the Sun');
      // On, a waving animal adds its emoji, its wave and its name; off, the
      // emoji and the wave. **The wave is not label-gated, deliberately**: it
      // is the icon half of "never rely on colour alone"
      // (`specs/06-title-polish-safety.md:23`), so turning names off must not
      // take the app back to marking a close flyby by ring colour alone.
      expect(wavingOn - emptyOn, 3, reason: 'emoji, wave and name');
      expect(wavingOff - emptyOff, 2, reason: 'emoji and wave — the name is gone');
    });
  });

  _animalTests();
}

/// A phone-shaped field, and where Earth sits on it — both from
/// `test/support/radar_frame.dart`, which every radar suite mounts through.
const Size _size = radarSize;
final Offset _centre = radarCentre;

/// The painter under test, filling a field of a known size, so every coordinate
/// above is one the painter computed rather than one the test invented.
Future<void> _radar(
  WidgetTester tester, {
  double maxLd = 60,
  double zoom = 1,
  double viewRot = 0,
  List<Asteroid> sky = const <Asteroid>[],
  Asteroid? selected,
  PlanetBackdrop? backdrop,
  RadarLayers layers = const RadarLayers(),
}) => pumpRadar(
  tester,
  maxLd: maxLd,
  zoom: zoom,
  viewRot: viewRot,
  sky: sky,
  selected: selected,
  backdrop: backdrop,
  layers: layers,
);

/// Every `drawCircle` the painter recorded, in order, with the [Paint] it used.
List<({Offset at, double radius, Paint paint})> _circles(WidgetTester tester) =>
    radarCircles(tester);

/// The circles drawn around [at] — one animal's token, its ring, and its
/// selection ring if it has one.
List<({Offset at, double radius, Paint paint})> _chipAt(
  WidgetTester tester,
  Offset at,
) => <({Offset at, double radius, Paint paint})>[
  for (final ({Offset at, double radius, Paint paint}) c in _circles(tester))
    if ((c.at - at).distance < 0.01) c,
];

/// Where the painter puts [rock] on the first frame — the same question the
/// painter asks [RadarOrbits], asked the same way, so a test can find an
/// animal's own marks without counting every circle on the canvas.
///
/// Safe to re-seed rather than reach into the painter's orbits: the seed is a
/// pure function of the sky and its order (`RadarOrbit.seed`), and at rest the
/// phase has not been advanced.
Offset _animalAt(Asteroid rock) {
  final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[rock]);
  return orbits.positionOf(
    orbits.orbits.single,
    geometry: const RadarGeometry(size: _size, maxLd: 60),
    zoom: 1,
    viewRot: 0,
  );
}

/// The selection halo — the only 2.5px stroke on the whole field, which is what
/// lets it be found without knowing where the animal has orbited to.
({Offset at, double radius, Paint paint}) _halo(WidgetTester tester) => _circles(
  tester,
).singleWhere((({Offset at, double radius, Paint paint}) c) => c.paint.strokeWidth == 2.5);

/// The selection caret — the only **filled** path on the whole frame, which is
/// what lets it be found without knowing where the animal has orbited to.
///
/// That identifier is checked, not assumed: every other `drawPath` in the app's
/// radar layers is stroked — the distance rings (`radar_painter.dart:204`,
/// `239`) and Saturn's three arcs (`planet_painters.dart:379-384`) — and
/// `the caret is the only filled path` below fails if that ever stops being
/// true, rather than letting this helper quietly pick up someone else's shape.
({Path path, Paint paint}) _caret(WidgetTester tester) =>
    _filledPaths(tester).single;

List<({Path path, Paint paint})> _filledPaths(WidgetTester tester) => <({Path path, Paint paint})>[
  for (final ({Path path, Paint paint}) drawn in radarPaths(tester))
    if (drawn.paint.style == PaintingStyle.fill) drawn,
];

/// A rock with only what the radar reads. [ld] and [diaMax] are the two inputs
/// that decide everything on screen: where it orbits and how big it is drawn.
Asteroid _rock({
  required String name,
  required double ld,
  double diaMax = 300,
  bool hazardous = false,
}) => Asteroid(
  name: name,
  diaMax: diaMax,
  diaMin: diaMax / 2,
  hazardous: hazardous,
  missLunar: ld,
  missKm: ld * 384400,
  velKps: 10,
  mag: 20,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: 'sample',
);

/// The animals themselves: the token, the ring that says what they are doing,
/// and the name only some of them show.
///
/// Colours are asserted off the recorded [Paint]s rather than off pixels,
/// because the emoji sits over the middle of every chip and `flutter_test`
/// renders text in a box font — so a probe near a token is reading the test
/// harness's glyph, not the app's. The Moon is the one thing here with clear
/// space around it, so it is the one thing rasterised.
void _animalTests() {
  group('RadarPainter — animals', () {
    testWidgets('draws a token, then its ring, then the animal in it', (tester) async {
      // The order is the guardrail (`index.html:852-862`). An emoji straight
      // onto deep space is dim and, next to a big one, reads as switched off —
      // and `specs/02-live-radar.md:28` is explicit that no animal may ever look
      // faded. The token is what gives every animal the same lit background
      // whatever its size, so the size difference stays a size difference.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(tester, sky: <Asteroid>[rock]);

      // **Found by where the animal is, not by counting circles from the start
      // of the frame.** This used to read `circles[1]` and `circles[2]` on the
      // grounds that the Moon was the only circle before them — which the planet
      // backdrop ended, since the Sun alone puts two circles on the canvas first.
      // Asking for the circles *at the animal* is what the test meant all along,
      // and it cannot be knocked over by anything drawn elsewhere.
      final List<({Offset at, double radius, Paint paint})> chip =
          _chipAt(tester, _animalAt(rock));
      expect(chip, hasLength(2), reason: 'an unselected animal is a token and a ring');
      final ({Offset at, double radius, Paint paint}) token = chip[0];
      final ({Offset at, double radius, Paint paint}) ring = chip[1];

      expect(token.at, ring.at, reason: 'the ring is around the token');
      expect(token.radius, closeTo(ring.radius, 1e-9));
      expect(token.paint.style, PaintingStyle.fill);
      expect(
        token.paint.shader,
        isNotNull,
        reason: 'a lit gradient, not a flat disc — it is what makes the animal '
            'sit in something rather than float on the field',
      );
      expect(ring.paint.style, PaintingStyle.stroke);
      expect(ring.paint.strokeWidth, 2);
    });

    testWidgets('sizes each animal by the real rock, not by the species', (tester) async {
      // Two animals, four orders of magnitude apart in real diameter. The one on
      // screen must be bigger — and both must still be big enough to see.
      final Asteroid mouse = _rock(name: '2020 SW', ld: 5, diaMax: 4);
      final Asteroid whale = _rock(name: '433 Eros', ld: 5, diaMax: 16800);
      await _radar(tester, sky: <Asteroid>[mouse, whale]);

      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[mouse, whale]);
      expect(orbits.orbits[0].chipRadius, lessThan(orbits.orbits[1].chipRadius));
      // Both are drawn at the size the ladder gave them.
      final List<double> radii = <double>[
        for (final ({Offset at, double radius, Paint paint}) c in _circles(tester))
          if (c.paint.style == PaintingStyle.stroke) c.radius,
      ];
      expect(radii, contains(closeTo(orbits.orbits[0].chipRadius, 0.01)));
      expect(radii, contains(closeTo(orbits.orbits[1].chipRadius, 0.01)));
    });

    testWidgets('rings a close flyby orange and everyone else quietly', (tester) async {
      // `index.html:854`. The orange is a *greeting*, not a warning
      // (`CLAUDE.md:64`) — and it is the only thing on this screen that marks
      // NASA's flag at all.
      final Asteroid waving = _rock(name: '2020 AA', ld: 0.4);
      final Asteroid passing = _rock(name: '2020 BB', ld: 30);
      await _radar(tester, sky: <Asteroid>[waving, passing], maxLd: 31.5);

      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 31.5);
      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[waving, passing]);

      final Paint wavingRing = _chipAt(
        tester,
        orbits.positionOf(orbits.orbits[0], geometry: geometry, zoom: 1, viewRot: 0),
      ).last.paint;
      final Paint passingRing = _chipAt(
        tester,
        orbits.positionOf(orbits.orbits[1], geometry: geometry, zoom: 1, viewRot: 0),
      ).last.paint;

      // `isSameColorAs`, not `equals`: `Paint.color` round-trips through float32,
      // so a colour comes back a few ulps from the one that went in and `==` is
      // false between two Colours that print identically.
      expect(wavingRing.color, isSameColorAs(const Color.fromRGBO(232, 140, 60, 0.95)));
      expect(passingRing.color, isSameColorAs(const Color.fromRGBO(120, 150, 200, 0.45)));
    });

    testWidgets('rings a flagged rock even when it passes far away', (tester) async {
      // `flybyTag`'s rule is `hazardous || missLunar < 1`, and the radar reads
      // the tag rather than the raw flag — so the ring here and the badge on the
      // detail screen can never disagree about which animals are waving.
      final Asteroid flagged = _rock(name: '2020 CC', ld: 30, hazardous: true);
      await _radar(tester, sky: <Asteroid>[flagged], maxLd: 31.5);

      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[flagged]);
      final Offset at = orbits.positionOf(
        orbits.orbits[0],
        geometry: const RadarGeometry(size: _size, maxLd: 31.5),
        zoom: 1,
        viewRot: 0,
      );
      expect(
        _chipAt(tester, at).last.paint.color,
        isSameColorAs(const Color.fromRGBO(232, 140, 60, 0.95)),
      );
    });

    testWidgets('gives the selected animal a white ring that breathes', (tester) async {
      // `index.html:855-857` — a second ring at `chip + 3 + pulse*3`, on the
      // same breath as Earth's glow. White because it is the only colour on this
      // field that means nothing else.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(tester, sky: <Asteroid>[rock], selected: rock);

      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[rock]);
      final Offset at = orbits.positionOf(
        orbits.orbits[0],
        geometry: const RadarGeometry(size: _size, maxLd: 60),
        zoom: 1,
        viewRot: 0,
      );
      final double chip = orbits.orbits[0].chipRadius;

      final ({Offset at, double radius, Paint paint}) halo = _chipAt(tester, at).last;
      expect(halo.paint.color, isSameColorAs(const Color(0xFFFFFFFF)));
      expect(halo.paint.strokeWidth, 2.5);
      // At rest the sine is 0, so pulse is 0.5 and the halo starts mid-breath.
      expect(halo.radius, closeTo(chip + 3 + 1.5, 0.001));

      // A quarter period on (471ms) it is at full stretch — and by then the
      // animal has orbited, so the halo is found by the 2.5px stroke that
      // nothing else on the field uses rather than by where it used to be.
      await tester.pump(const Duration(milliseconds: 471));
      expect(_halo(tester).radius, closeTo(chip + 6, 0.001));
    });

    testWidgets('points at the selected animal, so selection is not hue alone', (
      tester,
    ) async {
      // `specs/06-title-polish-safety.md:23` — never colour alone. The halo
      // above is white, a close flyby's ring is orange and a resting animal's
      // is blue-grey, and in the greyscale check that spec asks for all three
      // are just light rings round a token. The caret is the second channel:
      // the one mark on this field that is not a ring, a disc or a glyph, so a
      // child who cannot separate those hues can still tell which animal the
      // HUD card is about.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(tester, sky: <Asteroid>[rock], selected: rock);

      final Offset at = _animalAt(rock);
      final double chip = RadarOrbits.seed(<Asteroid>[rock]).orbits[0].chipRadius;
      final Rect bounds = _caret(tester).path.getBounds();

      expect(
        _caret(tester).paint.color,
        isSameColorAs(const Color(0xFFFFFFFF)),
        reason: 'no new colour is introduced — the shape is the new channel',
      );
      expect(
        bounds.center.dx,
        closeTo(at.dx, 0.001),
        reason: 'it points along the token\'s own axis, not off to one side',
      );
      // Apex up, base down: the top edge is a point and the bottom is the full
      // width. Asserted as a *shape*, because a triangle drawn the other way up
      // would satisfy every bound below and point at empty space.
      expect(bounds.width, closeTo(chip * 0.42 * 2, 0.001));
      expect(bounds.height, closeTo(chip * 0.5, 0.001));
      expect(
        _caret(tester).path.contains(Offset(at.dx, bounds.top + 0.5)),
        isTrue,
        reason: 'the apex is on the token\'s axis',
      );
      expect(
        _caret(tester).path.contains(Offset(bounds.left + 0.5, bounds.top + 0.5)),
        isFalse,
        reason: 'the wide edge is the far one — the arrow points up at the animal',
      );
    });

    testWidgets('hangs the caret off the breathing halo, clear of its stroke', (
      tester,
    ) async {
      // The two are one mark, not a ring with a sticker beside it, so the caret
      // rides the same sine the halo does. If it were anchored to `chip`
      // instead, the halo would breathe *through* it at full stretch.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(tester, sky: <Asteroid>[rock], selected: rock);

      final Offset at = _animalAt(rock);
      final double chip = RadarOrbits.seed(<Asteroid>[rock]).orbits[0].chipRadius;

      // At rest the sine is 0, so pulse is 0.5 and the halo is mid-breath — the
      // same frame `gives the selected animal a white ring that breathes` pins.
      expect(_caret(tester).path.getBounds().top, closeTo(at.dy + chip + 3 + 1.5 + 1.5, 0.001));

      // A quarter period on the halo is at full stretch, and the caret has
      // moved out with it — found by the fill rather than by where it was,
      // since the animal has orbited in the meantime.
      await tester.pump(const Duration(milliseconds: 471));
      final ({Path path, Paint paint}) moved = _caret(tester);
      expect(
        moved.path.getBounds().top - _halo(tester).at.dy,
        closeTo(chip + 6 + 1.5, 0.001),
        reason: 'still 1.5px outside the halo, wherever the breath has taken it',
      );
    });

    testWidgets('the caret is the only filled path on the frame', (tester) async {
      // `_caret` finds the mark by its fill, which is only a safe identifier
      // while every other path on this canvas is stroked — the distance rings
      // and Saturn's arcs. This is that claim, held where it will fail loudly
      // if a later layer lands a filled path and starts being mistaken for the
      // selection mark.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);

      await _radar(tester, sky: <Asteroid>[rock]);
      expect(_filledPaths(tester), isEmpty, reason: 'nothing is selected');

      await _radar(tester, sky: <Asteroid>[rock], selected: rock);
      expect(_filledPaths(tester), hasLength(1));
    });

    testWidgets('gives the caret to the selected animal and to no one else', (
      tester,
    ) async {
      // One caret on a sky of three: a mark that appeared on every animal would
      // point at nothing, which is the failure this rules out.
      final Asteroid a = _rock(name: '2020 AA', ld: 5);
      final Asteroid b = _rock(name: '2020 BB', ld: 6);
      final Asteroid c = _rock(name: '2020 CC', ld: 0.4, hazardous: true);
      await _radar(tester, sky: <Asteroid>[a, b, c], selected: b);

      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[a, b, c]);
      final Offset at =
          orbits.positionOf(orbits.orbits[1], geometry: geometry, zoom: 1, viewRot: 0);

      final List<({Path path, Paint paint})> carets = _filledPaths(tester);
      expect(carets, hasLength(1));
      expect(carets.single.path.getBounds().center.dx, closeTo(at.dx, 0.001));
    });

    testWidgets('keeps the caret when names are switched off', (tester) async {
      // The wave's rule, for the same reason (`radar_painter.dart`'s caret
      // doc): with the Labels chip off the HUD card is still the only text
      // naming the animal, so dropping the caret would leave selection as a
      // white ring and nothing else — colour alone, exactly what this mark
      // exists to stop.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(
        tester,
        sky: <Asteroid>[rock],
        selected: rock,
        layers: const RadarLayers(labels: false),
      );

      expect(_filledPaths(tester), hasLength(1));
    });

    testWidgets('leaves every other animal ringless', (tester) async {
      // Only the selected one gets a halo. Two circles per animal, not three.
      final Asteroid a = _rock(name: '2020 AA', ld: 5);
      final Asteroid b = _rock(name: '2020 BB', ld: 6);
      await _radar(tester, sky: <Asteroid>[a, b], selected: a);

      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[a, b]);

      expect(
        _chipAt(tester, orbits.positionOf(orbits.orbits[0], geometry: geometry, zoom: 1, viewRot: 0)),
        hasLength(3),
        reason: 'token, ring, halo',
      );
      expect(
        _chipAt(tester, orbits.positionOf(orbits.orbits[1], geometry: geometry, zoom: 1, viewRot: 0)),
        hasLength(2),
        reason: 'token and ring only',
      );
    });

    testWidgets('selects by designation, so nothing depends on object identity',
        (tester) async {
      // The prototype compares references (`Radar.selected===a`) because it only
      // ever has the one array. The designation is this app's identity for a rock
      // (plan decision 12), and it does not care which list the asteroid came out
      // of — an equal-but-not-identical rock must still be the selected one.
      final Asteroid rock = _rock(name: '2020 AA', ld: 5);
      await _radar(
        tester,
        sky: <Asteroid>[rock],
        selected: _rock(name: '2020 AA', ld: 5),
      );

      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[rock]);
      final Offset at = orbits.positionOf(
        orbits.orbits[0],
        geometry: const RadarGeometry(size: _size, maxLd: 60),
        zoom: 1,
        viewRot: 0,
      );
      expect(_chipAt(tester, at), hasLength(3), reason: 'it is still selected');
    });

    testWidgets('carries every animal round its own ring as time passes', (tester) async {
      // The orbit loop, seen through the painter rather than through the model:
      // the pure integrator being right says nothing about whether this file
      // reads it. Both animals must move, and the closer one must move further.
      final Asteroid near = _rock(name: '2020 AA', ld: 0.5);
      final Asteroid far = _rock(name: '2020 BB', ld: 30);
      await _radar(tester, sky: <Asteroid>[near, far], maxLd: 31.5);

      final List<Offset> before = <Offset>[
        for (final ({Offset at, double radius, Paint paint}) c in _circles(tester)) c.at,
      ];
      await tester.pump(const Duration(seconds: 2));
      final List<Offset> after = <Offset>[
        for (final ({Offset at, double radius, Paint paint}) c in _circles(tester)) c.at,
      ];

      expect(after, isNot(before), reason: 'the sky is alive');
      // Earth never moves, however long anyone watches.
      expect(after.last, before.last);
    });

    testWidgets('names the animals that are waving, and no others', (tester) async {
      // `index.html:864`. Sixty names at once would be a wall of text on the one
      // screen a five-year-old opens the app to; the rest introduce themselves
      // when they are tapped.
      //
      // Counted against an empty sky at the same `maxLd`, so the rings' own
      // labels, "Earth" and "Moon" are constant across the three frames and the
      // only difference is the animals.
      //
      // **Every animal contributes one paragraph before any name does: its own
      // emoji.** So "just passing" is base + 1, not base — the emoji is text on
      // this canvas too, which is easy to forget and would make a silently
      // wrong test read as a passing one.
      await _radar(tester, maxLd: 31.5);
      final int base = _paragraphOffsets(tester).length;

      await _radar(tester, sky: <Asteroid>[_rock(name: '2020 BB', ld: 30)], maxLd: 31.5);
      expect(
        _paragraphOffsets(tester), hasLength(base + 1),
        reason: 'its emoji and nothing else — a rock just passing keeps its name to itself',
      );

      await _radar(tester, sky: <Asteroid>[_rock(name: '2020 AA', ld: 0.4)], maxLd: 31.5);
      expect(
        _paragraphOffsets(tester), hasLength(base + 3),
        reason: 'emoji, wave and name — a close flyby says hello, twice over',
      );
    });

    testWidgets('sits the name above the animal, not across it', (tester) async {
      // `y - em*0.6 - 4` (`index.html:867`) — clear of the emoji's own box, so
      // the name never lands on the animal's face.
      //
      // Isolated by selecting the same rock rather than by hunting near a
      // coordinate: selection adds the name and moves nothing, so the one offset
      // that appears between the two frames *is* the name. Searching by position
      // instead picks up the animal's own emoji and whatever ring label happens
      // to be nearby.
      final Asteroid rock = _rock(name: '2020 BB', ld: 30);
      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[rock]);
      final RadarOrbit orbit = orbits.orbits[0];
      final Offset at = orbits.positionOf(
        orbit,
        geometry: const RadarGeometry(size: _size, maxLd: 31.5),
        zoom: 1,
        viewRot: 0,
      );

      await _radar(tester, sky: <Asteroid>[rock], maxLd: 31.5);
      final Set<({Offset at, double width})> unnamed = _paragraphOffsets(tester).toSet();

      await _radar(tester, sky: <Asteroid>[rock], maxLd: 31.5, selected: rock);
      final Set<({Offset at, double width})> named = _paragraphOffsets(tester).toSet();

      final ({Offset at, double width}) name = named.difference(unnamed).single;
      expect(
        name.at.dy,
        lessThan(at.dy - orbit.emojiSize * 0.5),
        reason: 'above the emoji box, not over it',
      );
      expect(
        name.at.dx + name.width / 2,
        closeTo(at.dx, 0.01),
        reason: 'centred over the animal it belongs to',
      );
    });

    testWidgets('waves at a close flyby, so the ring is not the only mark', (
      tester,
    ) async {
      // **The radar's half of "never rely on colour alone"**
      // (`specs/06-title-polish-safety.md:23`). Until the accessibility audit
      // this field marked a close flyby with an orange ring and nothing else —
      // meaningless to a colour-blind child, and to any child who has not been
      // told what orange stands for. The 👋 is the same glyph the badge, the
      // home strip's count and the Sky filter already use, so the radar now says
      // what the rest of the app says.
      //
      // Counted rather than read, because a `ui.Paragraph` does not carry its
      // text: the wave is one extra laid-out label on the *same sky*, with
      // labels off so the name cannot account for it.
      const RadarLayers noLabels = RadarLayers(labels: false);
      final Asteroid passing = _rock(name: '2020 BB', ld: 20);
      final Asteroid waving = _rock(name: '2020 BB', ld: 0.5);

      await _radar(tester, sky: <Asteroid>[passing], layers: noLabels);
      final int quiet = _paragraphOffsets(tester).length;

      await _radar(tester, sky: <Asteroid>[waving], layers: noLabels);

      expect(
        _paragraphOffsets(tester),
        hasLength(quiet + 1),
        reason: 'a close flyby draws its emoji and a wave',
      );
    });

    testWidgets('and a rock just passing is not waved at', (tester) async {
      // The other arm, and the one that stops the fix from becoming "every
      // animal waves", which would say nothing at all.
      const RadarLayers noLabels = RadarLayers(labels: false);

      await _radar(
        tester,
        sky: <Asteroid>[_rock(name: '2020 BB', ld: 20)],
        layers: noLabels,
      );
      final int passing = _paragraphOffsets(tester).length;

      await _radar(
        tester,
        sky: <Asteroid>[_rock(name: '2020 CC', ld: 30)],
        layers: noLabels,
      );

      expect(_paragraphOffsets(tester), hasLength(passing));
    });

    testWidgets('the wave sits on the token, clear of the name above it', (
      tester,
    ) async {
      // Placement is behaviour here: a wave drawn at the animal's centre would
      // sit under the emoji and be invisible, and one drawn straight up would
      // collide with the name label a close flyby also shows.
      //
      // Isolated by the set-difference idiom the name test above established —
      // the same rock at the same place, close in one frame and passing in the
      // other, so the single offset that appears *is* the wave.
      const RadarLayers noLabels = RadarLayers(labels: false);
      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      final Asteroid passing = _rock(name: '2020 BB', ld: 20);
      final Asteroid waving = _rock(name: '2020 BB', ld: 0.5);

      await _radar(tester, sky: <Asteroid>[passing], layers: noLabels);
      final Set<({Offset at, double width})> quiet =
          _paragraphOffsets(tester).toSet();

      await _radar(tester, sky: <Asteroid>[waving], layers: noLabels);
      final Set<({Offset at, double width})> withWave =
          _paragraphOffsets(tester).toSet();

      final RadarOrbits orbits = RadarOrbits.seed(<Asteroid>[waving]);
      final Offset at = orbits.positionOf(
        orbits.orbits[0],
        geometry: geometry,
        zoom: 1,
        viewRot: 0,
      );

      // Two offsets differ — the emoji moved with the rock's new distance, and
      // the wave is new — so the wave is the one up and to the right of centre.
      final Iterable<({Offset at, double width})> fresh =
          withWave.difference(quiet);
      expect(
        fresh.any((o) => o.at.dx > at.dx && o.at.dy < at.dy),
        isTrue,
        reason: 'the wave sits on the token\'s upper-right shoulder',
      );
    });

    testWidgets('names the selected animal even when it is only passing', (tester) async {
      // `showLabels && (close || sel)` (`index.html:864`) — being looked at is
      // reason enough to say your name, however far away you are.
      final Asteroid passing = _rock(name: '2020 BB', ld: 30);
      await _radar(tester, sky: <Asteroid>[passing], maxLd: 31.5);
      final int unnamed = _paragraphOffsets(tester).length;

      await _radar(
        tester,
        sky: <Asteroid>[passing],
        maxLd: 31.5,
        selected: passing,
      );
      expect(_paragraphOffsets(tester), hasLength(unnamed + 1));
    });

    testWidgets('draws a busy day, and lays each label out only once', (tester) async {
      // The automatable half of "a busy day (60+) holds ~60fps". The frame rate
      // itself needs a device this machine does not have (no Xcode, no Android
      // SDK — the plan's human-gated item), and is NOT claimed here. What can be
      // checked is the claim the port actually rests on: laying text out is by a
      // distance the most expensive thing this painter does, and it does it once
      // per label rather than once per label per frame. A radar that re-measured
      // all sixty animals every frame would look identical from the outside and
      // only show itself on a child's phone.
      final List<Asteroid> busy = <Asteroid>[
        for (int i = 0; i < 60; i++)
          _rock(
            name: '2026 A$i',
            // Spread across the whole field, and every rung of the size ladder,
            // so this is a real sky's worth of distinct labels rather than sixty
            // copies of one.
            ld: 0.2 + i * 0.5,
            diaMax: 4.0 + i * 40,
          ),
      ];

      await _radar(tester, sky: busy);
      final int afterFirstFrame = debugLabelLayouts;

      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        debugLabelLayouts,
        afterFirstFrame,
        reason: 'thirty more frames must not lay out a single label again',
      );
      // And the sky really was drawn — one ring per animal, found by the 2px
      // stroke that is theirs alone on this canvas (the halo is 2.5, the
      // distance rings 1, and the backdrop strokes only Saturn's, as paths).
      // **Not by counting every circle on the frame, which is what this used to
      // do**: the backdrop now puts twenty of its own underneath, and — worse —
      // these animals have been orbiting for thirty frames, so there is no
      // position left to look them up by. What identifies an animal is what it
      // is drawn *like*, which does not move.
      expect(
        _circles(tester).where(
          (({Offset at, double radius, Paint paint}) c) =>
              c.paint.style == PaintingStyle.stroke && c.paint.strokeWidth == 2,
        ),
        hasLength(60),
      );
    });

    testWidgets('draws the Moon on its ring, in the flesh', (tester) async {
      // Rasterised through `flutter_tester` — the same painting pipeline a phone
      // runs — because every assertion above would pass just as happily for a
      // Moon painted off the bottom of the screen. The Moon is the one object on
      // this field with clear space around it, so it is the one that can honestly
      // be probed for its own colour.
      await _radar(tester);

      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      final Offset moon = RadarOrbits.seed(const <Asteroid>[])
          .moonPosition(geometry: geometry, zoom: 1, viewRot: 0);
      final _Pixels pixels = await _paintedPixels(tester);

      expect(pixels.at(moon.dx, moon.dy), const Color(0xFFCFD6DE));
      // A 5px disc and not a smear: eight pixels out is space again.
      expect(pixels.at(moon.dx + 8, moon.dy), isNot(const Color(0xFFCFD6DE)));
      // And it really is out on the 1× ring rather than sitting on Earth.
      expect((moon - geometry.center).distance, closeTo(geometry.radiusFor(1), 0.01));
    });

    testWidgets('carries viewRot to the animals *and* the Moon', (tester) async {
      // **The one bug the pure orbit tests cannot see.** `RadarOrbits` is now
      // proven to turn everything by one shared angle, but it can only turn what
      // it is asked to: `viewRot` reaches the field through two separate calls
      // here (`index.html:837`, `845`), and a painter that passes it to
      // `positionOf` and forgets `moonPosition` spins the sky around a Moon
      // standing still. That is invisible in a still frame and wrong in the one
      // way this screen cannot afford — the Moon is the ruler every distance on
      // it is read against.
      final Asteroid rock = _rock(name: 'probe', ld: 5);
      const RadarGeometry geometry = RadarGeometry(size: _size, maxLd: 60);
      const double turn = math.pi / 2;

      await _radar(tester, viewRot: turn, sky: <Asteroid>[rock]);

      final RadarOrbits expected = RadarOrbits.seed(<Asteroid>[rock]);
      final Offset animal = expected.positionOf(
        expected.orbits[0],
        geometry: geometry,
        zoom: 1,
        viewRot: turn,
      );
      final Offset moon = expected.moonPosition(
        geometry: geometry,
        zoom: 1,
        viewRot: turn,
      );

      // Both are a quarter-turn on from where they rest, which for these two —
      // the animal seeded at phase 0, the Moon at 0 on a frame that has not
      // advanced — means both are due *south* of Earth rather than due east.
      expect(moon.dy, greaterThan(geometry.center.dy));
      expect(moon.dx, closeTo(geometry.center.dx, 1e-9));
      expect(animal.dy, greaterThan(geometry.center.dy));

      expect(
        _circles(tester).map((c) => c.at),
        containsAll(<Matcher>[
          _near(moon),
          _near(animal),
        ]),
        reason: 'a Moon left at three o’clock means it never got the rotation',
      );
    });
  });
}

/// Matches an [Offset] within a pixel of [at] — the painter and the test compute
/// the same trigonometry, so this is about float noise, not tolerance.
Matcher _near(Offset at) => predicate<Offset>(
  (Offset o) => (o - at).distance < 1,
  'within 1px of $at',
);

/// Where every string the painter laid down this frame was drawn, and how wide
/// it is.
///
/// A [ui.Paragraph] does not carry its text, so *which* label this is has to be
/// read from where it landed — which is worth pinning anyway, since a name drawn
/// in the right style at the wrong place is still wrong. The offset is the
/// text's **left edge**, not its centre: `_Label.paint` does the centring itself
/// (canvas's `textAlign="center"`), so recovering the centre needs the width.
List<({Offset at, double width})> _paragraphOffsets(WidgetTester tester) =>
    radarParagraphs(tester);

RenderBox _painterOf(WidgetTester tester) => radarPainterOf(tester);

/// The rings, outward — the paths the painter drew **around Earth**.
///
/// **The centre filter is not decoration, it is the whole definition.** This
/// used to collect every `drawPath` on the frame, on the stated grounds that
/// nothing else on the layer drew one; the planet backdrop landing underneath
/// ended that, because Saturn's three ring arcs are `drawPath`s too. A ring is
/// not "a path" — it is a circle centred on Earth, which is what a distance ring
/// *is*, and Saturn's arcs are 460px away from that. So the filter says the
/// thing the old count was only assuming.
List<Path> _ringPaths(WidgetTester tester) => <Path>[
  for (final ({Path path, Paint paint}) drawn in radarPaths(tester))
    if ((drawn.path.getBounds().center - _centre).distance < 1) drawn.path,
];

/// The length of each dash on each ring, outward.
List<List<double>> _ringDashes(WidgetTester tester) => <List<double>>[
  for (final Path ring in _ringPaths(tester))
    <double>[for (final ui.PathMetric dash in ring.computeMetrics()) dash.length],
];

/// The radius of each ring, taken from the path the painter actually drew
/// rather than from anything it was asked for.
List<double> _ringRadii(WidgetTester tester) => <double>[
  for (final Path ring in _ringPaths(tester)) ring.getBounds().width / 2,
];

/// Matches a `drawCircle` at Earth's centre whose radius satisfies [radius].
///
/// The `paints` pattern's own `circle(radius:)` compares exactly, which the
/// glow cannot be held to: its radius is the output of a sine, so the only
/// frames with a clean value are the ones a test would have to contrive.
PaintPattern _drawsCircle({required Matcher radius}) =>
    paints..something((Symbol method, List<dynamic> arguments) {
      if (method != #drawCircle) return false;
      final Offset centre = arguments[0] as Offset;
      return centre == _centre && radius.matches(arguments[1], <dynamic, dynamic>{});
    });

/// Every canvas call the painter recorded, in order.
List<({Symbol method, List<dynamic> args})> _calls(WidgetTester tester) =>
    radarCalls(tester);

/// The rendered frame, read back from the engine — a real rasterisation through
/// `flutter_tester`, the same painting pipeline a phone runs. `toImage` must go
/// through [WidgetTester.runAsync] because a `testWidgets` body runs in a
/// fake-async zone where a future waiting on the real engine never completes.
Future<_Pixels> _paintedPixels(WidgetTester tester) => rasteriseRadar(tester);

typedef _Pixels = RadarPixels;
