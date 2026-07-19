import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:rockimals/features/radar/radar_labels.dart';

/// The decorative planet backdrop's six planets and its Sun
/// (`index.html:741-788`, `801-806`).
///
/// **Purely scenery, and that is the whole point of it.** Nothing here is data:
/// the planets are not where they really are, not to scale, and not in the
/// asteroids' plane. They exist so the radar reads as *space* rather than as a
/// diagram — a child should look at this screen and see somewhere, not a chart
/// (`specs/02-live-radar.md:29`). Every real number on the field is Earth, the
/// Moon, the rings, and the animals; the planets are the wallpaper behind them.
///
/// **This file only knows how to draw one body at a given point and size.**
/// Where the bodies are, how they drift, and how they bob is
/// `planet_backdrop.dart`'s — which is exactly the split the prototype makes
/// between its painters and `drawPlanets` (`index.html:798-814`).
///
/// Each painter takes the prototype's own `(c, x, y, r)`, so `PLANETS`' `draw`
/// column ports across as a plain function reference (`PlanetPainter`, in
/// `planet_backdrop.dart`). [paintSun] keeps the same shape for the same
/// reason, even though the Sun is not in that table.

// ── The three shared helpers (`pSphere`, `pGlow`, `pLabel`).

/// A lit sphere: the body every planet is made of (`pSphere`,
/// `index.html:741-748`).
///
/// Two passes, and both are needed to stop it reading as a flat disc — a
/// highlight gradient lighting it from the upper left, then a shadow pooling at
/// the lower right.
void paintSphere(
  Canvas canvas,
  Offset at,
  double radius, {
  required Color lit,
  required Color mid,
  required Color dark,
}) {
  // `createRadialGradient(x-r*.35, y-r*.35, r*.1, x, y, r)` — a two-circle
  // gradient, which Flutter spells as a focal point. Up and to the left, which
  // is where Earth and every animal token are lit from too
  // (`radar_painter.dart`), so the whole field shares one imaginary sun.
  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(
        at,
        radius,
        <Color>[lit, mid, dark],
        const <double>[0, 0.55, 1],
        TileMode.clamp,
        null,
        at.translate(-radius * 0.35, -radius * 0.35),
        radius * 0.1,
      ),
  );

  // The terminator (`index.html:746-747`). Drawn out to 1.1r but filled only to
  // r, so the disc's edge catches the ramp before it reaches full black — the
  // planet's rim stays faintly lit instead of dying into the background.
  //
  // **Both stops are black, so this one needs no `withValues` fix** (see
  // [paintGlow] for the one that does): premultiplied and unpremultiplied
  // interpolation only disagree when the RGB changes along the ramp, and here
  // it does not.
  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(
        at,
        radius * 1.1,
        const <Color>[_shadowClear, _shadowDark],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        at.translate(radius * 0.55, radius * 0.55),
        radius * 0.15,
      ),
  );
}

/// The halo of light around a planet (`pGlow`, `index.html:749-753`) — an
/// atmosphere for the ones that have one, and a lens bloom for the ones that do
/// not. Earth gets the same treatment on the layer above (`index.html:873`).
///
/// **Two deliberate deviations, both of which make Flutter agree with canvas
/// rather than disagree.**
///
/// 1. **[alpha] is folded into the stops instead of set as a `globalAlpha`.**
///    Flutter's nearest equivalent is a `saveLayer`, which would cost seven of
///    them per frame (six planets and the Sun) for a result that is arithmetically
///    identical: `globalAlpha` scales the source's alpha before a source-over
///    composite, and scaling every stop's alpha scales the interpolated alpha by
///    the same constant while leaving RGB alone.
/// 2. **The far stop is [colour] at zero alpha, not the transparent black
///    `index.html:751` writes.** The two are the same colour — both premultiply
///    to nothing — but they do not ramp the same way. Canvas interpolates
///    gradients in *premultiplied* space, where this ramp holds one RGB and
///    fades its alpha; Skia interpolates in *unpremultiplied* space, where a
///    literal `rgba(0,0,0,0)` endpoint drags the RGB towards black on the way
///    out and rings the glow with grime. Ending on the same RGB at zero alpha
///    makes the unpremultiplied ramp reproduce the premultiplied one exactly.
void paintGlow(
  Canvas canvas,
  Offset at,
  double radius, {
  required Color colour,
  required double alpha,
}) {
  final double outer = radius * 2.3;

  canvas.drawCircle(
    at,
    outer,
    Paint()
      ..shader = ui.Gradient.radial(
        at,
        outer,
        <Color>[
          colour.withValues(alpha: colour.a * alpha),
          colour.withValues(alpha: 0),
        ],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        // Concentric with the outer circle rather than offset — the glow is
        // even all round, unlike the sphere it sits behind. The inner 0.6r is
        // flat colour, so the ramp starts at the planet's shoulder and not at
        // its centre, where it would be covered anyway.
        at,
        radius * 0.6,
      ),
  );
}

/// A planet's name, under it (`pLabel`, `index.html:754-758`).
///
/// **[showLabels] is the prototype's `if (!Radar.showLabels) return` at the top
/// of `pLabel`** (`index.html:755`) — the Labels chip gates the planets' names
/// on the same flag as the animals' and the Sun's, one chip over all three
/// layers. When it is off, this draws nothing, so the caller can pass the flag
/// straight through rather than wrapping every call in an `if`.
void paintPlanetLabel(
  Canvas canvas,
  Offset at,
  double radius,
  String name, {
  required bool showLabels,
}) {
  if (!showLabels) return;
  radarLabel(
    name,
    size: 9,
    colour: _planetLabelColour,
  ).paint(canvas, at.dx, at.dy + radius + 11);
}

// ── The six planets, in the prototype's own order (`index.html:759-788`).

/// **The only planet with no name under it** (`index.html:759`), and the
/// omission is deliberate rather than an oversight: at `r: 6` Mercury is the
/// smallest thing in the backdrop, and a 9px label under a 6px dot would read as
/// a caption for nothing. It is a grey speck near the Sun, which is what
/// Mercury is.
///
/// **It still takes [showLabels]** — to match [PlanetPainter] so the table ports
/// as a plain reference — and ignores it, having no label to switch off.
void paintMercury(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _mercuryGlow, alpha: 0.5);
  paintSphere(
    canvas,
    at,
    radius,
    lit: _mercuryLit,
    mid: _mercuryMid,
    dark: _mercuryDark,
  );
}

void paintVenus(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _venusGlow, alpha: 0.6);
  paintSphere(
    canvas,
    at,
    radius,
    lit: _venusLit,
    mid: _venusMid,
    dark: _venusDark,
  );
  paintPlanetLabel(canvas, at, radius, 'Venus', showLabels: showLabels);
}

void paintNeptune(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _neptuneGlow, alpha: 0.6);
  paintSphere(
    canvas,
    at,
    radius,
    lit: _neptuneLit,
    mid: _neptuneMid,
    dark: _neptuneDark,
  );
  paintPlanetLabel(canvas, at, radius, 'Neptune', showLabels: showLabels);
}

/// Rust, a dark plain, and a polar cap (`index.html:762-768`).
///
/// **Mars's clip is dead, and this is the third time on this screen** (the
/// radar's `rr < 7` cull and two of `chipSizeFor`'s four clamps are the others).
/// Both markings are already inside the disc at every radius — the plain reaches
/// `0.739r` and the cap `0.998r` — so the `save`/`clip`/`restore` can never
/// remove a pixel, at any size or zoom. It is ported anyway, because it is the
/// prototype's and costs one clip a frame, and pinned by a test that sweeps both
/// ellipses so the next reader does not go hunting for the input that makes it
/// bite. The cap missing the rim by 0.2% of the radius is presumably luck rather
/// than intent — which is exactly why the clip stays: shift the cap by a hair
/// and it starts earning its keep.
void paintMars(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _marsGlow, alpha: 0.6);
  paintSphere(
    canvas,
    at,
    radius,
    lit: _marsLit,
    mid: _marsMid,
    dark: _marsDark,
  );

  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: at, radius: radius)));

  canvas.drawOval(
    Rect.fromCenter(
      center: at.translate(-radius * 0.3, radius * 0.2),
      width: radius * 0.8,
      height: radius * 0.56,
    ),
    Paint()..color = _marsPlain,
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: at.translate(radius * 0.2, -radius * 0.75),
      width: radius * 0.7,
      height: radius * 0.4,
    ),
    Paint()..color = _marsIceCap,
  );

  canvas.restore();
  paintPlanetLabel(canvas, at, radius, 'Mars', showLabels: showLabels);
}

/// Five cloud bands and the Great Red Spot (`index.html:769-776`).
///
/// The bands are drawn as full-width rectangles and clipped to the disc, which
/// is the cheap trick that makes them look like bands wrapping a sphere: the
/// clip cuts each one to a lens shape, so they narrow towards the poles on their
/// own.
///
/// **Unlike Mars's, this clip is load-bearing** — every one of the five rects
/// reaches past the rim (`1.01r` to `1.27r` at its corners), so without it
/// Jupiter is a disc with five stripes ruled straight across the sky behind it.
/// The red spot does not need it (`0.54r`), but it shares the clip for free.
void paintJupiter(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _jupiterGlow, alpha: 0.55);
  paintSphere(
    canvas,
    at,
    radius,
    lit: _jupiterLit,
    mid: _jupiterMid,
    dark: _jupiterDark,
  );

  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: at, radius: radius)));

  final Paint band = Paint();
  for (final (double offset, Color colour) in _jupiterBands) {
    band.color = colour;
    canvas.drawRect(
      Rect.fromLTWH(
        at.dx - radius,
        at.dy + radius * offset - radius * 0.11,
        radius * 2,
        radius * 0.22,
      ),
      band,
    );
  }

  canvas.drawOval(
    Rect.fromCenter(
      center: at.translate(radius * 0.28, radius * 0.22),
      width: radius * 0.4,
      height: radius * 0.26,
    ),
    Paint()..color = _jupiterSpot,
  );

  canvas.restore();
  paintPlanetLabel(canvas, at, radius, 'Jupiter', showLabels: showLabels);
}

/// The rings, in four passes (`index.html:777-788`).
///
/// **The order is the whole illusion.** The ring is one flat ellipse around the
/// planet, but half of it passes *behind* the globe and half in front, so it is
/// drawn as two half-arcs with the sphere painted between them: back half, then
/// Saturn, then the front half — and the globe hides the middle of the back arc
/// without a mask, a depth buffer, or anything else knowing about occlusion. The
/// fourth pass is the thinner inner ring, in front only.
///
/// The front arc is also *brighter* than the back one (`.85` against `.5`),
/// which does the rest of the work: the far side reads as being in the planet's
/// shadow.
void paintSaturn(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _saturnGlow, alpha: 0.5);

  // π → 2π sweeps the *top* of the ellipse (canvas's y grows downward), which is
  // the half that runs behind the globe.
  _paintRingArc(
    canvas,
    at,
    rx: radius * 1.95,
    ry: radius * 0.6,
    from: math.pi,
    colour: _saturnRingBack,
    width: radius * 0.15,
  );

  paintSphere(
    canvas,
    at,
    radius,
    lit: _saturnLit,
    mid: _saturnMid,
    dark: _saturnDark,
  );

  _paintRingArc(
    canvas,
    at,
    rx: radius * 1.95,
    ry: radius * 0.6,
    from: 0,
    colour: _saturnRingFront,
    width: radius * 0.15,
  );
  _paintRingArc(
    canvas,
    at,
    rx: radius * 1.55,
    ry: radius * 0.48,
    from: 0,
    colour: _saturnRingInner,
    width: radius * 0.05,
  );

  // `r * 1.1`, not `r` — the one planet whose label is pushed out, so it clears
  // the rings rather than sitting on them (`index.html:787`).
  paintPlanetLabel(canvas, at, radius * 1.1, 'Saturn', showLabels: showLabels);
}

/// Half of a tilted ellipse (`index.html:780`, `784`, `786`).
///
/// The tilt is baked into the path rather than done with `canvas.rotate`, so the
/// arc is drawn in the same absolute coordinates as everything else on the
/// frame. `addArc` on an oval measures its angles parametrically — the point at
/// `t` is `(cx + rx·cos t, cy + ry·sin t)` — which is exactly what canvas's
/// `ellipse(…, startAngle, endAngle)` means, so the two sweep the same half.
void _paintRingArc(
  Canvas canvas,
  Offset at, {
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
    arc.transform((Matrix4.identity()..rotateZ(_saturnTilt)).storage).shift(at),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = colour,
  );
}

// ── The Sun (`index.html:801-806`).

/// The light the whole screen is lit by (`index.html:801-806`).
///
/// **Not a [paintSphere], and it is the only body here that is not.** A sphere
/// is a lit thing: it takes a highlight from the upper left and pools a shadow
/// at the lower right. The Sun is what is doing the lighting, so it has no
/// terminator and no dark side — just a hot core ramping out to its rim.
///
/// **Its highlight is offset by a flat 6px, not by a fraction of [radius]**
/// (`createRadialGradient(sx-6, sy-6, 4, sx, sy, sr)`, `index.html:803`), which
/// is the one place the backdrop breaks its own rule that everything scales.
/// The effect is that zooming in walks the core towards the centre and the disc
/// flattens into an even glare, which is more or less what happens when you get
/// closer to something that big. Ported literally either way — the alternative
/// is inventing a proportion the prototype does not have.
void paintSun(
  Canvas canvas,
  Offset at,
  double radius, {
  required bool showLabels,
}) {
  paintGlow(canvas, at, radius, colour: _sunGlow, alpha: 0.95);

  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(
        at,
        radius,
        const <Color>[_sunCore, _sunBody, _sunRim],
        const <double>[0, 0.42, 1],
        TileMode.clamp,
        null,
        at.translate(-6, -6),
        4,
      ),
  );

  // `if (Radar.showLabels)` (`index.html:806`) — the Labels chip switches the
  // Sun's name off with everything else's. Gated here rather than in `paintSun`'s
  // head because only the label is optional; the disc is scenery that stays.
  if (!showLabels) return;

  // **Not [paintPlanetLabel]**, close as it looks: the Sun's caption is written
  // out longhand in `drawPlanets` (`index.html:806`) with its own warm colour
  // and its own 12px drop rather than the planets' 11. Routing it through
  // `pLabel` would silently restyle it, so the two stay separate — which is
  // what the prototype is saying by not calling `pLabel` here itself.
  radarLabel(
    'Sun',
    size: 9,
    colour: _sunLabelColour,
  ).paint(canvas, at.dx, at.dy + radius + 12);
}

// ── The backdrop's palette, ported from `index.html:741-788` and `801-806`.
//
// All of it is one-off literals in the prototype — none of these colours is a
// `:root` variable, and none is reused outside this file — so they stay local,
// which is the rule `Palette`'s own doc sets out for what does and does not get
// hoisted.

/// `rgba(180,196,225,.72)` (`index.html:756`) — every planet's name.
///
/// Deliberately *not* `Palette.muted` (`#93a8ca`), close as it looks: it is a
/// paler, bluer grey, and the difference is the point. The backdrop's labels sit
/// behind the field's, so they are the one text on this screen that is meant to
/// recede.
const Color _planetLabelColour = Color.fromRGBO(180, 196, 225, 0.72);

/// The terminator's two stops (`index.html:746`) — clear, then half-black.
const Color _shadowClear = Color.fromRGBO(0, 0, 0, 0);
const Color _shadowDark = Color.fromRGBO(0, 0, 0, 0.5);

/// Mercury (`index.html:759`) — bare rock, so its three stops are pure greys.
const Color _mercuryGlow = Color.fromRGBO(150, 150, 160, 0.22);
const Color _mercuryLit = Color(0xFFD2D2D6);
const Color _mercuryMid = Color(0xFF8F8F96);
const Color _mercuryDark = Color(0xFF4A4A52);

/// Venus (`index.html:760`) — the cloud deck, which is all anyone ever sees.
const Color _venusGlow = Color.fromRGBO(240, 205, 150, 0.28);
const Color _venusLit = Color(0xFFF7E6BD);
const Color _venusMid = Color(0xFFE2BA79);
const Color _venusDark = Color(0xFF9C7B3E);

/// Mars (`index.html:762-768`).
const Color _marsGlow = Color.fromRGBO(230, 110, 60, 0.3);
const Color _marsLit = Color(0xFFF0A878);
const Color _marsMid = Color(0xFFD1440E);
const Color _marsDark = Color(0xFF7A2408);
const Color _marsPlain = Color.fromRGBO(120, 45, 15, 0.4);
const Color _marsIceCap = Color.fromRGBO(255, 255, 255, 0.55);

/// Jupiter (`index.html:769-776`).
const Color _jupiterGlow = Color.fromRGBO(220, 160, 110, 0.26);
const Color _jupiterLit = Color(0xFFECD0A8);
const Color _jupiterMid = Color(0xFFC98F5A);
const Color _jupiterDark = Color(0xFF7A4A2A);
const Color _jupiterSpot = Color.fromRGBO(200, 80, 50, 0.8);

/// The five cloud bands (`index.html:773-774`), each an offset in radii from the
/// planet's equator and the colour it is painted.
///
/// **Not evenly spaced, and not symmetrical about the equator** — the gaps run
/// 0.34, 0.33, 0.33, 0.30 and the whole set sits slightly north of centre. That
/// irregularity is what keeps Jupiter from looking like a barcode; ported as the
/// literal table it is rather than generated from a step.
const List<(double, Color)> _jupiterBands = <(double, Color)>[
  (-0.62, Color.fromRGBO(120, 70, 40, 0.35)),
  (-0.28, Color.fromRGBO(235, 205, 165, 0.4)),
  (0.05, Color.fromRGBO(150, 90, 55, 0.4)),
  (0.38, Color.fromRGBO(215, 180, 140, 0.32)),
  (0.68, Color.fromRGBO(130, 78, 45, 0.35)),
];

/// Saturn (`index.html:777-788`).
const Color _saturnGlow = Color.fromRGBO(220, 200, 150, 0.26);
const Color _saturnLit = Color(0xFFF4E6C4);
const Color _saturnMid = Color(0xFFD9BE86);
const Color _saturnDark = Color(0xFF8F7440);

/// `rgba(220,205,165,.5)` — the half of the ring running behind the planet,
/// dimmer because it is in Saturn's shadow.
const Color _saturnRingBack = Color.fromRGBO(220, 205, 165, 0.5);

/// `rgba(238,222,182,.85)` — the near half, in full sunlight.
const Color _saturnRingFront = Color.fromRGBO(238, 222, 182, 0.85);

/// `rgba(205,185,145,.55)` — the thin inner ring, front only.
const Color _saturnRingInner = Color.fromRGBO(205, 185, 145, 0.55);

/// `-0.38` radians (`index.html:780`) — about 22° of tilt, shared by all three
/// ring arcs. They are one object, so a value that drifted between them would
/// tear the ring apart.
const double _saturnTilt = -0.38;

/// The Sun (`index.html:802-806`).
///
/// **The only warm light on a screen that is otherwise entirely blue**, which is
/// what buys it: at 4% across the field it is a sliver, and the colour is the
/// whole reason a child reads that sliver as the Sun rather than as a smudge.
///
/// `rgba(255,168,54,.5)` at a 0.95 alpha, so the halo lands at 0.475 — by some
/// way the strongest glow in the backdrop (Neptune's, the next brightest, is
/// 0.18). It reaches 2.3× a 44px disc, which is 101px of orange bleeding across
/// the corner of the field.
const Color _sunGlow = Color.fromRGBO(255, 168, 54, 0.5);

/// The disc's three stops (`index.html:804`): white-hot core, `#ffd166` body,
/// and a rim that has cooled to `#f2731d`.
///
/// **Deliberately not `Palette.accent`/`accent2`**, which are the same family of
/// orange. Those are the app's *interactive* colour — the one that means "this
/// is a thing you can press" (`palette.dart`) — and the Sun is scenery a child
/// must never try to tap. It is one-off `rgba()` literals in the prototype and
/// it stays that way here, which is the rule that kept the radar's ring colours
/// local too.
const Color _sunCore = Color(0xFFFFF7DB);
const Color _sunBody = Color(0xFFFFD166);
const Color _sunRim = Color(0xFFF2731D);

/// `rgba(255,206,140,.8)` (`index.html:806`) — the Sun's own name.
///
/// A hair off the close-flyby name colour on the field above
/// (`rgba(255,206,140,.9)`, `radar_painter.dart`), and the two are unrelated:
/// same channels, different alpha, different layer. Neither derives from the
/// other, because the prototype writes both out by hand and they have nothing to
/// do with each other beyond both being warm text on deep space.
const Color _sunLabelColour = Color.fromRGBO(255, 206, 140, 0.8);

/// Neptune (`index.html:761`) — the deepest blue in the backdrop, and the
/// furthest thing out there.
const Color _neptuneGlow = Color.fromRGBO(60, 110, 230, 0.3);
const Color _neptuneLit = Color(0xFF8FB0FF);
const Color _neptuneMid = Color(0xFF3A5ED8);
const Color _neptuneDark = Color(0xFF1E2F7A);
