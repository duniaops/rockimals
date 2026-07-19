import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/planet_painters.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_labels.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';

/// The radar: deep space, the planet backdrop, the distance rings, the Moon,
/// the animals orbiting on them, and Earth at the centre (`radarDraw`,
/// `index.html:816-877`).
///
/// The order here is the prototype's, and it is the reason Earth is the *last*
/// thing painted (`index.html:870`): it is the smallest and most important
/// object on the screen, so nothing is allowed to cover it.
///
/// **Repaints are driven by [clock] rather than by rebuilding the widget.**
/// [CustomPainter.repaint] listens to it directly, so a frame costs one
/// `paint` and no element tree walk — the shape `CLAUDE.md:80` asks for.
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.clock,
    required this.orbits,
    required this.backdrop,
    required this.maxLd,
    required this.zoom,
    required this.viewRot,
    required this.layers,
    this.selected,
  }) : super(repaint: clock);

  /// Time since the radar started drawing. Earth's glow and the selection ring
  /// pulse off it; the animals' own motion is [orbits]', because it is
  /// integrated rather than computed (see [RadarOrbits.advance]).
  final ValueListenable<Duration> clock;

  /// The animals, the Moon, and where they currently are. Advanced by the view's
  /// `Ticker` immediately before [clock] fires, so a frame reads it and does not
  /// move it.
  final RadarOrbits orbits;

  /// The decorative planets and the Sun behind the field. Drifted by the same
  /// `Ticker` and on the same step as [orbits] — see [PlanetBackdrop.advance].
  final PlanetBackdrop backdrop;

  /// How far out the field reaches, from [RadarGeometry.maxLdFor].
  final double maxLd;

  /// The pinch scale (`index.html:625`), clamped to 0.35–6.5 by the view that
  /// owns it. Rings scale with it; **Earth does not** — the prototype strokes it
  /// at a fixed 15px however far in you are (`index.html:874`), so the thing the
  /// whole screen is about never grows into the field or shrinks out of sight.
  final double zoom;

  /// How far the child has spun the field, in radians (`Radar.viewRot`,
  /// `index.html:625`).
  ///
  /// **Not applied here as a canvas rotation, deliberately.** Turning the whole
  /// canvas would take the ring labels, the animals' names, and "Earth" round
  /// with it and leave a child reading upside-down text. The prototype adds it to
  /// the two *angles* instead (`index.html:837`, `845`) — the animals and the
  /// Moon travel round the field while every word on it stays the right way up —
  /// so it is [RadarOrbits]' business, and this painter only carries it there.
  final double viewRot;

  /// The animal a child has tapped, if any (`Radar.selected`,
  /// `index.html:624`) — it wears a white ring that breathes, a caret pointing
  /// up at it from below, and says its name.
  final Asteroid? selected;

  /// Which of the five toggle layers are on (`Radar.showHaz`/`showLabels`/
  /// `showRings`/`showMoon`/`showPlanets`, `index.html:625`). Every guard in
  /// [paint] reads one of these; the view owns flipping them.
  final RadarLayers layers;

  @override
  void paint(Canvas canvas, Size size) {
    final RadarGeometry geometry = RadarGeometry(size: size, maxLd: maxLd);
    // `ts` is the rAF timestamp in `radarDraw(ts)`, i.e. milliseconds since the
    // loop began — which is exactly what a `Ticker` hands over.
    final double ts = clock.value.inMicroseconds / 1000;
    final double pulse = (math.sin(ts / 300) + 1) / 2;

    // **🐢 Calm motion deliberately does not reach [ts], and so does not reach
    // the breath below or the planets' bob.** Both read the clock directly
    // rather than integrating the ticker's step, which is why they are
    // untouched by the drift factor — but that is an accident of shape, and
    // this note is here so a later reader does not "fix" it. The reason to
    // leave them is that they are the setting's own exclusion: an opacity and a
    // radius that breathe in place, and five pixels of vertical bob, are not
    // travel across a screen, and the vestibular concern reduced motion serves
    // is large positional movement. A radar whose Earth stopped breathing under
    // Calm motion would be a still photograph, which is what a crash looks
    // like. What *is* calmed is everything fed from the step: the animals, the
    // Moon and the backdrop's horizontal drift (see `radar_view.dart`'s ticker).

    // The prototype's own order (`index.html:818-877`), and every step of it is
    // a decision about what may cover what: the backdrop is scenery and is
    // painted before anything the child can read, the rings are scale and go
    // under everything else, the Moon is the unit those rings are read against,
    // the animals are the subject, and Earth is last because it is the smallest
    // and most important thing on the screen.
    _paintSpace(canvas, size);
    // Each layer is behind its chip (`index.html:816-877`). The animals and
    // Earth have no chip — the sky always has its subject and its centre — so
    // they are unguarded; the Close-flybys filter thins the animals rather than
    // hiding them all, and it lives inside [_paintAnimals].
    if (layers.planets) _paintBackdrop(canvas, geometry, ts);
    if (layers.rings) _paintRings(canvas, geometry);
    if (layers.moon) _paintMoon(canvas, geometry);
    _paintAnimals(canvas, geometry, pulse: pulse);
    _paintEarth(canvas, geometry, pulse: pulse);
  }

  /// The dark that everything else sits on (`index.html:170`).
  ///
  /// The prototype puts this on `.radarwrap` and leaves the canvas transparent,
  /// which is a DOM split rather than a design one: `#radarCv` is
  /// `position:absolute; inset:0` (`index.html:171`), so the two are the same
  /// rectangle. Painting it here keeps the radar one self-contained thing
  /// instead of a canvas that only looks right if whoever mounts it remembers
  /// to put the correct colour behind it.
  void _paintSpace(Canvas canvas, Size size) {
    // `circle at 50% 44%` — not the 46% Earth sits at. The glow's centre is
    // deliberately a touch above the planet, which reads as light coming from
    // somewhere rather than as a halo the planet emits.
    final Offset heart = Offset(size.width * 0.5, size.height * 0.44);
    // CSS sizes an unqualified `radial-gradient` to `farthest-corner`. From 44%
    // down the box that is always a bottom corner, 0.56 of the height away.
    final double toFarthestCorner = math.sqrt(
      math.pow(size.width * 0.5, 2) + math.pow(size.height * 0.56, 2),
    );

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          heart,
          toFarthestCorner,
          const <Color>[_spaceNear, _spaceFar],
          const <double>[0, 0.72],
        ),
    );
  }

  /// The Sun and the six planets behind the field (`drawPlanets`,
  /// `index.html:798-814`).
  ///
  /// **The Sun goes down first, and the planets in table order**
  /// (`index.html:802`, `808`) — so where two bodies overlap, the one further
  /// down `PLANETS` wins. Nothing depends on it today (the six are spread across
  /// the field and only meet as they drift past each other), which is exactly
  /// why it is worth pinning: when they do meet, they should meet the way the
  /// prototype has them meet.
  ///
  /// **The whole method is behind `if (Radar.showPlanets)` (`index.html:818`)**,
  /// which [paint] applies at the call site — the guard wraps the Sun *and* the
  /// six planets, so the Planets chip clears the 44px orange glare in the corner
  /// along with the planets rather than leaving it bleeding across a switched-off
  /// backdrop.
  ///
  /// [RadarLayers.labels] is passed on to the Sun and every planet so the Labels
  /// chip can switch their names off with the animals' (`index.html:755`, `806`).
  void _paintBackdrop(Canvas canvas, RadarGeometry geometry, double ts) {
    paintSun(
      canvas,
      backdrop.sunPosition(geometry: geometry, zoom: zoom, ts: ts),
      backdrop.sunRadius(zoom: zoom),
      showLabels: layers.labels,
    );

    for (final Planet planet in backdrop.planets) {
      // `p.draw(ctx, x, y, rr)` (`index.html:812`) — the table's own function
      // reference, called with the prototype's own three arguments plus the
      // labels flag its `pLabel` reads off a global.
      planet.draw(
        canvas,
        backdrop.positionOf(planet, geometry: geometry, zoom: zoom, ts: ts),
        backdrop.radiusOf(planet, zoom: zoom),
        showLabels: layers.labels,
      );
    }
  }

  /// The dashed Moon-distance rings and their labels (`index.html:823-831`).
  void _paintRings(Canvas canvas, RadarGeometry geometry) {
    final Offset center = geometry.center;
    // One [Paint], recoloured per ring, rather than six per frame.
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final (ld: int ld, radius: double radius) in geometry.visibleRings(
      zoom: zoom,
    )) {
      final bool isMoon = ld == 1;
      stroke.color = isMoon ? _moonRingColour : _outerRingColour;
      canvas.drawPath(
        dashedCircle(
          center,
          radius,
          // The Moon's ring gets longer dashes and smaller gaps than the rest
          // (`index.html:828`), so it reads as the one real thing out there
          // and the others as the measuring marks they are.
          on: isMoon ? 3 : 2,
          off: isMoon ? 5 : 7,
        ),
        stroke,
      );

      // Sat just above the ring's twelve o'clock, on its baseline
      // (`index.html:830`).
      _ringLabel(ld).paint(canvas, center.dx, center.dy - radius - 3);
    }
  }

  /// The Moon, riding its own ring (`index.html:833-841`).
  ///
  /// A plain grey disc with its name over it — the one object out there a child
  /// has already seen with their own eyes, which is what makes it the ruler
  /// every other distance on this screen is measured with (`CLAUDE.md:66`).
  ///
  /// **When the Rings chip is off but the Moon is on, the 1× ring is drawn here
  /// anyway** (`index.html:835`), so the Moon keeps a visible track rather than
  /// floating on nothing. It is a hair dimmer than the rings' own 1× stroke
  /// (`.28` against `.30`, `index.html:835` vs `827`) — a track for the Moon, not
  /// a distance ring in its own right — and it shares the Moon's [3, 5] dash so
  /// the two read as the same object.
  void _paintMoon(Canvas canvas, RadarGeometry geometry) {
    final Offset center = geometry.center;

    if (!layers.rings) {
      canvas.drawPath(
        dashedCircle(center, geometry.moonRadius(zoom: zoom), on: 3, off: 5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _moonTrackColour,
      );
    }

    final Offset moon = orbits.moonPosition(
      geometry: geometry,
      zoom: zoom,
      viewRot: viewRot,
    );

    canvas.drawCircle(moon, _moonRadius, Paint()..color = _moonColour);
    _moonLabel.paint(canvas, moon.dx, moon.dy - 9);
  }

  /// The animals (`index.html:842-869`).
  ///
  /// Each is a navy token, a ring around it, and its emoji — drawn in that order
  /// so the animal sits *in* something rather than floating on the field.
  ///
  /// **The token is why every animal reads as bright and alive**
  /// (`index.html:852`). An emoji straight onto deep space is dim, low-contrast
  /// and, next to a big one, looks switched off — and `specs/02-live-radar.md:28`
  /// is explicit that no animal may ever look faded. The token gives all of them
  /// the same lit background whatever their size, so the size difference stays a
  /// size difference and does not turn into a difference in how *alive* they
  /// look.
  void _paintAnimals(
    Canvas canvas,
    RadarGeometry geometry, {
    required double pulse,
  }) {
    // Two [Paint]s recoloured per animal, rather than two per animal per frame.
    final Paint fill = Paint();
    final Paint stroke = Paint()..style = PaintingStyle.stroke;

    // `if (Radar.showHaz && !a.hazardous) { a._sx = null; return; }`
    // (`index.html:843`), read through the tag rather than the raw flag (plan
    // decision 2). Iterating [RadarOrbits.visible] — the same list the hit test
    // walks — is what stops a filtered animal from being tappable while off
    // screen.
    for (final RadarOrbit orbit in orbits.visible(
      onlyCloseFlybys: layers.closeFlybysOnly,
    )) {
      final Offset at = orbits.positionOf(
        orbit,
        geometry: geometry,
        zoom: zoom,
        viewRot: viewRot,
      );
      final double chip = orbit.chipRadius;
      // By designation, not by identity: the prototype compares object
      // references (`Radar.selected===a`, `index.html:851`) because it only ever
      // has the one array, but the designation is this app's identity for a rock
      // everywhere else (plan decision 12) and it does not care which list an
      // asteroid was read out of.
      final bool isSelected = orbit.asteroid.name == selected?.name;

      // `createRadialGradient(x-chip*.3, y-chip*.3, chip*.2, x, y, chip)` — lit
      // from up and to the left, like Earth, so the tokens belong to the same
      // scene as the planet rather than being flat stickers on it.
      fill.shader = ui.Gradient.radial(
        at,
        chip,
        const <Color>[_chipLit, _chipDark],
        const <double>[0, 1],
        TileMode.clamp,
        null,
        at.translate(-chip * 0.3, -chip * 0.3),
        chip * 0.2,
      );
      canvas.drawCircle(at, chip, fill);

      stroke
        ..strokeWidth = 2
        ..color = orbit.isCloseFlyby ? _closeFlybyRing : _restingRing;
      canvas.drawCircle(at, chip, stroke);

      if (isSelected) {
        final double halo = chip + 3 + pulse * 3;
        stroke
          ..strokeWidth = 2.5
          ..color = _selectedRing;
        canvas.drawCircle(at, halo, stroke);
        _paintSelectionCaret(canvas, at, chip: chip, halo: halo);
      }

      _emoji(
        orbit.critter.animal.emoji,
        orbit.emojiSize,
      ).paintCentred(canvas, at);

      // **The wave is the accessibility audit's addition, and it is the only
      // mark on this field the prototype does not have.**
      // `specs/06-title-polish-safety.md:23` says never to rely on colour
      // alone, and until now the radar did exactly that: a close flyby was an
      // orange ring and nothing else, which is invisible to a colour-blind
      // child and to anyone who has not been told what orange means. Every
      // other surface in the app already pairs that state with this glyph and
      // the words "close flyby" — the badge, the home strip's count chip, the
      // Sky filter — so the fix is to say the same thing here rather than
      // invent a radar-specific one. The words follow on tap, in the HUD card.
      //
      // Drawn at the token's shoulder so it cannot sit under the name label
      // above it, and sized against the animal rather than fixed, so it stays
      // proportional as the zoom changes `emojiSize`. It costs one cached
      // [RadarLabel] per distinct size (`radar_labels.dart`), exactly as the
      // animal emoji beside it does — no per-frame layout (`CLAUDE.md:80`).
      if (orbit.isCloseFlyby) {
        _wave(
          orbit.emojiSize * _waveScale,
        ).paintCentred(canvas, at.translate(chip * 0.8, -chip * 0.8));
      }

      // Only the animals waving and the one being looked at say their names,
      // and only while the Labels chip is on — `showLabels && (close || sel)`
      // (`index.html:864`). Sixty labels at once would be a wall of text on a
      // screen a five-year-old is meant to be able to read; the rest introduce
      // themselves when they are tapped.
      if (layers.labels && (orbit.isCloseFlyby || isSelected)) {
        _animalName(
          orbit.critter.first,
          selected: isSelected,
        ).paint(canvas, at.dx, at.dy - orbit.emojiSize * 0.6 - 4);
      }
    }

    fill.shader = null;
  }

  /// The arrowhead under the selected animal — the second channel the white
  /// halo does not have.
  ///
  /// **Why a shape and not another colour.** The halo is the prototype's mark
  /// (`index.html:855-857`) and it is kept, but on its own it says "selected"
  /// in hue alone, which `specs/06-title-polish-safety.md:23` forbids. In
  /// greyscale — the check that spec asks for — a white halo, a close flyby's
  /// orange ring and a resting animal's blue-grey one are all just light rings
  /// around a token, so a child who cannot separate those hues cannot tell
  /// which animal the HUD card is about. That is the whole job of this mark:
  /// the card names the animal, and this says *which token the card belongs
  /// to*. A filled triangle is the one thing on this field that is not a ring,
  /// a disc or a glyph, so it survives being read as a grey blob.
  ///
  /// It is the same fix the 👋 above is, in the same shape: keep the colour,
  /// add a channel that does not need it. It is **not** label-gated for the
  /// same reason either — turning names off must not drop selection back to
  /// colour alone.
  ///
  /// **Below, pointing up**, because below is the only clear side: the name
  /// sits above the token and the wave on its upper-right shoulder. It hangs
  /// off [halo] rather than off [chip], so it breathes on the same sine and the
  /// two read as one mark instead of a ring with a sticker next to it.
  ///
  /// One [Path] per frame, for the at-most-one selected animal — the [Paint] is
  /// the file-level [_selectionCaretFill] because it never varies, which is the
  /// allocation `CLAUDE.md:80` actually cares about.
  void _paintSelectionCaret(
    Canvas canvas,
    Offset at, {
    required double chip,
    required double halo,
  }) {
    final double half = chip * _caretHalfWidth;
    final double apex = at.dy + halo + _caretGap;
    final double base = apex + chip * _caretHeight;

    canvas.drawPath(
      Path()
        ..moveTo(at.dx, apex)
        ..lineTo(at.dx - half, base)
        ..lineTo(at.dx + half, base)
        ..close(),
      _selectionCaretFill,
    );
  }

  /// Earth: a glow that breathes, the planet, and its name
  /// (`index.html:870-876`).
  void _paintEarth(
    Canvas canvas,
    RadarGeometry geometry, {
    required double pulse,
  }) {
    final Offset center = geometry.center;

    // The glow is the only thing on this layer that moves. It is a slow breath
    // — a ~1.9s period, three pixels of travel — which is the "calm" of
    // `specs/02-live-radar.md:28` made literal: the screen is never quite
    // still, and never asks to be looked at either.
    canvas.drawCircle(
      center,
      26 + pulse * 3,
      Paint()..color = _earthGlowColour,
    );

    canvas.drawCircle(
      center,
      15,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          16,
          const <Color>[_earthLit, _earthOcean, _earthDark],
          const <double>[0, 0.55, 1],
          TileMode.clamp,
          null,
          // `createRadialGradient(cx-4, cy-4, 2, cx, cy, 16)` — a two-circle
          // gradient, which Flutter spells as a focal point. Up and to the
          // left of centre, so the planet is lit from off-screen rather than
          // being a flat blue dot.
          center.translate(-4, -4),
          2,
        ),
    );

    _earthLabel.paint(canvas, center.dx, center.dy + 27);
  }

  /// Only about the things a *rebuild* can change. The animals moving does not
  /// go through here at all — [clock] is the painter's `repaint` listenable, so
  /// a frame is a repaint with no rebuild and nothing to compare.
  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) =>
      oldDelegate.maxLd != maxLd ||
      oldDelegate.zoom != zoom ||
      oldDelegate.viewRot != viewRot ||
      oldDelegate.selected?.name != selected?.name ||
      oldDelegate.layers != layers ||
      !identical(oldDelegate.orbits, orbits) ||
      !identical(oldDelegate.backdrop, backdrop);
}

/// A circle stroked as dashes — `setLineDash([on, off])` over
/// `arc(cx, cy, r, 0, …)` (`index.html:828-829`), which Flutter has no
/// equivalent of.
///
/// [on] and [off] are lengths *along the circumference* in pixels, as CSS and
/// canvas measure a dash pattern, so the same pattern gives a bigger ring more
/// dashes rather than longer ones. The pattern starts at three o'clock and the
/// last dash is cut short at the top of the loop rather than wrapping — again
/// what canvas does, since a dash pattern restarts per sub-path.
///
/// **The prototype's arc sweeps 7 radians, and this one sweeps 2π.** `0, 7` is
/// its idiom for "all the way round" — every other arc in `radarDraw` uses the
/// same two numbers for a plain circle (`index.html:838`, `857`, `873`), where
/// the extra 0.72 radians is drawn over itself and cannot be seen. Under a dash
/// pattern it *can*: the overshoot lays a second run of dashes across the first
/// at a different phase, brightening one arc of every ring and part-filling its
/// gaps. That is the side effect of a shorthand, not a design, so what is
/// ported here is the circle it means.
Path dashedCircle(
  Offset center,
  double radius, {
  required double on,
  required double off,
}) {
  final Path path = Path();
  final Rect box = Rect.fromCircle(center: center, radius: radius);
  final double onSweep = on / radius;
  final double period = (on + off) / radius;

  for (double start = 0; start < _tau; start += period) {
    // Each `addArc` opens its own sub-path, which is what makes these dashes
    // rather than one polyline.
    path.addArc(box, start, math.min(onSweep, _tau - start));
  }

  return path;
}

/// What a ring calls itself (`index.html:830`).
///
/// Every distance in this app is a Moon-distance and nothing else
/// (`CLAUDE.md:66`), so the innermost ring names the Moon outright and the rest
/// count against it. There is no unit here to learn and no number to be scared
/// of — 20× Moon is twenty times as far away as the thing in the sky tonight.
@visibleForTesting
String ringLabelText(int ld) => ld == 1 ? '🌙 Moon' : '$ld× Moon';

const double _tau = math.pi * 2;

// ── The radar's palette, ported from `index.html:170` and `823-876`.
//
// **Almost none of these are CSS variables, and that is why they are still
// here.** `radarDraw` hard-codes its own `rgba()` literals: the ring strokes,
// Earth's glow and its three gradient stops, and the space wrap's two ends exist
// nowhere else in the prototype and are named by nothing. `Palette` holds what
// the prototype itself named; a radar reading its ring colours from a shared
// palette would be inventing a relationship the prototype does not have, so the
// one-offs below stay local — which is the answer this screen was kept open to
// give the plan's "extract the palette" item.
//
// The two exceptions are the labels, which *are* `--muted` in disguise, at .55
// and .85. They now derive from `Palette.muted` rather than restating its
// channels, so the app's most-used colour lives in one place.

/// `#0c2044` — the near end of the space glow (`index.html:170`).
const Color _spaceNear = Color(0xFF0C2044);

/// `#040a17` — deep space at the edges, and the darkest thing in the app.
const Color _spaceFar = Color(0xFF040A17);

/// `rgba(207,214,222,.30)` (`index.html:827`) — the 1× ring, drawn brighter
/// than the others because it is the Moon's own orbit and the unit every other
/// ring is read against.
const Color _moonRingColour = Color.fromRGBO(207, 214, 222, 0.30);

/// `rgba(90,120,170,.16)` (`index.html:827`) — the 2× and beyond, faint enough
/// to be scale rather than scenery.
const Color _outerRingColour = Color.fromRGBO(90, 120, 170, 0.16);

/// `rgba(207,214,222,.28)` (`index.html:835`) — the Moon's fallback track, drawn
/// only when the Rings chip is off. Two points dimmer than the 1× ring proper
/// (`.30`), because here it is the Moon's own orbit and not one of the measuring
/// marks.
const Color _moonTrackColour = Color.fromRGBO(207, 214, 222, 0.28);

/// `rgba(147,168,202,.55)` — `--muted`, dimmed (`index.html:830`).
///
/// `final` rather than `const` because no const expression can derive one
/// colour's alpha from another. It costs nothing per frame: a top-level `final`
/// is computed once, on first access, and the labels it paints are themselves
/// laid out once and cached (see [RadarLabel]).
final Color _ringLabelColour = Palette.muted.withValues(alpha: 0.55);

/// `#cfd6de` (`index.html:837`) — the Moon, and the only grey on the field.
const Color _moonColour = Color(0xFFCFD6DE);

/// The Moon's disc, in pixels (`index.html:837`). It does not scale with zoom,
/// for Earth's reason: it is an object, not a distance, and the ring it rides is
/// where the distance is being shown.
const double _moonRadius = 5;

/// `rgba(147,168,202,.8)` — `--muted` a third time (`index.html:839`).
final Color _moonLabelColour = Palette.muted.withValues(alpha: 0.8);

/// The navy token behind every animal (`index.html:853`) — lit and shadow.
const Color _chipLit = Color(0xFF20406E);
const Color _chipDark = Color(0xFF122A4D);

/// `rgba(232,140,60,.95)` (`index.html:854`) — the ring on an animal that is
/// waving. A warm orange, close to `--accent` but not it: this is the one place
/// in the app that marks NASA's "potentially hazardous" flag, and it is a
/// *greeting*, not a warning (`CLAUDE.md:64`).
const Color _closeFlybyRing = Color.fromRGBO(232, 140, 60, 0.95);

/// `rgba(120,150,200,.45)` (`index.html:854`) — everyone else. Quiet enough to
/// be an outline rather than a state.
const Color _restingRing = Color.fromRGBO(120, 150, 200, 0.45);

/// `#fff` (`index.html:856`) — the animal being looked at. White because it is
/// the only colour on this field that means nothing else. What it does *not*
/// carry on its own is the state — see [RadarPainter._paintSelectionCaret].
const Color _selectedRing = Color(0xFFFFFFFF);

/// The selection caret's fill. A top-level `final`, so the one shape the
/// painter draws per frame does not also cost a [Paint] per frame.
final Paint _selectionCaretFill = Paint()..color = _selectedRing;

/// The caret, against the token it points at. Half the arrowhead's width and
/// its full height, both as a fraction of `chipRadius` — which spans only
/// 10.8–20.7px across every animal the ladder can produce
/// (`chipSizeFor`, `radar_geometry.dart:187-191`), so the mark stays a
/// readable arrowhead on a Mouse without becoming a second animal on a Whale.
/// No floor is needed at that range, and one would be dead code if it were.
const double _caretHalfWidth = 0.42;
const double _caretHeight = 0.5;

/// The gap between the breathing halo and the caret's apex. Small enough that
/// they read as one mark, big enough that the apex is never swallowed by the
/// 2.5px stroke it sits under.
const double _caretGap = 1.5;

/// `rgba(255,206,140,.9)` (`index.html:865`) — a close flyby's name.
const Color _flybyNameColour = Color.fromRGBO(255, 206, 140, 0.9);

/// **The emoji's colour is not read, and the prototype proves it.** `radarDraw`
/// never sets `fillStyle` before `fillText(c.emoji, …)` (`index.html:861-862`),
/// so the emoji is nominally filled with the chip's radial gradient — and looks
/// nothing like it, because 🐭 and 🐋 are colour glyphs that carry their own
/// bitmaps and ignore the fill entirely. A [TextStyle] needs *some* colour, so
/// this is plain opaque white: the value a monochrome fallback glyph would use,
/// on the field where white already means nothing else.
const Color _emojiColour = Color(0xFFFFFFFF);

/// `rgba(120,180,255,.12)` (`index.html:873`) — the atmosphere.
const Color _earthGlowColour = Color.fromRGBO(120, 180, 255, 0.12);

/// The planet's three stops (`index.html:872`): daylight, ocean, night.
const Color _earthLit = Color(0xFFA9DCFF);
const Color _earthOcean = Color(0xFF1C6FB0);
const Color _earthDark = Color(0xFF0C355C);

/// `rgba(147,168,202,.85)` — `--muted` again (`index.html:875`).
final Color _earthLabelColour = Palette.muted.withValues(alpha: 0.85);

/// The radar's text is laid out once each and kept for the life of the app —
/// see [radarLabel] in `radar_labels.dart` for why, and for the cache the four
/// helpers below sit on.

RadarLabel _ringLabel(int ld) =>
    radarLabel(ringLabelText(ld), size: 9, colour: _ringLabelColour);

/// `${em}px serif` (`index.html:861`). The size is per-animal, so this is the
/// one label whose key really varies.
RadarLabel _emoji(String emoji, double size) =>
    radarLabel(emoji, size: size, colour: _emojiColour, family: 'serif');

/// The 👋 on a close flyby's token — the icon half of "never colour alone"
/// (`specs/06-title-polish-safety.md:23`). `serif` for the same reason the
/// animal emoji asks for it, and the same opaque white: a colour emoji carries
/// its own bitmap and ignores the fill, so this colour only matters to a
/// monochrome fallback glyph.
RadarLabel _wave(double size) => radarLabel(
  kCloseFlybyGlyph,
  size: size,
  colour: _emojiColour,
  family: 'serif',
);

/// How big the wave is against the animal it belongs to. Small enough to read
/// as a mark *on* the token rather than a second animal beside it, big enough
/// to survive the smallest `emojiSize` the zoom produces.
const double _waveScale = 0.55;

/// A close flyby's or the selected animal's first name (`index.html:865-867`).
/// The selected one is white and bold; everyone else waving is warm amber.
RadarLabel _animalName(String first, {required bool selected}) => radarLabel(
  first,
  size: 10,
  colour: selected ? _selectedRing : _flybyNameColour,
  weight: selected ? FontWeight.bold : null,
);

final RadarLabel _earthLabel = RadarLabel(
  'Earth',
  fontSize: 10,
  colour: _earthLabelColour,
);

final RadarLabel _moonLabel = RadarLabel(
  'Moon',
  fontSize: 9,
  colour: _moonLabelColour,
);
