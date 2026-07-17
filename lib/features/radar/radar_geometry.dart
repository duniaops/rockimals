import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// Where the radar puts things: the centre of the field, how far out it
/// reaches, and the scale that turns a miss distance in Moon-distances into a
/// radius in pixels.
///
/// A port of `radarResize()` (`index.html:659-666`), the `MAXLD` lines of
/// `homeInit()` (`index.html:638-639`), and `radiusFor()`
/// (`index.html:629-633`). It is a plain value class with no canvas in it on
/// purpose: this scale is the one piece of radar maths that can quietly lie to
/// a child — every animal's distance from Earth is *this function* — so it is
/// unit-testable without rendering anything.
///
/// [center] and [r0] are derived rather than stored so there is no way to build
/// a geometry whose centre disagrees with its size.
@immutable
class RadarGeometry {
  const RadarGeometry({required this.size, required this.maxLd});

  /// The radar field's size in logical pixels — the whole tab.
  final Size size;

  /// The Moon-distance the outer edge of the field represents. Use [maxLdFor];
  /// it is the only thing that produces a sane one.
  final double maxLd;

  /// `cx=W/2, cy=H*0.46` (`index.html:664`). Above the middle, not on it: the
  /// home overlay's title and stat strip sit across the top of the radar
  /// (`index.html:191`), so Earth is nudged up out from under them.
  Offset get center => Offset(size.width / 2, size.height * 0.46);

  /// The radius the outermost ring sits at — `min(W, H*0.9)/2 - 28`
  /// (`index.html:665`). The 28 is the margin the ring labels are drawn into.
  double get r0 => math.min(size.width, size.height * 0.9) / 2 - 28;

  /// How far from Earth an animal [ld] Moon-distances away is drawn, before
  /// zoom.
  ///
  /// **A log scale with a floor, and both halves matter.** Real approaches are
  /// bunched hard at the near end — most of a day's animals are inside a few
  /// Moon-distances while the odd one is fifty out — so a linear scale would
  /// pile almost every animal onto Earth and leave the rest of the screen
  /// empty. The log spreads them. The floor ([_innerRadius]) then holds even a
  /// zero-distance animal out at 42px, clear of Earth's 15px disc and its 29px
  /// glow, so the closest animals stay separate and tappable rather than
  /// becoming a scrum on top of the planet.
  ///
  /// Beyond [maxLd] this saturates at [r0] rather than running off the screen.
  double radiusFor(double ld) {
    final double capped = math.min(ld, maxLd);
    final double t =
        (_log10(capped + _k) - _log10(_k)) / (_log10(maxLd + _k) - _log10(_k));
    return _innerRadius + (r0 - _innerRadius) * t.clamp(0.0, 1.0);
  }

  /// The distance rings to draw, outward, each with the radius to draw it at.
  ///
  /// **Two culls, and the second is not redundant.** [ringLds] is the fixed set
  /// the prototype offers, but which of them exist is *data-dependent*: a quiet
  /// day where nothing comes further than 9 Moon-distances gets rings at 1, 2
  /// and 5 only, because a 50× ring on that day would claim the field reaches
  /// somewhere it does not. (`specs/02-live-radar.md:19` lists all six as if
  /// they were fixed; `index.html:825` filters them, and the prototype wins.)
  /// Then [zoom] scales what survives, and `rr < 7 || rr > max(W, H)`
  /// (`index.html:826`) drops what that leaves unreadable.
  ///
  /// **Only the second half of that ever fires in the app**, and the plan item
  /// that asked for this cull said the opposite, so it is worth writing down.
  /// Rings stroked far outside the field at the 6.5 zoom ceiling are real and
  /// are dropped here. But the 7px floor needs zoom below 0.089: the smallest
  /// ring is the 1×, [radiusFor]'s own floor holds it at ~78px, and zoom clamps
  /// at 0.35 (`index.html:689`). The comparison is ported and kept anyway — it
  /// is the prototype's, it costs one compare, and it is a real guard on this
  /// method as a unit — but nothing a child can do reaches it.
  ///
  /// Returns a fresh list per call, which is per frame. Six records of two
  /// fields is not the allocation `CLAUDE.md:80` is about, and pulling the loop
  /// out of the painter is what lets both culls be tested without a canvas.
  List<({int ld, double radius})> visibleRings({required double zoom}) {
    final double offScreen = math.max(size.width, size.height);
    final List<({int ld, double radius})> rings = <({int ld, double radius})>[];

    for (final int ld in ringLds) {
      if (ld > maxLd) continue;
      final double radius = radiusFor(ld.toDouble()) * zoom;
      if (radius < _minRingRadius || radius > offScreen) continue;
      rings.add((ld: ld, radius: radius));
    }

    return rings;
  }

  /// How far out the field reaches for a given sky: 5% beyond the furthest
  /// animal in it, floored at 8 and capped at 60 Moon-distances
  /// (`index.html:638-639`).
  ///
  /// The floor stops a day where everything is close from zooming the scale in
  /// so far that the rings mean nothing; the cap stops one distant animal from
  /// squashing every other animal onto Earth. The 5% is the margin that keeps
  /// that furthest animal just inside the outer ring instead of sitting exactly
  /// on the edge.
  ///
  /// **This is fed the full asteroid list, never `todayList`** (plan decision
  /// 9, `index.html:637`) — the radar draws the whole window, so a scale built
  /// from today's handful would size the field for animals it is not drawing.
  ///
  /// An empty sky answers 8.4, which is the floor doing its job: the app is
  /// never in that state (the repository substitutes the sample sky rather than
  /// hand anyone an empty feed), but the answer is a usable radar rather than a
  /// division by zero in [radiusFor].
  static double maxLdFor(Iterable<Asteroid> asteroids) {
    double furthest = _ldFloor;
    for (final Asteroid asteroid in asteroids) {
      if (asteroid.missLunar > furthest) furthest = asteroid.missLunar;
    }
    return math.min(_ldCeiling, furthest * _ldHeadroom);
  }

  /// The rings the prototype offers, in Moon-distances (`index.html:825`).
  /// Which of them are actually drawn is [visibleRings]'s answer, not this.
  static const List<int> ringLds = <int>[1, 2, 5, 10, 20, 50];

  /// The floor that keeps the closest animals off Earth (`index.html:630`).
  static const double _innerRadius = 42;

  /// The log's offset (`index.html:630`). It is what makes `radiusFor(0)`
  /// finite — `log10(0)` is negative infinity, and 0 Moon-distances is an
  /// impact, but the feed's smallest misses get close enough to matter.
  static const double _k = 0.25;

  /// Below this a ring is a smudge rather than a ring (`index.html:826`).
  static const double _minRingRadius = 7;

  static const double _ldFloor = 8;
  static const double _ldCeiling = 60;
  static const double _ldHeadroom = 1.05;

  static double _log10(double x) => math.log(x) / math.ln10;

  @override
  bool operator ==(Object other) =>
      other is RadarGeometry && other.size == size && other.maxLd == maxLd;

  @override
  int get hashCode => Object.hash(size, maxLd);

  @override
  String toString() =>
      'RadarGeometry(${size.width}×${size.height}, maxLd: $maxLd)';
}
