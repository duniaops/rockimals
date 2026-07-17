import 'dart:math' as math;

import 'package:flutter/painting.dart';
// Prefixed because [RadarOrbit.critter] is a field and `critter()` is a
// function: unprefixed, the field shadows the function inside the very factory
// that has to call it.
import 'package:rockimals/core/animals/animal_system.dart' as animals;
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';

/// One animal on the radar: which rock it is, everything about how it is drawn
/// that never changes, and where it currently is on its ring.
///
/// A port of one entry of `Radar.seeds` (`index.html:642-645`) with the
/// per-animal constants `radarDraw` recomputes every frame folded in — the
/// critter, the chip sizes, and the flyby tag are all pure functions of the
/// asteroid, so computing them sixty times a second would be sixty hashes and
/// sixty logarithms per animal for an answer that cannot change
/// (`CLAUDE.md:80`).
class RadarOrbit {
  RadarOrbit._({
    required this.asteroid,
    required this.critter,
    required this.phase,
    required this.angVel,
    required this.rOff,
    required this.emojiSize,
    required this.chipRadius,
    required this.isCloseFlyby,
  });

  /// Seeds one animal from its rock and its [index] in the radar's list.
  ///
  /// **The index is load-bearing and it is the list's, not the sky's.** Both
  /// [phase] and [rOff] are derived from it, so the same asteroid at a different
  /// position in the list orbits from a different place — which is why plan
  /// decision 9 insists the radar is fed the full `asteroids` list rather than
  /// `todayList`, and why `kFallbackAsteroids`' source order is pinned by its
  /// own test.
  factory RadarOrbit.seed(Asteroid asteroid, int index) {
    final ({double emoji, double chip}) size = chipSizeFor(asteroid.diaMax);

    return RadarOrbit._(
      asteroid: asteroid,
      critter: animals.critter(asteroid),
      // `(i*61 % 360)°` (`index.html:644`). 61 is coprime with 360, so
      // consecutive animals are flung a long way apart around the circle and
      // 360 of them would go all the way round before repeating. The result is
      // a sky that looks scattered while being entirely deterministic — the
      // same rock is in the same place on every launch, with nothing stored
      // (`CLAUDE.md:70`).
      phase: (index * 61 % 360) * math.pi / 180,
      // `0.16 / sqrt(max(0.5, missLunar))` (`index.html:643`). Closer animals
      // sweep faster, which is Kepler's third law in spirit — near things really
      // do go round quicker — without being a simulation of anything. The 0.5
      // floor caps the fastest animal at ~0.23 rad/s, so a rock that grazes the
      // planet drifts rather than whirls: `specs/02-live-radar.md:28` asks for
      // calm, and the closest rock is exactly where calm is hardest to keep.
      angVel: 0.16 / math.sqrt(math.max(0.5, asteroid.missLunar)),
      // `((i%5)-2) * 3.4` (`index.html:645`) — a fixed ±6.8px ladder of five
      // rungs, nudging each animal off the exact ring. Animals at similar
      // distances would otherwise ride the same circle and overlap on it; this
      // gives them lanes. It is added *after* zoom (see [RadarOrbits.positionOf]),
      // so it stays a constant few pixels of separation rather than growing into
      // a visible error in the distance it is meant to be showing.
      rOff: ((index % 5) - 2) * 3.4,
      emojiSize: size.emoji,
      chipRadius: size.chip,
      isCloseFlyby:
          animals.flybyTag(asteroid) == animals.FlybyTag.closeFlyby,
    );
  }

  final Asteroid asteroid;

  /// The animal this rock is — cached because `critter()` hashes the designation.
  final animals.Critter critter;

  /// Where the animal is on its ring, in radians. The only thing here that
  /// moves; [RadarOrbits.advance] is what moves it.
  double phase;

  /// Radians per second.
  final double angVel;

  /// The animal's lane: a few pixels in or out of its true ring.
  final double rOff;

  /// The emoji's font size, and the radius of the navy token behind it.
  final double emojiSize;
  final double chipRadius;

  /// Whether this animal wears the orange ring (`index.html:854`).
  ///
  /// Precomputed from `flybyTag()` rather than from the raw `hazardous` flag:
  /// the radar must never be the one surface that leaks NASA's word for it
  /// (`CLAUDE.md:64`), and this way the ring and the badge on the detail screen
  /// cannot disagree about which animals are waving.
  final bool isCloseFlyby;
}

/// Every animal on the radar and the Moon, and the clock that moves them —
/// `radarLoop`'s integration step (`index.html:729-739`).
///
/// **This is deliberately mutable and deliberately integrated, rather than a
/// pure function of elapsed time.** `phase = phase0 + angVel * t` would be
/// equivalent today and would be wrong the moment either of the next two items
/// lands: the play/pause item stops the clock without moving the animals back,
/// and this class's [advance] already refuses to hand a slow frame a big jump.
/// Both are properties of an accumulator, not of a formula.
class RadarOrbits {
  RadarOrbits._(this.orbits);

  /// Seeds a radar from its sky. Cheap enough to do per load and far too
  /// expensive to do per frame.
  factory RadarOrbits.seed(List<Asteroid> asteroids) => RadarOrbits._(
    <RadarOrbit>[
      for (final (int i, Asteroid a) in asteroids.indexed) RadarOrbit.seed(a, i),
    ],
  );

  final List<RadarOrbit> orbits;

  /// The Moon's own angle around the 1× ring (`index.html:626`, `734`).
  double moonPhase = 0;

  /// The last [advance] timestamp, so a dt can be taken from a clock that only
  /// reports elapsed time. `Radar.last` (`index.html:730`).
  Duration _last = Duration.zero;

  /// Moves every animal and the Moon on to where [elapsed] says they should be.
  ///
  /// **The dt clamp is the whole reason this takes a duration rather than a
  /// dt.** `min(0.05, …)` (`index.html:730`) means a frame that took longer than
  /// 50ms — the app was backgrounded, the phone was busy, the tab was hidden —
  /// advances the sky by 50ms and no more. Without it, returning to the radar
  /// after a minute away teleports every animal to a new angle in one frame,
  /// which is exactly the jolt `specs/02-live-radar.md:28` asks the screen never
  /// to give. The sky simply falls behind instead, which nobody can tell,
  /// because there is nothing to be behind: these orbits are decorative, not a
  /// prediction of where the rock really is.
  void advance(Duration elapsed) {
    final double dt = math.min(
      _maxFrame,
      (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond,
    );
    _last = elapsed;

    for (final RadarOrbit orbit in orbits) {
      orbit.phase += orbit.angVel * dt;
    }
    moonPhase += _moonAngVel * dt;
  }

  /// Where an animal is on the field, in pixels.
  ///
  /// **[RadarOrbit.rOff] is added after [zoom], not scaled by it**
  /// (`index.html:845`) — it is a drawing nudge that stops animals at similar
  /// distances from overlapping, not a distance. Zooming it would turn a few
  /// pixels of lane separation at rest into a 44px lie about how far away the
  /// animal is at the 6.5 ceiling, on a screen whose entire job is to show that
  /// distance honestly.
  ///
  /// [viewRot] is added to the animal's own [RadarOrbit.phase]
  /// (`index.html:845`) rather than [phase] being changed, which is what makes
  /// the drag a *view* transform: let go and the sky keeps orbiting from where
  /// the child left it, because nothing about where the animals are was ever
  /// touched.
  Offset positionOf(
    RadarOrbit orbit, {
    required RadarGeometry geometry,
    required double zoom,
    required double viewRot,
  }) {
    final double radius =
        geometry.radiusFor(orbit.asteroid.missLunar) * zoom + orbit.rOff;
    final double angle = orbit.phase + viewRot;
    return geometry.center + Offset(math.cos(angle), math.sin(angle)) * radius;
  }

  /// Where the Moon is (`index.html:835-837`).
  ///
  /// **[viewRot] is required here for the same reason it is above, and this is
  /// the pair that has to agree.** The Moon rides the 1× ring and every animal's
  /// distance is read against it, so a rotation applied to the animals and not to
  /// the Moon would spin the whole sky around a Moon standing still — the one
  /// object out there a child already knows, turned into the one thing that does
  /// not move with everything else. Neither takes a default: a caller that forgets
  /// [viewRot] on exactly one of these two is precisely that bug, and it does not
  /// compile.
  Offset moonPosition({
    required RadarGeometry geometry,
    required double zoom,
    required double viewRot,
  }) {
    final double angle = moonPhase + viewRot;
    return geometry.center +
        Offset(math.cos(angle), math.sin(angle)) *
            geometry.moonRadius(zoom: zoom);
  }

  /// The animal under a tap at [at], or null for empty space — `radarHit`
  /// (`index.html:707-713`).
  ///
  /// **Nearest wins, but only among animals within their own reach**: an animal
  /// is a candidate when the tap is inside `max(20, chipRadius + 12)` of it, and
  /// of the candidates the closest is selected. So a tap that lands between two
  /// overlapping animals picks one rather than neither, and a tap in open space
  /// picks nothing.
  ///
  /// **The reach is bigger than the animal on purpose.** The 12px of margin is
  /// what makes a Mouse tappable by a five-year-old with a fingertip much wider
  /// than the 21px token it is aiming at (`specs/02-live-radar.md:35`, "an easy
  /// tap radius").
  ///
  /// **The 20px floor is dead, and it is ported anyway** — the third time on this
  /// screen (`RadarGeometry.visibleRings`' 7px cull and two of `chipSizeFor`'s
  /// four clamp bounds are the others). [RadarOrbit.chipRadius] is `emojiSize *
  /// 0.72` over an emoji floored at 15, so the smallest reach any animal can have
  /// is `10.8 + 12 = 22.8` and the `max` never picks its own first argument. It
  /// costs one compare, it is the prototype's, and a test pins that it never
  /// fires so the next reader does not go hunting for the animal small enough to
  /// need it.
  ///
  /// **Positions are recomputed here rather than read back from the last frame.**
  /// The prototype hit-tests against `a._sx/_sy/_sr`, which `radarDraw` writes
  /// into every asteroid as it paints them (`index.html:850`), because the draw
  /// had just computed them anyway. This port keeps the answer a pure function of
  /// the same inputs the painter uses: it costs one cosine per animal on a tap
  /// (not per frame), and it means a tap cannot be answered by a stale frame or
  /// by a cache the painter forgot to fill. The one behaviour that rides on the
  /// prototype's cache is `if(a._sx==null) return` — an animal filtered off the
  /// field is unhittable (`index.html:843`, `710`). Nothing filters yet; the
  /// toggle-chips item that adds the Close-flybys filter owns making the two
  /// agree, and it has to, or a child taps a hidden animal.
  RadarOrbit? hitTest(
    Offset at, {
    required RadarGeometry geometry,
    required double zoom,
    required double viewRot,
  }) {
    RadarOrbit? best;
    double bestDistance = double.infinity;

    for (final RadarOrbit orbit in orbits) {
      final double distance =
          (positionOf(orbit, geometry: geometry, zoom: zoom, viewRot: viewRot) -
                  at)
              .distance;
      if (distance < bestDistance &&
          distance < math.max(_minTapRadius, orbit.chipRadius + _tapMargin)) {
        bestDistance = distance;
        best = orbit;
      }
    }

    return best;
  }

  /// 0.32 rad/s (`index.html:734`) — a lap in ~19.6 seconds.
  ///
  /// Not the real Moon's month, and not meant to be: at 27 days a child would
  /// never see it move. It is the fastest thing on the radar because it is the
  /// one object out there they already know, so it reads as the hand of a clock
  /// telling them the sky is live.
  static const double _moonAngVel = 0.32;

  /// `min(0.05, …)` (`index.html:730`) — the longest step the sky will take.
  static const double _maxFrame = 0.05;

  /// The smallest reach a tap is ever given (`index.html:711`). Dead — see
  /// [hitTest].
  static const double _minTapRadius = 20;

  /// How far outside its own token an animal answers a tap
  /// (`index.html:711`).
  static const double _tapMargin = 12;
}
