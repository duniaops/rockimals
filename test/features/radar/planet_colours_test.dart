import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/planet_painters.dart';
import 'package:rockimals/features/radar/radar_labels.dart';

import '../../support/radar_frame.dart';

/// Every colour in the planet backdrop, pinned against `index.html`'s literals.
///
/// **Why this file exists when `planet_painters_test.dart` already probes
/// pixels.** That suite pins *structure* — draw order, radii, band offsets, ring
/// geometry, occlusion — and its handful of colour probes were chosen to prove
/// specific claims (the glow folds its alpha, the Sun's core is off-centre),
/// not to cover the palette. Four mutations run against it on 2026-07-18 all
/// survived the whole `test/features/radar` suite: `_planetLabelColour` `.72` →
/// `.60`, `_sunLabelColour` `.8` → `.6`, `_neptuneMid` `#3a5ed8` → `#3a5edc`,
/// `_venusMid` `#e2ba79` → `#e2ba7d`. Roughly forty colours were reachable only
/// through a `ui.Gradient` or a `ui.Paragraph`, where no `Paint.color` is left
/// to read, and a wrong one does not throw — the planet just looks a bit off,
/// forever.
///
/// **The technique is `radar_colours_test.dart`'s, applied one file over.** For
/// each body the test paints a *reference* frame from the prototype's own
/// literals, transcribed from `index.html:741-788` and `801-806` below, and
/// compares it with the frame the real painter renders. Nothing here reads a
/// colour out of `planet_painters.dart`, so the two sides are independent: the
/// implementation can only agree with the reference by holding the prototype's
/// values.
///
/// **Whole frames, not probe points.** The comparison walks all 200×200 pixels
/// rather than a chosen few, because picking probes is exactly where the gap
/// above came from — a colour is covered only if someone thought to aim at it,
/// and the ones nobody aimed at are the ones that drift. Every stop, glow,
/// band, ring arc, marking and label is on the frame, so every one of them is
/// on the assertion.
///
/// The labels are inside the comparison rather than ink-probed separately: the
/// reference draws them through the same [radarLabel] with the prototype's
/// colour, so `_planetLabelColour` and `_sunLabelColour` are pinned by the same
/// walk as the gradients.
void main() {
  group('the backdrop matches the prototype colour for colour', () {
    for (final (
          String name,
          PlanetPainter draw,
          void Function(Canvas) reference,
        )
        in <(String, PlanetPainter, void Function(Canvas))>[
          ('Mercury', paintMercury, _refMercury),
          ('Venus', paintVenus, _refVenus),
          ('Neptune', paintNeptune, _refNeptune),
          ('Mars', paintMars, _refMars),
          ('Jupiter', paintJupiter, _refJupiter),
          ('Saturn', paintSaturn, _refSaturn),
          ('the Sun', paintSun, _refSun),
        ]) {
      testWidgets(name, (WidgetTester tester) async {
        await _paint(tester, draw);

        _expectFrame(
          await rasteriseBoundary(tester),
          await _render(tester, reference),
          reason: name,
        );
      });
    }
  });

  testWidgets('the reference would notice a colour that moved', (
    WidgetTester tester,
  ) async {
    // The pin's own pin. A whole-frame comparison is only worth its runtime if
    // it is tight enough to catch the smallest edit anyone would plausibly
    // make, and the four surviving mutations above were all of exactly this
    // size: one step on one channel. Venus painted with `#e2ba7d` for its mid
    // stop — the real mutation, four units of blue — must fail against the
    // reference, or nothing else in this file means anything.
    await _paint(tester, (
      Canvas canvas,
      Offset at,
      double radius, {
      required bool showLabels,
    }) {
      _refGlow(canvas, const Color.fromRGBO(240, 205, 150, 0.28), 0.6);
      _refSphere(
        canvas,
        const Color(0xFFF7E6BD),
        const Color(0xFFE2BA7D),
        const Color(0xFF9C7B3E),
      );
      _refLabel(canvas, 'Venus', 131, _refPlanetLabel);
    });

    await expectLater(
      () async => _expectFrame(
        await rasteriseBoundary(tester),
        await _render(tester, _refVenus),
        reason: 'Venus with a mutated mid stop',
      ),
      throwsA(isA<TestFailure>()),
    );
  });
}

// ── The prototype's own painters, transcribed from `index.html`.
//
// Deliberately written as the prototype writes them — the same call order, the
// same arithmetic, the same literals inline rather than named — so a reader can
// diff these against the HTML by eye. They are a second implementation, and
// that is the point: two independent transcriptions of one source agree only if
// both are right.

/// `pSphere` (`index.html:741-748`).
void _refSphere(Canvas canvas, Color c1, Color c2, Color c3) {
  canvas.drawCircle(
    _at,
    _r,
    Paint()
      ..shader = ui.Gradient.radial(
        _at,
        _r,
        <Color>[c1, c2, c3],
        const <double>[0, 0.55, 1],
        TileMode.clamp,
        null,
        _at.translate(-_r * 0.35, -_r * 0.35),
        _r * 0.1,
      ),
  );
  canvas.drawCircle(
    _at,
    _r,
    Paint()
      ..shader = ui.Gradient.radial(
        _at,
        _r * 1.1,
        const <Color>[Color.fromRGBO(0, 0, 0, 0), Color.fromRGBO(0, 0, 0, 0.5)],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        _at.translate(_r * 0.55, _r * 0.55),
        _r * 0.15,
      ),
  );
}

/// `pGlow` (`index.html:749-753`).
///
/// The prototype's `globalAlpha = a` and its `rgba(0,0,0,0)` far stop are both
/// spelled the way `paintGlow` spells them, and for the reasons its doc gives:
/// Flutter has no `globalAlpha` short of a `saveLayer`, and canvas's
/// premultiplied gradient interpolation only matches Skia's unpremultiplied one
/// if the far stop keeps the near stop's RGB. Those two deviations are pinned by
/// `planet_painters_test.dart`'s own probes against hand-computed values, so
/// restating them here does not launder them — this file is pinning the
/// *colours* fed through them.
void _refGlow(Canvas canvas, Color colour, double a) {
  canvas.drawCircle(
    _at,
    _r * 2.3,
    Paint()
      ..shader = ui.Gradient.radial(
        _at,
        _r * 2.3,
        <Color>[
          colour.withValues(alpha: colour.a * a),
          colour.withValues(alpha: 0),
        ],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        _at,
        _r * 0.6,
      ),
  );
}

/// `pLabel` (`index.html:754-758`), and `drawPlanets`' longhand copy of it for
/// the Sun (`index.html:806`) — same call, different colour and drop.
void _refLabel(Canvas canvas, String name, double baseline, Color colour) =>
    radarLabel(name, size: 9, colour: colour).paint(canvas, _at.dx, baseline);

/// `rgba(180,196,225,.72)` (`index.html:756`).
const Color _refPlanetLabel = Color.fromRGBO(180, 196, 225, 0.72);

/// Clip to the disc — `c.save(); c.arc(x,y,r); c.clip();` (`index.html:764`,
/// `771`).
void _refClipToDisc(Canvas canvas) {
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _at, radius: _r)));
}

/// `pMercury` (`index.html:759`) — no `pLabel`, alone among the six.
void _refMercury(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(150, 150, 160, 0.22), 0.5);
  _refSphere(
    canvas,
    const Color(0xFFD2D2D6),
    const Color(0xFF8F8F96),
    const Color(0xFF4A4A52),
  );
}

/// `pVenus` (`index.html:760`).
void _refVenus(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(240, 205, 150, 0.28), 0.6);
  _refSphere(
    canvas,
    const Color(0xFFF7E6BD),
    const Color(0xFFE2BA79),
    const Color(0xFF9C7B3E),
  );
  _refLabel(canvas, 'Venus', 131, _refPlanetLabel);
}

/// `pNeptune` (`index.html:761`).
void _refNeptune(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(60, 110, 230, 0.3), 0.6);
  _refSphere(
    canvas,
    const Color(0xFF8FB0FF),
    const Color(0xFF3A5ED8),
    const Color(0xFF1E2F7A),
  );
  _refLabel(canvas, 'Neptune', 131, _refPlanetLabel);
}

/// `pMars` (`index.html:762-768`) — a dark plain and a polar cap over the rust.
void _refMars(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(230, 110, 60, 0.3), 0.6);
  _refSphere(
    canvas,
    const Color(0xFFF0A878),
    const Color(0xFFD1440E),
    const Color(0xFF7A2408),
  );

  _refClipToDisc(canvas);
  canvas.drawOval(
    Rect.fromCenter(
      center: _at.translate(-_r * 0.3, _r * 0.2),
      width: _r * 0.8,
      height: _r * 0.56,
    ),
    Paint()..color = const Color.fromRGBO(120, 45, 15, 0.4),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: _at.translate(_r * 0.2, -_r * 0.75),
      width: _r * 0.7,
      height: _r * 0.4,
    ),
    Paint()..color = const Color.fromRGBO(255, 255, 255, 0.55),
  );
  canvas.restore();

  _refLabel(canvas, 'Mars', 131, _refPlanetLabel);
}

/// `pJupiter` (`index.html:769-776`) — five bands and the Great Red Spot.
void _refJupiter(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(220, 160, 110, 0.26), 0.55);
  _refSphere(
    canvas,
    const Color(0xFFECD0A8),
    const Color(0xFFC98F5A),
    const Color(0xFF7A4A2A),
  );

  _refClipToDisc(canvas);
  for (final (double offset, Color colour) in const <(double, Color)>[
    (-0.62, Color.fromRGBO(120, 70, 40, 0.35)),
    (-0.28, Color.fromRGBO(235, 205, 165, 0.4)),
    (0.05, Color.fromRGBO(150, 90, 55, 0.4)),
    (0.38, Color.fromRGBO(215, 180, 140, 0.32)),
    (0.68, Color.fromRGBO(130, 78, 45, 0.35)),
  ]) {
    canvas.drawRect(
      Rect.fromLTWH(
        _at.dx - _r,
        _at.dy + _r * offset - _r * 0.11,
        _r * 2,
        _r * 0.22,
      ),
      Paint()..color = colour,
    );
  }
  canvas.drawOval(
    Rect.fromCenter(
      center: _at.translate(_r * 0.28, _r * 0.22),
      width: _r * 0.4,
      height: _r * 0.26,
    ),
    Paint()..color = const Color.fromRGBO(200, 80, 50, 0.8),
  );
  canvas.restore();

  _refLabel(canvas, 'Jupiter', 131, _refPlanetLabel);
}

/// `pSaturn` (`index.html:777-788`) — back arc, globe, front arc, inner arc.
void _refSaturn(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(220, 200, 150, 0.26), 0.5);
  _refRingArc(
    canvas,
    rx: _r * 1.95,
    ry: _r * 0.6,
    from: math.pi,
    colour: const Color.fromRGBO(220, 205, 165, 0.5),
    width: _r * 0.15,
  );
  _refSphere(
    canvas,
    const Color(0xFFF4E6C4),
    const Color(0xFFD9BE86),
    const Color(0xFF8F7440),
  );
  _refRingArc(
    canvas,
    rx: _r * 1.95,
    ry: _r * 0.6,
    from: 0,
    colour: const Color.fromRGBO(238, 222, 182, 0.85),
    width: _r * 0.15,
  );
  _refRingArc(
    canvas,
    rx: _r * 1.55,
    ry: _r * 0.48,
    from: 0,
    colour: const Color.fromRGBO(205, 185, 145, 0.55),
    width: _r * 0.05,
  );

  // `pLabel(c, x, y, r*1.1, 'Saturn')` (`index.html:787`) — 100 + 22 + 11.
  _refLabel(canvas, 'Saturn', 133, _refPlanetLabel);
}

/// Half of the `-0.38`-radian ellipse the three ring arcs share
/// (`index.html:780`, `784`, `786`).
void _refRingArc(
  Canvas canvas, {
  required double rx,
  required double ry,
  required double from,
  required Color colour,
  required double width,
}) {
  final Path arc = Path()
    ..addArc(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      from,
      math.pi,
    );

  canvas.drawPath(
    arc.transform((Matrix4.identity()..rotateZ(-0.38)).storage).shift(_at),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = colour,
  );
}

/// The Sun (`index.html:801-806`) — no terminator, and a label 12px down rather
/// than the planets' 11.
void _refSun(Canvas canvas) {
  _refGlow(canvas, const Color.fromRGBO(255, 168, 54, 0.5), 0.95);
  canvas.drawCircle(
    _at,
    _r,
    Paint()
      ..shader = ui.Gradient.radial(
        _at,
        _r,
        const <Color>[Color(0xFFFFF7DB), Color(0xFFFFD166), Color(0xFFF2731D)],
        const <double>[0, 0.42, 1],
        TileMode.clamp,
        null,
        _at.translate(-6, -6),
        4,
      ),
  );
  _refLabel(canvas, 'Sun', 132, const Color.fromRGBO(255, 206, 140, 0.8));
}

// ── The harness.

/// The same field `planet_painters_test.dart` measures on, so a probe quoted in
/// one file's failure means the same point in the other's.
const Size _size = Size(200, 200);
const Offset _at = Offset(100, 100);
const double _r = 20;

/// Black, so every pixel below is the body composited over a known constant
/// rather than over the radar's space gradient, which no painter here knows
/// about.
const Color _backdrop = Color(0xFF000000);

/// The real painter, rendered by the engine at one device pixel per logical one
/// so the image's coordinates are the painter's.
Future<void> _paint(WidgetTester tester, PlanetPainter draw) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      child: ColoredBox(
        color: _backdrop,
        child: CustomPaint(
          key: UniqueKey(),
          painter: _Planet(draw),
          size: _size,
        ),
      ),
    ),
  );
}

/// A reference frame, painted straight onto a recorder — no widget tree needed
/// on this side, only the same backdrop underneath and the same size.
Future<RadarPixels> _render(
  WidgetTester tester,
  void Function(Canvas canvas) draw,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = _backdrop);
  draw(canvas);

  return imagePixels(
    tester,
    recorder.endRecording().toImageSync(
      _size.width.round(),
      _size.height.round(),
    ),
  );
}

/// Every pixel of [frame] against [reference].
///
/// Reports the *first* disagreement with both colours and how many followed, so
/// a failure names a point on the body rather than saying only that two images
/// differ. A tolerance of one absorbs rounding in the read-back; it does not
/// absorb a colour that moved, the smallest of which is a whole channel step
/// (pinned by this file's own mutation test).
void _expectFrame(
  RadarPixels frame,
  RadarPixels reference, {
  required String reason,
}) {
  Offset? first;
  int differing = 0;

  for (int y = 0; y < _size.height; y++) {
    for (int x = 0; x < _size.width; x++) {
      final Color actual = frame.at(x.toDouble(), y.toDouble());
      final Color expected = reference.at(x.toDouble(), y.toDouble());
      if (_apart(actual, expected)) {
        first ??= Offset(x.toDouble(), y.toDouble());
        differing++;
      }
    }
  }

  expect(
    differing,
    0,
    reason:
        '$reason differs from the prototype at $differing pixel(s); '
        'first at $first, where the painter drew '
        '${frame.atPoint(first ?? Offset.zero)} and `index.html` says '
        '${reference.atPoint(first ?? Offset.zero)}',
  );
}

bool _apart(Color a, Color b) =>
    ((a.r - b.r).abs() * 255) > 1 ||
    ((a.g - b.g).abs() * 255) > 1 ||
    ((a.b - b.b).abs() * 255) > 1 ||
    ((a.a - b.a).abs() * 255) > 1;

class _Planet extends CustomPainter {
  const _Planet(this.draw);

  final PlanetPainter draw;

  @override
  void paint(Canvas canvas, Size size) =>
      draw(canvas, _at, _r, showLabels: true);

  @override
  bool shouldRepaint(_Planet oldDelegate) => true;
}
