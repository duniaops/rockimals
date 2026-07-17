import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/planet_painters.dart';

/// What the decorative backdrop's six bodies actually put on the screen.
///
/// **Checked against the prototype's own output, not against a reading of it.**
/// Every expectation below — the draw order, the radii, the band offsets, the
/// ring geometry — was captured by slicing `index.html:741-788` out of the file
/// and `eval`-ing the six painters over a recording canvas stub at
/// `(x, y, r) = (100, 100, 20)`. That is the technique this plan has used since
/// the FALLBACK item, for the reason it keeps earning: a table of hand-copied
/// coordinates is exactly where a careful read fails silently, and a planet that
/// is subtly wrong does not throw — it just looks a bit off, forever.
///
/// **There is no golden file here, and the item's "matches the prototype's look"
/// cannot be met literally.** A byte-comparison would need the prototype
/// rasterised, which needs a browser; this machine has Node and no browser (and
/// no Xcode or Android SDK — see the plan's human-gated item). Self-generated
/// goldens would pin *this* port's output against itself and prove nothing about
/// the prototype, so what is asserted instead is the two halves that can be
/// honest: the recorded draw calls, which are the prototype's own numbers, and
/// rasterised pixel probes for the things that exist only once the calls are
/// composited — Saturn's occlusion, Jupiter's clipped bands, the glow's ramp.
void main() {
  group('paintGlow', () {
    testWidgets('fills 2.3r from one flat core out to nothing', (tester) async {
      // `createRadialGradient(x, y, r*0.6, x, y, r*2.3)` filled over
      // `arc(x, y, r*2.3)` (`index.html:750-752`) — the gradient and the disc
      // share an edge, so the glow ends exactly where it stops being drawn
      // rather than being cut off mid-ramp.
      await _paint(tester, (Canvas c, Offset at, double r) {
        paintGlow(c, at, r, colour: _neptuneGlow, alpha: 0.6);
      });

      expect(_painterOf(tester), paints..circle(x: 100, y: 100, radius: 46));
    });

    testWidgets('folds globalAlpha into the stops', (tester) async {
      // `c.globalAlpha = a` around a single source-over fill (`index.html:752`)
      // scales the source's alpha and nothing else, so scaling every stop's
      // alpha by the same constant is arithmetically identical — and costs no
      // `saveLayer`. Pinned at the core, which is flat colour: 0.3 × 0.6 = 0.18
      // of `rgb(60,110,230)` over black.
      await _paint(tester, (Canvas c, Offset at, double r) {
        paintGlow(c, at, r, colour: _neptuneGlow, alpha: 0.6);
      });

      _expectPixel(
        await _pixels(tester),
        const Offset(100, 100),
        const Color.fromARGB(255, 11, 20, 41),
      );
    });

    testWidgets('fades along one hue instead of dragging through black', (tester) async {
      // The deviation from `index.html:751`, and the reason it is not optional.
      // Canvas interpolates gradient stops in *premultiplied* space, where
      // `rgb(60,110,230)` → `rgba(0,0,0,0)` holds its colour and drops its
      // alpha. Skia interpolates *unpremultiplied*, where that same pair walks
      // the RGB down to black as it fades and leaves a dirty ring. Ending on the
      // glow's own colour at zero alpha makes Skia reproduce canvas exactly.
      //
      // Probed halfway along the ramp (d = 29, i.e. t = (29-12)/(46-12) = 0.5),
      // where alpha is 0.09 and the two behaviours differ by a clean factor of
      // two: `0.09 × (60,110,230)` here, against `0.09 × (30,55,115)` if the
      // far stop were the literal transparent black.
      await _paint(tester, (Canvas c, Offset at, double r) {
        paintGlow(c, at, r, colour: _neptuneGlow, alpha: 0.6);
      });

      _expectPixel(
        await _pixels(tester),
        const Offset(129, 100),
        const Color.fromARGB(255, 5, 10, 21),
      );
    });
  });

  group('paintSphere', () {
    testWidgets('draws the body, then the shadow over it', (tester) async {
      // Two fills of radius r (`index.html:744`, `747`). The second is the
      // terminator and must land on top, or the planet is a flat disc.
      await _paint(tester, (Canvas c, Offset at, double r) {
        paintSphere(c, at, r, lit: _mercuryLit, mid: _mercuryMid, dark: _mercuryDark);
      });

      expect(
        _painterOf(tester),
        paints
          ..circle(x: 100, y: 100, radius: 20)
          ..circle(x: 100, y: 100, radius: 20),
      );
      expect(_calls(tester).where((_Call c) => c.method == #drawCircle), hasLength(2));
    });

    testWidgets('lights every planet from the upper left, like Earth', (tester) async {
      // `createRadialGradient(x-r*.35, y-r*.35, …)` (`index.html:742`) plus a
      // shadow pooling at `+r*.55` (`index.html:746`). The direction is not
      // arbitrary: Earth and the animal tokens are lit from the same corner
      // (`radar_painter.dart`), so one imaginary sun lights the whole field. A
      // planet lit from the other side would read as a sticker on the scene
      // rather than a thing in it.
      await _paint(tester, (Canvas c, Offset at, double r) {
        paintSphere(c, at, r, lit: _mercuryLit, mid: _mercuryMid, dark: _mercuryDark);
      });

      // Two points mirrored through the centre, so the only thing that can
      // separate them is which way the light falls.
      final _Pixels pixels = await _pixels(tester);
      final Color lit = pixels.at(const Offset(95, 95));
      final Color shadowed = pixels.at(const Offset(112, 112));

      expect(_luma(lit), greaterThan(_luma(shadowed) * 1.5));
    });
  });

  group('the six planets', () {
    testWidgets('each glows, then is a sphere, and says its name', (tester) async {
      // The shared shape of `index.html:759-788`: a halo at 2.3r, the body at r,
      // the terminator at r, then a 9px name 11px under the rim.
      for (final (String name, void Function(Canvas, Offset, double) draw)
          in <(String, void Function(Canvas, Offset, double))>[
        ('Venus', paintVenus),
        ('Neptune', paintNeptune),
      ]) {
        await _paint(tester, draw);

        expect(
          _painterOf(tester),
          paints
            ..circle(x: 100, y: 100, radius: 46)
            ..circle(x: 100, y: 100, radius: 20)
            ..circle(x: 100, y: 100, radius: 20)
            ..paragraph(offset: _labelOffset(name, 131)),
        );
      }
    });

    testWidgets('Mercury alone has no name under it', (tester) async {
      // `index.html:759` — the only one of the six that never calls `pLabel`,
      // and the omission is deliberate rather than an oversight: at `r: 6` it is
      // the smallest thing in the backdrop, and a 9px caption under a 6px dot
      // would be a label for nothing.
      await _paint(tester, paintMercury);

      expect(
        _calls(tester).where((_Call c) => c.method == #drawParagraph),
        isEmpty,
      );
    });

    testWidgets('hangs every name 11px under the rim, and Saturn 11px under its rings',
        (tester) async {
      // `fillText(name, x, y + r + 11)` (`index.html:757`) — except Saturn,
      // which passes `r * 1.1` (`index.html:787`) so its name clears the rings
      // instead of being struck through by them. At r = 20 that is 133, not 131.
      await _paint(tester, paintJupiter);
      expect(_painterOf(tester), paints..paragraph(offset: _labelOffset('Jupiter', 131)));

      await _paint(tester, paintSaturn);
      expect(_painterOf(tester), paints..paragraph(offset: _labelOffset('Saturn', 133)));
    });
  });

  group('paintSun', () {
    testWidgets('glows, then is a disc — and never a sphere', (tester) async {
      // `index.html:802-805`. **Two circles where every planet draws three**,
      // and the missing one is the point: [paintSphere]'s second pass is the
      // terminator, the shadow that pools on a lit body's far side. The Sun is
      // what is doing the lighting, so it has no far side — a Sun with a
      // terminator would be a body lit by some *other* sun, which is the one
      // thing on this screen there cannot be.
      await _paint(tester, paintSun);

      expect(
        _painterOf(tester),
        paints
          ..circle(x: 100, y: 100, radius: 46)
          ..circle(x: 100, y: 100, radius: 20),
      );
      expect(
        _calls(tester).where((_Call c) => c.method == #drawCircle),
        hasLength(2),
        reason: 'a glow and a disc — no terminator',
      );
    });

    testWidgets('hangs its name 12px under the rim, not the planets\' 11', (tester) async {
      // `fillText('Sun', sx, sy + sr + 12)` (`index.html:806`) — one pixel lower
      // than `pLabel`'s 11 (`index.html:757`), because `drawPlanets` writes the
      // Sun's caption out longhand instead of calling `pLabel`. A pixel is
      // nothing to look at and everything to port: routing it through the shared
      // helper would also hand it the planets' cooler grey, and the difference
      // between the two colours is the only thing marking the Sun as the warm
      // object in a blue scene.
      await _paint(tester, paintSun);

      expect(_painterOf(tester), paints..paragraph(offset: _labelOffset('Sun', 132)));
    });

    testWidgets('burns white off-centre and cools to orange at the rim', (tester) async {
      // `createRadialGradient(sx-6, sy-6, 4, sx, sy, sr)` with `#fff7db` →
      // `#ffd166` → `#f2731d` (`index.html:803-804`).
      //
      // **The 6px offset is flat, not a fraction of the radius** — the one place
      // the backdrop breaks its own rule that everything scales — so at r = 20
      // the white core sits at (94, 94) and the disc is visibly lit from the
      // upper left, like everything else on this screen.
      await _paint(tester, paintSun);
      final _Pixels px = await _pixels(tester);

      // The core: inside the 4px focal circle at (94, 94), so it is flat
      // `#fff7db` and nothing else.
      _expectPixel(px, const Offset(94, 94), const Color(0xFFFFF7DB));

      // The rim, just inside the 20px disc on the far side from the core: the
      // ramp has run all the way to `#f2731d`.
      final Color rim = px.at(const Offset(112, 112));
      expect(rim.r, greaterThan(rim.g), reason: 'orange');
      expect(rim.g, greaterThan(rim.b));
      expect(rim.b, lessThan(0.35), reason: 'cooled well past the #ffd166 midpoint');

      // And the core really is off-centre: the exact middle of the disc is
      // already past the white and into the body colour.
      expect(_luma(px.at(const Offset(94, 94))), greaterThan(_luma(px.at(_at))));
    });
  });

  group('paintJupiter', () {
    testWidgets('rules five bands across the planet, then the red spot', (tester) async {
      // `index.html:773-775`. The offsets are the prototype's own literals and
      // are neither evenly spaced nor symmetrical about the equator — the
      // irregularity is what stops Jupiter reading as a barcode, so it is ported
      // as a table rather than generated from a step.
      await _paint(tester, paintJupiter);

      final List<Rect> bands = _calls(tester)
          .where((_Call c) => c.method == #drawRect)
          .map((_Call c) => c.args[0] as Rect)
          .toList();

      expect(bands, hasLength(5));
      for (final (int i, double top) in <(int, double)>[
        (0, 85.4),
        (1, 92.2),
        (2, 98.8),
        (3, 105.4),
        (4, 111.4),
      ]) {
        expect(bands[i].top, closeTo(top, 0.001));
        expect(bands[i].left, 80);
        expect(bands[i].width, 40);
        expect(bands[i].height, closeTo(4.4, 0.001));
      }
    });

    testWidgets('clips the bands to the planet rather than across the sky', (tester) async {
      // The one clip on this screen that is load-bearing. Every band is a rect
      // spanning the planet's full width, so its corners reach 1.01r–1.27r —
      // without the clip, Jupiter is a disc with five stripes ruled straight
      // past it into empty space.
      //
      // Probed along the top band's centre line (y = 87.6) at two points that
      // are **both inside the rect** — it spans x 80–120 — but on opposite sides
      // of the planet's rim: x = 100 is 12.4px from centre, x = 118 is 21.9px.
      // Sampling outside the rect would prove nothing at all, since there is no
      // band there to clip.
      await _paint(tester, paintJupiter);
      final _Pixels pixels = await _pixels(tester);

      expect(_luma(pixels.at(const Offset(100, 87.6))), greaterThan(60));
      // Past the rim: the glow's faint tail and nothing else. Unclipped, the
      // band would land here at roughly twice this brightness.
      expect(_luma(pixels.at(const Offset(118, 87.6))), lessThan(25));
      expect(_calls(tester).where((_Call c) => c.method == #clipPath), hasLength(1));
    });

    testWidgets('puts the red spot south-east of centre', (tester) async {
      // `ellipse(x + r*0.28, y + r*0.22, r*0.2, r*0.13)` (`index.html:775`) —
      // 0.54r out at its furthest, so it is the one marking on this planet the
      // clip could not touch.
      await _paint(tester, paintJupiter);
      final _Pixels pixels = await _pixels(tester);

      final Color spot = pixels.at(const Offset(105.6, 104.4));
      expect(spot.r * 255, greaterThan(spot.b * 255 * 1.5));
    });
  });

  group('paintMars', () {
    testWidgets('marks a dark plain and a bright polar cap', (tester) async {
      // `index.html:765-766` — two ellipses on an otherwise plain rust ball, and
      // they pull in opposite directions: the plain is a dark smudge below-left
      // of centre, the cap a white patch up at the pole. Measured against the
      // bare sphere, so each is asserted to *change* its pixel rather than
      // merely to be brighter or darker than some number the test made up.
      await _paint(tester, paintMars);
      final _Pixels marked = await _pixels(tester);

      await _paint(tester, (Canvas c, Offset at, double r) {
        paintSphere(c, at, r, lit: _marsLit, mid: _marsMid, dark: _marsDark);
      });
      final _Pixels bare = await _pixels(tester);

      const Offset cap = Offset(104, 85);
      const Offset plain = Offset(94, 104);

      expect(_luma(marked.at(cap)), greaterThan(_luma(bare.at(cap)) + 100));
      expect(_luma(marked.at(plain)), lessThan(_luma(bare.at(plain)) - 10));
    });

    testWidgets('has a clip that can never fire, at any radius', (tester) async {
      // **Dead, and pinned as dead so the next reader stops looking for the
      // input that triggers it** — the third such on this screen, after the
      // radar's `rr < 7` cull and two of `chipSizeFor`'s four clamps.
      //
      // Both of Mars's markings are already inside the disc: the plain reaches
      // 0.739r and the cap 0.998r. Both bounds are *ratios of r*, so this is not
      // a fact about one size — no radius and no zoom can make the clip remove a
      // pixel. It is ported anyway because it is the prototype's and costs one
      // clip a frame, and because the cap misses the rim by 0.2% of the radius,
      // which is luck rather than design: nudge the cap and the clip starts
      // earning its keep.
      for (final (double cx, double cy, double rx, double ry) in <(double, double, double, double)>[
        (-0.3, 0.2, 0.4, 0.28), // the plain
        (0.2, -0.75, 0.35, 0.2), // the cap
      ]) {
        double furthest = 0;
        for (double t = 0; t < math.pi * 2; t += 0.0005) {
          furthest = math.max(
            furthest,
            Offset(cx + rx * math.cos(t), cy + ry * math.sin(t)).distance,
          );
        }
        expect(furthest, lessThan(1));
      }

      // And it really is still there, doing its nothing.
      await _paint(tester, paintMars);
      expect(_calls(tester).where((_Call c) => c.method == #clipPath), hasLength(1));
    });
  });

  group('paintSaturn', () {
    testWidgets('draws the back of the ring, then the planet, then the front', (tester) async {
      // **The order is the whole illusion** (`index.html:779-786`). One flat
      // ellipse passes behind the globe and in front of it, so it is drawn as
      // two half-arcs with the sphere painted between them — and the planet
      // hides the middle of the back arc without a mask, a depth buffer, or
      // anything else knowing that occlusion is a concept.
      await _paint(tester, paintSaturn);

      expect(
        _painterOf(tester),
        paints
          ..circle(radius: 46) // the glow
          ..path() // the back of the ring
          ..circle(radius: 20) // the body
          ..circle(radius: 20) // the terminator
          ..path() // the front of the ring
          ..path(), // the thin inner ring, front only
      );
    });

    testWidgets('hides the back arc behind the globe but not beside it', (tester) async {
      // The occlusion itself, rather than the call order that produces it.
      //
      // **Measured against Saturn with its rings taken away** — the bare sphere,
      // same colours, same place. The body is opaque, so anywhere the globe is
      // meant to be in front, the two renders must agree *exactly*; anywhere the
      // ring is meant to be in front, they must not. That is the claim "the
      // rings occlude correctly" states, pinned as an equality rather than as a
      // brightness, which is what makes it bite: reorder the passes and the
      // back arc appears painted across Saturn's face, breaking the first
      // expectation while leaving every other pixel alone.
      await _paint(tester, paintSaturn);
      final _Pixels ringed = await _pixels(tester);

      await _paint(tester, (Canvas c, Offset at, double r) {
        paintSphere(c, at, r, lit: _saturnLit, mid: _saturnMid, dark: _saturnDark);
      });
      final _Pixels bare = await _pixels(tester);

      // t = 3π/2 — the top of the ellipse, 12px from centre, deep inside a 20px
      // planet. The back arc runs through here and must not show.
      final Offset behind = _onRing(3 * math.pi / 2);
      expect((behind - _at).distance, lessThan(_r));
      expect(ringed.at(behind), bare.at(behind));

      // t = π/2 — its mirror, the same 12px in, where the *front* arc crosses
      // the globe and very much must show.
      final Offset across = _onRing(math.pi / 2);
      expect((across - _at).distance, lessThan(_r));
      expect(ringed.at(across), isNot(bare.at(across)));
      expect(_luma(ringed.at(across)), greaterThan(_luma(bare.at(across)) + 40));

      // t = π + 0.4 — the back arc again, out past the rim with nothing to hide
      // behind, so it is on show: `rgba(220,205,165,.5)` over the faint tail of
      // the glow. Without this the first expectation would also pass for a back
      // arc that was simply never drawn.
      final Offset beside = _onRing(math.pi + 0.4);
      expect((beside - _at).distance, greaterThan(_r));
      _expectPixel(ringed, beside, const Color.fromARGB(255, 114, 106, 85), tolerance: 3);
    });

    testWidgets('tilts all three arcs together', (tester) async {
      // They are one object. A tilt that drifted between the passes would tear
      // the ring in half at the planet's edge, so the arcs are pinned to share
      // it — measured as: each path's bounds are those of a -0.38rad ellipse.
      await _paint(tester, paintSaturn);

      final List<Rect> arcs = _calls(tester)
          .where((_Call c) => c.method == #drawPath)
          .map((_Call c) => (c.args[0] as Path).getBounds())
          .toList();

      expect(arcs, hasLength(3));

      // The outer two are one ellipse cut in half, so they are the same size and
      // their bounds mirror through the planet's centre. A tilt applied to only
      // one of them breaks both facts at once.
      expect(arcs[0].width, closeTo(arcs[1].width, 0.1));
      expect(arcs[0].height, closeTo(arcs[1].height, 0.1));
      expect(arcs[0].center.dx + arcs[1].center.dx, closeTo(200, 0.5));
      expect(arcs[0].center.dy + arcs[1].center.dy, closeTo(200, 0.5));

      // And the tilt is actually on. Flat, the outer halves would be `ry` tall —
      // 12px — and the inner one 9.6px; leaning them 0.38rad makes each about
      // 40 and 32. Nothing here would notice a tilt of zero without this.
      for (final Rect arc in arcs) {
        expect(arc.height, greaterThan(30));
      }

      // The two front arcs lean the same way as each other, down and to the
      // right — where the back one, being the opposite half, leans up and left.
      expect(arcs[0].center - _at, _leansUpLeft);
      expect(arcs[1].center - _at, isNot(_leansUpLeft));
      expect(arcs[2].center - _at, isNot(_leansUpLeft));
    });

    testWidgets('strokes the far half dimmer than the near half', (tester) async {
      // `.5` against `.85` (`index.html:779`, `784`) — the far side reads as
      // being in the planet's own shadow, which is what sells the ring as
      // something the light has to get past rather than a hoop drawn round a
      // circle.
      await _paint(tester, paintSaturn);

      final List<Paint> arcs = _calls(tester)
          .where((_Call c) => c.method == #drawPath)
          .map((_Call c) => c.args[1] as Paint)
          .toList();

      expect(arcs[0].color.a, closeTo(0.5, 0.01));
      expect(arcs[1].color.a, closeTo(0.85, 0.01));
      expect(arcs[0].strokeWidth, closeTo(3, 0.001)); // r * 0.15
      expect(arcs[2].strokeWidth, closeTo(1, 0.001)); // r * 0.05, the thin one
    });
  });
}

/// A canvas big enough for the largest planet's glow, with the body at its
/// centre. Every coordinate in this file is relative to `(100, 100)` at `r = 20`
/// — the same probe the Node capture of `index.html:741-788` used, so the two
/// sets of numbers are directly comparable.
const Size _size = Size(200, 200);
const Offset _at = Offset(100, 100);
const double _r = 20;

/// Black, so a pixel probe is reading the planet and not a blend with whatever
/// the radar happens to put behind it. The real backdrop is the radar's space
/// gradient; that is the *next* item's business, and none of these painters
/// knows about it.
const Color _backdrop = Color(0xFF000000);

// The prototype's own literals (`index.html:759`, `761-762`, `781`), restated
// here because the pixel probes need a bare sphere in the same colours as the
// planet they are measuring against. Their transcription is pinned by the Node
// capture this file's header describes, not by these copies.
const Color _neptuneGlow = Color.fromRGBO(60, 110, 230, 0.3);
const Color _mercuryLit = Color(0xFFD2D2D6);
const Color _mercuryMid = Color(0xFF8F8F96);
const Color _mercuryDark = Color(0xFF4A4A52);
const Color _marsLit = Color(0xFFF0A878);
const Color _marsMid = Color(0xFFD1440E);
const Color _marsDark = Color(0xFF7A2408);
const Color _saturnLit = Color(0xFFF4E6C4);
const Color _saturnMid = Color(0xFFD9BE86);
const Color _saturnDark = Color(0xFF8F7440);

/// Which half of the tilted ring a bounding box belongs to.
final Matcher _leansUpLeft = predicate<Offset>(
  (Offset o) => o.dx < 0 && o.dy < 0,
  'leans up and to the left of the planet',
);

/// A point on Saturn's outer ring at parameter [t] — the prototype's own
/// `ellipse(x, y, r*1.95, r*0.6, -0.38, …)` (`index.html:780`), evaluated here
/// rather than hard-coded, so the probe points move with the geometry instead of
/// silently pointing at empty space if it ever changes.
Offset _onRing(double t, {double rx = _r * 1.95, double ry = _r * 0.6}) {
  const double tilt = -0.38;
  final double x = rx * math.cos(t);
  final double y = ry * math.sin(t);
  return _at.translate(
    x * math.cos(tilt) - y * math.sin(tilt),
    x * math.sin(tilt) + y * math.cos(tilt),
  );
}

/// Where `fillText(name, 100, baseline)` with `textAlign = "center"` puts a
/// paragraph's top-left corner — which is what the engine records.
Offset _labelOffset(String name, double baseline) {
  final TextPainter measured = TextPainter(
    text: TextSpan(
      text: name,
      style: const TextStyle(fontSize: 9, color: Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  return Offset(
    100 - measured.width / 2,
    baseline - measured.computeDistanceToActualBaseline(TextBaseline.alphabetic),
  );
}

double _luma(Color c) => 0.2126 * c.r * 255 + 0.7152 * c.g * 255 + 0.0722 * c.b * 255;

void _expectPixel(_Pixels pixels, Offset at, Color expected, {double tolerance = 2}) {
  final Color actual = pixels.at(at);
  expect(actual.a, closeTo(expected.a, 0.01), reason: 'alpha at $at');
  for (final (String channel, double got, double want) in <(String, double, double)>[
    ('red', actual.r * 255, expected.r * 255),
    ('green', actual.g * 255, expected.g * 255),
    ('blue', actual.b * 255, expected.b * 255),
  ]) {
    expect(got, closeTo(want, tolerance), reason: '$channel at $at');
  }
}

Future<void> _paint(
  WidgetTester tester,
  void Function(Canvas canvas, Offset at, double radius) draw,
) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      child: ColoredBox(
        color: _backdrop,
        child: CustomPaint(key: UniqueKey(), painter: _Planet(draw), size: _size),
      ),
    ),
  );
}

RenderCustomPaint _painterOf(WidgetTester tester) =>
    tester.renderObject(find.byType(CustomPaint));

typedef _Call = ({Symbol method, List<dynamic> args});

/// Every canvas call the painter recorded, in order.
List<_Call> _calls(WidgetTester tester) {
  final List<_Call> calls = <_Call>[];
  expect(
    _painterOf(tester),
    paints
      ..everything((Symbol method, List<dynamic> arguments) {
        calls.add((method: method, args: arguments));
        return true;
      }),
  );
  return calls;
}

/// The rendered frame, read back from the engine — a real rasterisation through
/// `flutter_tester`, the same painting pipeline a phone runs. `toImage` must go
/// through [WidgetTester.runAsync] because a `testWidgets` body runs in a
/// fake-async zone where a future waiting on the real engine never completes.
Future<_Pixels> _pixels(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  );
  final ui.Image image = (await tester.runAsync<ui.Image>(boundary.toImage))!;
  final ByteData data = (await tester.runAsync<ByteData?>(image.toByteData))!;
  return _Pixels(data, image.width);
}

class _Pixels {
  const _Pixels(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  Color at(Offset p) {
    final int i = ((p.dy.round() * _width) + p.dx.round()) * 4;
    return Color.fromARGB(
      _rgba.getUint8(i + 3),
      _rgba.getUint8(i),
      _rgba.getUint8(i + 1),
      _rgba.getUint8(i + 2),
    );
  }
}

class _Planet extends CustomPainter {
  const _Planet(this.draw);

  final void Function(Canvas canvas, Offset at, double radius) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, _at, _r);

  @override
  bool shouldRepaint(_Planet oldDelegate) => true;
}
