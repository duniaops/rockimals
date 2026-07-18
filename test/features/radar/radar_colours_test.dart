import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';

import '../../support/radar_frame.dart';

/// What colour the radar is, pinned one literal at a time.
///
/// **Why this file exists.** `radar_painter_test.dart` proves the radar draws
/// the right *things* in the right *places*, and it pins a handful of colours it
/// happened to need (the close-flyby ring, the resting ring, the selection
/// white, the Moon's grey). Everything else was unpinned: changing
/// `_ringLabelColour`'s alpha from `.55` to `.50` passed all 258 tests, and so
/// did editing a ring stroke or one of Earth's three gradient stops. This is a
/// screen ported pixel-for-pixel from a prototype (`CLAUDE.md:20`), so a colour
/// drifting silently is a port breaking silently.
///
/// **Every expected value here is written out from `index.html`, not read back
/// from the app.** That is the whole point: a test that derived its expectation
/// from the same constant it is checking would pass whatever that constant said.
/// Each literal below carries the prototype line it came from.
///
/// **Two techniques, because a colour reaches the screen in two ways.**
///
///  * *Through a [Paint]* — the ring strokes and Earth's glow set `color`
///    directly, so the recorded call carries the answer and it is asserted
///    exactly.
///  * *Through a shader or a glyph* — Earth's disc, the animals' tokens and
///    every label do not. `ui.Gradient` is opaque to a test and a [ui.Paragraph]
///    does not carry its style, so these are checked against **the rendered
///    frame**: the test paints a reference of its own from the prototype's
///    literals ([_render]) and compares the two rasters. Where a label is
///    involved the reference is the *background* it sits on, and the expected
///    ink is that background with the label's colour composited over it —
///    `flutter_test` draws every glyph as a solid box, which is what makes a
///    probe inside one exact rather than an antialiasing lottery.
void main() {
  group('the space behind everything', () {
    testWidgets('is the prototype\'s own two-stop glow, corner to heart',
        (WidgetTester tester) async {
      // `.radarwrap`'s background (`index.html:170`): `#0c2044` at the heart,
      // `#040a17` from 72% out. Only the corner was pinned before this, which
      // left the near end — the colour of four-fifths of the screen — free to
      // drift.
      await pumpRadar(
        tester,
        layers: const RadarLayers(planets: false, rings: false, moon: false),
      );
      final RadarPixels frame = await rasteriseRadar(tester);
      final RadarPixels reference = await _render(tester, _paintSpace);

      // Everywhere the frame is space and nothing else. Earth and its glow reach
      // 29px from the centre; 60 is clear of them and of the antialiased edge.
      for (final Offset probe in <Offset>[
        const Offset(1, 1),
        Offset(radarSize.width - 2, 1),
        const Offset(1, 698),
        Offset(radarSize.width - 2, radarSize.height - 2),
        Offset(radarCentre.dx, radarCentre.dy - 60),
        Offset(radarCentre.dx - 120, radarCentre.dy),
        Offset(radarCentre.dx, radarSize.height - 40),
        Offset(radarSize.width - 30, radarCentre.dy + 100),
      ]) {
        _expectPixel(frame, reference, probe, reason: 'space at $probe');
      }
    });
  });

  group('the distance rings', () {
    testWidgets('strokes the Moon\'s ring brighter than the marks beyond it',
        (WidgetTester tester) async {
      // `rgba(207,214,222,.30)` on the 1× and `rgba(90,120,170,.16)` on the rest
      // (`index.html:827`). The difference is the whole legend: the 1× ring is
      // the Moon's own orbit — the unit every other ring is read against — and
      // the others are the faint measuring marks it is read with.
      await pumpRadar(tester);
      final List<({Path path, Paint paint})> rings = _ringsOf(tester);
      expect(rings, hasLength(6), reason: 'a 60-Moon sky draws every ring');

      expect(
        rings.first.paint.color,
        isSameColorAs(const Color.fromRGBO(207, 214, 222, 0.30)),
        reason: 'the 1× ring',
      );
      for (final ({Path path, Paint paint}) ring in rings.skip(1)) {
        expect(
          ring.paint.color,
          isSameColorAs(const Color.fromRGBO(90, 120, 170, 0.16)),
          reason: 'every ring beyond the Moon\'s',
        );
      }
    });

    testWidgets('dims the Moon\'s track two points below the ring it replaces',
        (WidgetTester tester) async {
      // With the Rings chip off the Moon keeps a track of its own so it is not
      // floating on nothing (`index.html:835`) — at `.28` rather than the `.30`
      // the 1× ring proper is stroked at, because here it is the Moon's orbit
      // and not one of the measuring marks. Two points is invisible to the eye
      // and deliberate in the prototype, which is exactly the kind of value that
      // gets "tidied" to match its neighbour.
      await pumpRadar(tester, layers: const RadarLayers(rings: false));
      final List<({Path path, Paint paint})> tracks = _ringsOf(tester);

      expect(tracks, hasLength(1), reason: 'the Moon\'s track and no rings');
      expect(
        tracks.single.paint.color,
        isSameColorAs(const Color.fromRGBO(207, 214, 222, 0.28)),
      );
      expect(
        tracks.single.paint.color,
        isNot(isSameColorAs(const Color.fromRGBO(207, 214, 222, 0.30))),
        reason: 'dimmer than the ring it stands in for, not the same stroke',
      );
    });
  });

  group('Earth', () {
    testWidgets('breathes a 12% atmosphere, not a solid halo',
        (WidgetTester tester) async {
      // `rgba(120,180,255,.12)` (`index.html:873`). The radius is a sine and is
      // pinned elsewhere; what is pinned here is that the glow stays a hint of
      // atmosphere. At any greater alpha it stops being the calm
      // `specs/02-live-radar.md:28` asks for and starts being a beacon.
      await pumpRadar(tester);

      expect(
        _glowOf(tester).paint.color,
        isSameColorAs(const Color.fromRGBO(120, 180, 255, 0.12)),
      );
    });

    testWidgets('is lit from up and to the left, through all three stops',
        (WidgetTester tester) async {
      // `#a9dcff` daylight → `#1c6fb0` ocean at 55% → `#0c355c` night
      // (`index.html:872`), on a two-circle gradient whose focal point is 4px up
      // and to the left. The whole disc is compared against a reference painted
      // from those three literals, so a change to any one of them — or to the
      // 0.55 stop, or to the focal point that makes the planet look lit rather
      // than flat — moves pixels this test is reading.
      await pumpRadar(tester);
      final RadarPixels frame = await rasteriseRadar(tester);
      final RadarPixels reference = await _render(tester, _paintEarthDisc);

      // Inside the 15px disc, off its antialiased rim. The lit end is only
      // reached at the focal circle, so the first probe is the one that pins
      // `#a9dcff` outright.
      for (final Offset probe in <Offset>[
        radarCentre.translate(-4, -4),
        radarCentre,
        radarCentre.translate(10, 0),
        radarCentre.translate(-9, 5),
        radarCentre.translate(9, 9),
        radarCentre.translate(0, -11),
      ]) {
        _expectPixel(frame, reference, probe, reason: 'Earth at $probe');
      }
    });
  });

  group('the animals\' tokens', () {
    testWidgets('are the same lit navy however big the animal is',
        (WidgetTester tester) async {
      // `#20406e` → `#122a4d` (`index.html:853`), lit from up and to the left
      // like Earth so the tokens belong to the same scene. This is what
      // `specs/02-live-radar.md:28` rests on — the token is why no animal ever
      // looks faded next to a bigger one — so its two ends are worth holding.
      final Asteroid rock = _rock(name: '433 Eros', ld: 5, diaMax: 16800);
      await pumpRadar(
        tester,
        sky: <Asteroid>[rock],
        layers: const RadarLayers(planets: false, rings: false, moon: false),
      );
      final RadarPixels frame = await rasteriseRadar(tester);

      final ({Offset at, double chip}) token = _tokenOf(<Asteroid>[rock], rock.name);
      final RadarPixels reference = await _render(
        tester,
        (Canvas canvas) => _paintToken(canvas, token.at, token.chip),
      );

      // On the axes at 80% of the chip: outside the animal's glyph box (the
      // emoji is drawn at `chip / 0.72`, so its box reaches 69%) and inside the
      // 2px ring stroke at the rim. The four points sit at four different
      // distances from the off-centre focal point, so between them they sample
      // the gradient rather than one band of it.
      for (final Offset probe in <Offset>[
        token.at.translate(-token.chip * 0.8, 0),
        token.at.translate(token.chip * 0.8, 0),
        token.at.translate(0, -token.chip * 0.8),
        token.at.translate(0, token.chip * 0.8),
      ]) {
        _expectPixel(frame, reference, probe, reason: 'token at $probe');
      }
    });
  });

  group('the labels', () {
    testWidgets('the rings and Earth say their names in muted, at two alphas',
        (WidgetTester tester) async {
      // `--muted` `#93a8ca` at `.55` on the ring labels (`index.html:830`) and
      // `.85` on "Earth" (`index.html:875`) — the same colour twice, and the
      // gap between the two alphas is the reading order of the screen: the
      // planet at the centre is what the child is looking at, and the rings are
      // the scale it is measured on. Flatten them to one value and the field
      // loses its foreground.
      await pumpRadar(tester, layers: const RadarLayers(planets: false, moon: false));
      final RadarPixels frame = await rasteriseRadar(tester);
      final RadarPixels background = await _radarBackground(tester);

      final List<({Offset at, double width})> centred = <({Offset at, double width})>[
        for (final ({Offset at, double width}) label in radarParagraphs(tester))
          if ((label.at.dx + label.width / 2 - radarCentre.dx).abs() < 1) label,
      ];
      // Six ring labels above the planet and "Earth" below it — every string on
      // a sky with no Moon, no planets and no animals.
      final List<({Offset at, double width})> rings = <({Offset at, double width})>[
        for (final ({Offset at, double width}) label in centred)
          if (label.at.dy < radarCentre.dy) label,
      ];
      expect(rings, hasLength(6));
      expect(centred, hasLength(7));

      for (final ({Offset at, double width}) ring in rings) {
        _expectInk(
          frame,
          background,
          ring,
          const Color.fromRGBO(147, 168, 202, 0.55),
          reason: 'ring label at ${ring.at}',
        );
      }
      _expectInk(
        frame,
        background,
        centred.singleWhere(
          (({Offset at, double width}) l) => l.at.dy > radarCentre.dy,
        ),
        const Color.fromRGBO(147, 168, 202, 0.85),
        reason: '"Earth"',
      );
    });

    testWidgets('the Moon says its name brighter than the rings do',
        (WidgetTester tester) async {
      // `rgba(147,168,202,.8)` (`index.html:839`) — `--muted` a third time, and
      // a third alpha. The Moon is an object out there, not a measuring mark, so
      // it is named more brightly than the rings it rides among.
      await pumpRadar(
        tester,
        layers: const RadarLayers(planets: false, rings: false),
      );
      final RadarPixels frame = await rasteriseRadar(tester);
      final RadarPixels background = await _radarBackground(tester);

      // The one label on this sky that is not centred on Earth.
      final ({Offset at, double width}) moon = radarParagraphs(tester).singleWhere(
        (({Offset at, double width}) l) =>
            (l.at.dx + l.width / 2 - radarCentre.dx).abs() >= 1,
      );

      _expectInk(
        frame,
        background,
        moon,
        const Color.fromRGBO(147, 168, 202, 0.8),
        reason: '"Moon"',
      );
    });

    testWidgets('an animal waving is named in warm amber, the tapped one in white',
        (WidgetTester tester) async {
      // `rgba(255,206,140,.9)` for a close flyby and flat white for the selected
      // animal (`index.html:865-867`). The amber is the app's greeting colour
      // (`CLAUDE.md:64`) and the white is the only colour on this field that
      // means nothing else, which is what lets it mean "this one".
      final Asteroid waving = _rock(name: '2020 AA', ld: 5, hazardous: true);
      final Asteroid tapped = _rock(name: '2021 BB', ld: 9, diaMax: 900);
      final List<Asteroid> sky = <Asteroid>[waving, tapped];
      await pumpRadar(
        tester,
        sky: sky,
        selected: tapped,
        layers: const RadarLayers(planets: false, rings: false, moon: false),
      );
      final RadarPixels frame = await rasteriseRadar(tester);
      final RadarPixels background = await _radarBackground(tester);

      _expectInk(
        frame,
        background,
        _nameAbove(tester, _tokenOf(sky, waving.name)),
        const Color.fromRGBO(255, 206, 140, 0.9),
        reason: 'a close flyby\'s name',
      );
      _expectInk(
        frame,
        background,
        _nameAbove(tester, _tokenOf(sky, tapped.name)),
        const Color(0xFFFFFFFF),
        reason: 'the selected animal\'s name',
      );
    });

    testWidgets('the animal and its wave are drawn opaque, whatever glyph arrives',
        (WidgetTester tester) async {
      // A colour emoji carries its own bitmap and ignores the fill, so this
      // colour is only ever seen on a **monochrome fallback glyph** — which is
      // precisely why it must be pinned rather than left to whatever a
      // [TextStyle] happens to default to. `flutter_test` renders exactly that
      // fallback, so this test sees the case a phone without the emoji font
      // would. Faded would break `specs/02-live-radar.md:28`.
      final Asteroid waving = _rock(name: '2020 AA', ld: 5, hazardous: true);
      await pumpRadar(
        tester,
        sky: <Asteroid>[waving],
        layers: const RadarLayers(planets: false, rings: false, moon: false),
      );
      final RadarPixels frame = await rasteriseRadar(tester);

      final ({Offset at, double chip}) token = _tokenOf(<Asteroid>[waving], waving.name);
      // The two glyphs on the token, found by size: the animal is drawn at
      // `emojiSize` and the wave at 55% of it (`_waveScale`).
      final List<({Offset at, double width})> glyphs = <({Offset at, double width})>[
        for (final ({Offset at, double width}) label in radarParagraphs(tester))
          if ((label.at - token.at).distance < token.chip * 2) label,
      ];
      expect(glyphs, hasLength(2), reason: 'the animal and its wave');

      for (final ({Offset at, double width}) glyph in glyphs) {
        _expectOpaqueWhiteGlyph(frame, glyph);
      }
    });
  });
}

// ── The prototype's own literals, painted by the test rather than by the app.
//
// Everything below is written out from `index.html` a second time, on purpose.
// The app's copy is what is under test; this copy is what it is tested against.

/// `.radarwrap`'s background (`index.html:170`) — `#0c2044` at 50%/44%, out to
/// `#040a17` at 72% of the distance to the farthest corner.
void _paintSpace(Canvas canvas) {
  final Offset heart = Offset(radarSize.width * 0.5, radarSize.height * 0.44);
  final double toFarthestCorner = math.sqrt(
    math.pow(radarSize.width * 0.5, 2) + math.pow(radarSize.height * 0.56, 2),
  );

  canvas.drawRect(
    Offset.zero & radarSize,
    Paint()
      ..shader = ui.Gradient.radial(
        heart,
        toFarthestCorner,
        const <Color>[Color(0xFF0C2044), Color(0xFF040A17)],
        const <double>[0, 0.72],
      ),
  );
}

/// The planet itself (`index.html:872`): a 15px disc on a two-circle gradient
/// from a focal point 4px up and to the left.
void _paintEarthDisc(Canvas canvas) {
  canvas.drawCircle(
    radarCentre,
    15,
    Paint()
      ..shader = ui.Gradient.radial(
        radarCentre,
        16,
        const <Color>[Color(0xFFA9DCFF), Color(0xFF1C6FB0), Color(0xFF0C355C)],
        const <double>[0, 0.55, 1],
        TileMode.clamp,
        null,
        radarCentre.translate(-4, -4),
        2,
      ),
  );
}

/// Earth's atmosphere (`index.html:873`), replayed at the radius the frame under
/// test actually drew — it breathes on a sine, so the reference has to be told.
void _paintGlow(Canvas canvas, double radius) => canvas.drawCircle(
  radarCentre,
  radius,
  Paint()..color = const Color.fromRGBO(120, 180, 255, 0.12),
);

/// One animal's token (`index.html:853`), lit from up and to the left.
void _paintToken(Canvas canvas, Offset at, double chip) {
  canvas.drawCircle(
    at,
    chip,
    Paint()
      ..shader = ui.Gradient.radial(
        at,
        chip,
        const <Color>[Color(0xFF20406E), Color(0xFF122A4D)],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        at.translate(-chip * 0.3, -chip * 0.3),
        chip * 0.2,
      ),
  );
}

/// Everything a label can be sitting on: deep space, and Earth's glow over it.
///
/// Rebuilt from the literals above rather than probed off the frame beside the
/// label, because the space gradient is brightest at the middle of the screen —
/// a background sampled a few pixels to one side of a glyph is a different
/// colour from the one under it, and "a few pixels" is the width of the answer.
Future<RadarPixels> _radarBackground(WidgetTester tester) {
  final double glow = _glowOf(tester).radius;
  return _render(tester, (Canvas canvas) {
    _paintSpace(canvas);
    _paintGlow(canvas, glow);
  });
}

/// A reference frame, painted by the test at the size of the real one.
Future<RadarPixels> _render(
  WidgetTester tester,
  void Function(Canvas canvas) draw,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  return imagePixels(
    tester,
    recorder.endRecording().toImageSync(
      radarSize.width.round(),
      radarSize.height.round(),
    ),
  );
}

// ── Reading the frame.

/// The frame and the reference agree at [probe].
///
/// A tolerance of one, because two rasters of the same gradient can round a
/// channel apart; a real colour change moves a channel by far more (the
/// tightest pairing here, the Moon's `.30` ring against its `.28` track, is
/// four).
void _expectPixel(
  RadarPixels frame,
  RadarPixels reference,
  Offset probe, {
  required String reason,
}) {
  final Color actual = frame.at(probe.dx, probe.dy);
  final Color expected = reference.at(probe.dx, probe.dy);
  expect(
    <int>[
      (actual.r * 255).round(),
      (actual.g * 255).round(),
      (actual.b * 255).round(),
      (actual.a * 255).round(),
    ],
    <Matcher>[
      closeTo((expected.r * 255).round(), 1),
      closeTo((expected.g * 255).round(), 1),
      closeTo((expected.b * 255).round(), 1),
      closeTo((expected.a * 255).round(), 1),
    ],
    reason: reason,
  );
}

/// A label's ink is [colour] composited over the background it was drawn on.
///
/// Probed inside the **last** glyph of the string, which is a letter in every
/// label the radar draws — the first is a `🌙` on one of them, and an emoji is
/// the one glyph `flutter_test` does not render as a solid box.
void _expectInk(
  RadarPixels frame,
  RadarPixels background,
  ({Offset at, double width}) label,
  Color colour, {
  required String reason,
}) {
  final Offset ink = Offset(label.at.dx + label.width - 4, label.at.dy + 5);
  final Color actual = frame.at(ink.dx, ink.dy);
  final Color expected = Color.alphaBlend(
    colour,
    background.at(ink.dx, ink.dy),
  );

  expect(
    <int>[
      (actual.r * 255).round(),
      (actual.g * 255).round(),
      (actual.b * 255).round(),
    ],
    <Matcher>[
      closeTo((expected.r * 255).round(), 1),
      closeTo((expected.g * 255).round(), 1),
      closeTo((expected.b * 255).round(), 1),
    ],
    reason: reason,
  );
}

/// A glyph is inked in flat, opaque white.
///
/// **Scanned rather than probed at a point**, because this is the one label on
/// the radar that is *not* a solid box: `flutter_test` has no emoji font, so 🐋
/// and 👋 arrive as the fallback's hollow outline and the middle of the box is
/// background. Which pixels are inked is the fallback font's business and not
/// worth pinning; that every inked one is `#fff` is this test's business.
void _expectOpaqueWhiteGlyph(
  RadarPixels frame,
  ({Offset at, double width}) glyph,
) {
  final List<Color> ink = <Color>[];
  for (double dx = 0; dx < glyph.width; dx++) {
    for (double dy = 0; dy < glyph.width; dy++) {
      final Color pixel = frame.at(glyph.at.dx + dx, glyph.at.dy + dy);
      if (pixel == const Color(0xFFFFFFFF)) ink.add(pixel);
    }
  }

  expect(
    ink,
    isNotEmpty,
    reason: 'the glyph at ${glyph.at} is drawn in something other than white — '
        'a faded animal is what `specs/02-live-radar.md:28` forbids',
  );
}

/// The paths drawn *around Earth* — the distance rings, and the Moon's track
/// when the rings are off — innermost first.
List<({Path path, Paint paint})> _ringsOf(WidgetTester tester) =>
    <({Path path, Paint paint})>[
      for (final ({Path path, Paint paint}) drawn in radarPaths(tester))
        if ((drawn.path.getBounds().center - radarCentre).distance < 1) drawn,
    ];

/// Earth's atmosphere: the one circle at the centre with no shader on it — the
/// planet itself is a gradient and the rings are paths.
({Offset at, double radius, Paint paint}) _glowOf(WidgetTester tester) =>
    radarCircles(tester).firstWhere(
      (({Offset at, double radius, Paint paint}) c) =>
          c.at == radarCentre && c.paint.shader == null,
    );

/// Where the painter puts [name]'s animal, and how big its token is — asked of
/// [RadarOrbits] the same way the painter asks it, so a test can find an
/// animal's own marks without counting circles.
///
/// **[sky] must be the whole sky, in the order it was mounted in.** The seed is
/// a pure function of the list *and its order* (`RadarOrbits.seed`), so re-seeding
/// one rock on its own answers for a different sky and lands the token somewhere
/// the frame never drew one.
({Offset at, double chip}) _tokenOf(List<Asteroid> sky, String name) {
  final RadarOrbits orbits = RadarOrbits.seed(sky);
  final RadarOrbit orbit = orbits.orbits.singleWhere(
    (RadarOrbit o) => o.asteroid.name == name,
  );
  return (
    at: orbits.positionOf(
      orbit,
      geometry: const RadarGeometry(size: radarSize, maxLd: 60),
      zoom: 1,
      viewRot: 0,
    ),
    chip: orbit.chipRadius,
  );
}

/// The name drawn above [token] — found by position, since a [ui.Paragraph]
/// cannot be asked what it says.
({Offset at, double width}) _nameAbove(
  WidgetTester tester,
  ({Offset at, double chip}) token,
) => radarParagraphs(tester).singleWhere(
  (({Offset at, double width}) label) =>
      (label.at.dx + label.width / 2 - token.at.dx).abs() < 1 &&
      label.at.dy < token.at.dy - token.chip,
);

/// A rock with only what the radar reads: where it orbits, and how big it is.
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

