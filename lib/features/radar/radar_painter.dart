import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';

/// The radar's base layer: deep space, the distance rings, and Earth at the
/// centre of them (`radarDraw`, `index.html:816-877`).
///
/// The animals, the Moon, and the planet backdrop are other items' work; this
/// is the field they are drawn on and the scale they are placed by. The order
/// here is the prototype's, and it is the reason Earth is the *last* thing
/// painted (`index.html:870`): it is the smallest and most important object on
/// the screen, so nothing is allowed to cover it.
///
/// **Repaints are driven by [clock] rather than by rebuilding the widget.**
/// [CustomPainter.repaint] listens to it directly, so a frame costs one
/// `paint` and no element tree walk — the shape `CLAUDE.md:80` asks for.
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.clock,
    required this.maxLd,
    required this.zoom,
  }) : super(repaint: clock);

  /// Time since the radar started drawing. Only Earth's glow reads it today;
  /// the orbit loop is the next item's.
  final ValueListenable<Duration> clock;

  /// How far out the field reaches, from [RadarGeometry.maxLdFor].
  final double maxLd;

  /// The pinch/scroll scale (`index.html:625`, clamped to 0.35–6.5 by the
  /// interactions item). Rings scale with it; **Earth does not** — the
  /// prototype strokes it at a fixed 15px however far in you are
  /// (`index.html:874`), so the thing the whole screen is about never grows
  /// into the field or shrinks out of sight.
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final RadarGeometry geometry = RadarGeometry(size: size, maxLd: maxLd);
    // `ts` is the rAF timestamp in `radarDraw(ts)`, i.e. milliseconds since the
    // loop began — which is exactly what a `Ticker` hands over.
    final double ts = clock.value.inMicroseconds / 1000;

    _paintSpace(canvas, size);
    _paintRings(canvas, geometry);
    _paintEarth(canvas, geometry, pulse: (math.sin(ts / 300) + 1) / 2);
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

  /// Earth: a glow that breathes, the planet, and its name
  /// (`index.html:870-876`).
  void _paintEarth(Canvas canvas, RadarGeometry geometry, {required double pulse}) {
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

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) =>
      oldDelegate.maxLd != maxLd || oldDelegate.zoom != zoom;
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

/// `rgba(147,168,202,.55)` — `--muted`, dimmed (`index.html:830`).
///
/// `final` rather than `const` because no const expression can derive one
/// colour's alpha from another. It costs nothing per frame: a top-level `final`
/// is computed once, on first access, and the labels it paints are themselves
/// laid out once and cached (see `_Label`).
final Color _ringLabelColour = Palette.muted.withValues(alpha: 0.55);

/// `rgba(120,180,255,.12)` (`index.html:873`) — the atmosphere.
const Color _earthGlowColour = Color.fromRGBO(120, 180, 255, 0.12);

/// The planet's three stops (`index.html:872`): daylight, ocean, night.
const Color _earthLit = Color(0xFFA9DCFF);
const Color _earthOcean = Color(0xFF1C6FB0);
const Color _earthDark = Color(0xFF0C355C);

/// `rgba(147,168,202,.85)` — `--muted` again (`index.html:875`).
final Color _earthLabelColour = Palette.muted.withValues(alpha: 0.85);

/// Text on this canvas, laid out once and kept.
///
/// **Laying text out is by a distance the most expensive thing the radar does
/// per frame**, and there are only ever seven strings on it — six ring labels
/// and "Earth" — none of which ever change. Measuring them sixty times a second
/// would be the single biggest cost on the screen, spent on an answer that was
/// the same the last fifty-nine times (`CLAUDE.md:80`).
class _Label {
  factory _Label(String text, {required double fontSize, required Color colour}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        // No family: the prototype asks for `-apple-system, sans-serif`
        // (`index.html:824`), i.e. whatever the phone's own font is, which is
        // what leaving this null means here too.
        style: TextStyle(fontSize: fontSize, color: colour),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return _Label._(
      painter,
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );
  }

  const _Label._(this._painter, this._baseline);

  final TextPainter _painter;
  final double _baseline;

  /// Draws with [x] through the text's centre and [y] on its alphabetic
  /// baseline — canvas's `textAlign="center"` and its default `textBaseline`,
  /// which is what every `fillText` in `radarDraw` is positioned by.
  void paint(Canvas canvas, double x, double y) =>
      _painter.paint(canvas, Offset(x - _painter.width / 2, y - _baseline));
}

/// Keyed by the text, which is safe because each of the seven strings has
/// exactly one style. Bounded by [RadarGeometry.ringLds], so it cannot grow.
final Map<int, _Label> _ringLabels = <int, _Label>{};

_Label _ringLabel(int ld) => _ringLabels.putIfAbsent(
  ld,
  () => _Label(ringLabelText(ld), fontSize: 9, colour: _ringLabelColour),
);

final _Label _earthLabel = _Label('Earth', fontSize: 10, colour: _earthLabelColour);
