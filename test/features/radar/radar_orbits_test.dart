import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';

/// Where the animals are and how they move.
///
/// **The expected seeds are the prototype's own output, not hand-derived
/// numbers.** `index.html:642-645` was sliced out and `eval`-ed over its own
/// `FALLBACK` — the technique the FALLBACK, naming, and power items all used,
/// and which caught six wrong guesses out of eight the one time it was checked
/// against a careful read. All 14 rocks are covered rather than a sample,
/// because the sample sky *is* the whole population of the offline radar and 14
/// cost no more to capture than 3.
void main() {
  group('RadarOrbit.seed', () {
    test('matches the prototype seed for seed, for all 14 sample rocks', () {
      // `phase: (i*61%360)*π/180`, `angVel: 0.16/sqrt(max(0.5, missLunar))`,
      // `rOff: ((i%5)-2)*3.4` — captured from `index.html:642-645`.
      const List<({String name, double phase, double angVel, double rOff})> expected =
          <({String name, double phase, double angVel, double rOff})>[
        (name: '2011 EW', phase: 0, angVel: 0.045436946739765185, rOff: -6.8),
        (name: '2006 QV89', phase: 1.064650843716541, angVel: 0.03680349649825889, rOff: -3.4),
        (name: '2020 SW', phase: 2.129301687433082, angVel: 0.22627416997969518, rOff: 0),
        (name: '433 Eros', phase: 3.193952531149623, angVel: 0.022188007849009168, rOff: 3.4),
        (name: '2004 BL86', phase: 4.258603374866164, angVel: 0.09087389347953037, rOff: 6.8),
        (name: '2012 DA14', phase: 5.323254218582705, angVel: 0.22627416997969518, rOff: -6.8),
        (name: '99942 Apophis', phase: 0.10471975511965977, angVel: 0.22627416997969518, rOff: -3.4),
        (name: '2015 TB145', phase: 1.1693705988362006, angVel: 0.14032928308912468, rOff: 0),
        (name: '2010 WC9', phase: 2.234021442552742, angVel: 0.22627416997969518, rOff: 3.4),
        (name: '2001 FO32', phase: 3.2986722862692828, angVel: 0.07016464154456234, rOff: 6.8),
        (name: '2005 YU55', phase: 4.363323129985823, angVel: 0.17354436625492495, rOff: -6.8),
        (name: '2019 OK', phase: 5.427973973702365, angVel: 0.22627416997969518, rOff: -3.4),
        (name: '2018 LF16', phase: 0.20943951023931953, angVel: 0.025298221281347035, rOff: 0),
        (name: '2013 TX68', phase: 1.2740903539558606, angVel: 0.042761798705987904, rOff: 3.4),
      ];

      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      expect(orbits.orbits, hasLength(expected.length));

      for (final (int i, RadarOrbit orbit) in orbits.orbits.indexed) {
        final ({String name, double phase, double angVel, double rOff}) want = expected[i];
        // The name is asserted too, so a reordering of `kFallbackAsteroids`
        // fails here as a *name* mismatch rather than as an inscrutable float
        // one — the index is the seed, so that reordering silently moves the
        // whole sky.
        expect(orbit.asteroid.name, want.name, reason: 'record $i');
        expect(orbit.phase, closeTo(want.phase, 1e-12), reason: want.name);
        expect(orbit.angVel, closeTo(want.angVel, 1e-12), reason: want.name);
        expect(orbit.rOff, closeTo(want.rOff, 1e-12), reason: want.name);
      }
    });

    test('flings consecutive animals apart rather than clustering them', () {
      // The point of 61: it is coprime with 360, so neighbours in the list land
      // a long way apart on the circle and the sky reads as scattered. A seed
      // of, say, 60 would put every sixth animal at the same angle — six neat
      // spokes, which is the one thing a "scattered sky" must not look like.
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      final Set<String> phases = <String>{
        for (final RadarOrbit o in orbits.orbits) o.phase.toStringAsFixed(6),
      };

      expect(
        phases,
        hasLength(orbits.orbits.length),
        reason: 'no two of the 14 share a starting angle',
      );
      // 61° apart, in radians, for the first pair — the gap the constant buys.
      expect(
        orbits.orbits[1].phase - orbits.orbits[0].phase,
        closeTo(61 * math.pi / 180, 1e-12),
      );
    });

    test('is deterministic — the same sky seeds the same radar, with nothing stored', () {
      // `CLAUDE.md:70`. Two independent seedings of the same list must agree on
      // every animal, or a child's sky rearranges itself between launches.
      final RadarOrbits a = RadarOrbits.seed(kFallbackAsteroids);
      final RadarOrbits b = RadarOrbits.seed(kFallbackAsteroids);

      for (final (int i, RadarOrbit orbit) in a.orbits.indexed) {
        expect(orbit.phase, b.orbits[i].phase);
        expect(orbit.angVel, b.orbits[i].angVel);
        expect(orbit.rOff, b.orbits[i].rOff);
        expect(orbit.critter.name, b.orbits[i].critter.name);
      }
    });

    test('floors the fastest animal, so nothing on the radar ever whirls', () {
      // `max(0.5, missLunar)` (`index.html:643`) caps angular speed at
      // 0.16/sqrt(0.5) = 0.226 rad/s — a lap in ~28s. Without the floor a rock
      // passing at 0.01 Moons would sweep at 1.6 rad/s, a lap in under four
      // seconds, on the screen `specs/02-live-radar.md:28` asks to be calm.
      const double fastest = 0.16 / 0.7071067811865476;
      for (final RadarOrbit orbit in RadarOrbits.seed(kFallbackAsteroids).orbits) {
        expect(orbit.angVel, lessThanOrEqualTo(fastest + 1e-12));
      }

      // A grazing rock gets the floor, not its own tiny distance.
      expect(
        RadarOrbit.seed(_rock(missLunar: 0.001), 0).angVel,
        closeTo(fastest, 1e-12),
      );
    });

    test('rings the close flybys, and reads the tag rather than the raw flag', () {
      // `CLAUDE.md:64`: the radar must never be the surface that leaks NASA's
      // word for it. A rock inside the Moon's distance wears the ring even
      // though NASA has not flagged it — which is `flybyTag`'s rule, not
      // `hazardous`.
      expect(RadarOrbit.seed(_rock(missLunar: 0.5), 0).isCloseFlyby, isTrue);
      expect(RadarOrbit.seed(_rock(missLunar: 5), 0).isCloseFlyby, isFalse);
      expect(
        RadarOrbit.seed(_rock(missLunar: 5, hazardous: true), 0).isCloseFlyby,
        isTrue,
        reason: 'flagged but far — still waving',
      );
    });
  });

  group('RadarOrbits.advance', () {
    test('moves every animal at its own rate, and the Moon at 0.32 rad/s', () {
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      final List<double> before = <double>[
        for (final RadarOrbit o in orbits.orbits) o.phase,
      ];

      // Four 10ms frames. The step is [FrameClock]'s to measure and to clamp —
      // this class is handed one and spends all of it, which is why the numbers
      // here are seconds rather than `Duration`s.
      for (int i = 0; i < 4; i++) {
        orbits.advance(0.01);
      }

      for (final (int i, RadarOrbit orbit) in orbits.orbits.indexed) {
        expect(orbit.phase, closeTo(before[i] + orbit.angVel * 0.04, 1e-9));
      }
      expect(orbits.moonPhase, closeTo(0.32 * 0.04, 1e-9));
    });

    test('accumulates rather than recomputing, so a pause can hold the sky still', () {
      // Why this is an integrator and not `phase0 + angVel*t`. Advancing to 1s
      // in one step and in fifty must agree — and the fifty-step path is the one
      // the play/pause item will interrupt.
      final RadarOrbits stepped = RadarOrbits.seed(kFallbackAsteroids);
      final List<double> before = <double>[
        for (final RadarOrbit o in stepped.orbits) o.phase,
      ];
      for (int i = 0; i < 50; i++) {
        stepped.advance(0.02);
      }

      expect(stepped.moonPhase, closeTo(0.32 * 1.0, 1e-9));
      for (final (int i, RadarOrbit orbit) in stepped.orbits.indexed) {
        expect(orbit.phase - before[i], closeTo(orbit.angVel * 1.0, 1e-9));
      }
    });
  });

  group('RadarOrbits.positionOf', () {
    const RadarGeometry geometry = RadarGeometry(size: Size(390, 700), maxLd: 60);

    test('adds the lane offset after zoom, never through it', () {
      // `radiusFor(ld)*zoom + rOff` (`index.html:845`). `rOff` is a few pixels
      // of separation between animals at the same distance, not a distance — so
      // zoom must not scale it. At the 6.5 ceiling a scaled 6.8px lane would
      // become 44px of pure fiction about how far away the animal is, on the
      // screen whose whole job is that number.
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      // `2011 EW`: index 0, so rOff is the full -6.8, and phase 0 puts it due
      // east of Earth where the offset is a clean x displacement.
      final RadarOrbit rock = orbits.orbits.first;
      expect(rock.rOff, -6.8);
      expect(rock.phase, 0);

      final double ring = geometry.radiusFor(rock.asteroid.missLunar);
      for (final double zoom in <double>[0.35, 1, 6.5]) {
        final Offset at = orbits.positionOf(rock, geometry: geometry, zoom: zoom, viewRot: 0);
        expect(
          at.dx - geometry.center.dx,
          closeTo(ring * zoom + rock.rOff, 1e-9),
          reason: 'the lane stays 6.8px at zoom $zoom',
        );
      }
    });

    test('places an animal on its own ring at its own angle', () {
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      final RadarOrbit rock = orbits.orbits[3]; // rOff 3.4, phase 3.19 rad
      final double radius = geometry.radiusFor(rock.asteroid.missLunar) + rock.rOff;
      final Offset at = orbits.positionOf(
        rock,
        geometry: geometry,
        zoom: 1,
        viewRot: 0,
      );

      expect((at - geometry.center).distance, closeTo(radius, 1e-9));
      expect((at - geometry.center).direction, closeTo(rock.phase - 2 * math.pi, 1e-9));
    });

    test('rides the Moon on the 1× ring, because that ring is its orbit', () {
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);

      for (final double zoom in <double>[0.35, 1, 6.5]) {
        final Offset moon = orbits.moonPosition(
          geometry: geometry,
          zoom: zoom,
          viewRot: 0,
        );
        // The ring and the Moon on it can never come apart: same radius, at
        // every zoom. A Moon drifting off its own ring would quietly break the
        // one comparison this whole screen is built on.
        expect(
          (moon - geometry.center).distance,
          closeTo(geometry.radiusFor(1) * zoom, 1e-9),
          reason: 'zoom $zoom',
        );
      }
    });

    test('sweeps the Moon a full lap in ~19.6 seconds', () {
      // 0.32 rad/s (`index.html:734`) — not the real Moon's month, which no
      // child would ever see move. It is the hand of a clock saying the sky is
      // live.
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      for (int i = 0; i < 982; i++) {
        orbits.advance(0.02);
      }

      expect(orbits.moonPhase, closeTo(2 * math.pi, 0.01));
    });
  });

  group('viewRot', () {
    const RadarGeometry geometry = RadarGeometry(size: Size(390, 700), maxLd: 60);

    test('turns every animal and the Moon by one shared rotation', () {
      // **The bug this exists to fail on.** `viewRot` is added at two call sites
      // (`index.html:837`, `845`), and an author who threads it through the
      // animals and forgets the Moon gets a screen that looks *almost* right:
      // the sky spins and the Moon stands still. Every distance on this radar is
      // read against the Moon's ring, so that is not a cosmetic slip — it is the
      // ruler coming loose from the thing being measured.
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      orbits.advance(0.05); // so the Moon is off its start

      const double turn = 0.7;
      double bearing(Offset at) => (at - geometry.center).direction;
      double turned(double a, double b) => _wrap(b - a);

      final double moonBefore = bearing(
        orbits.moonPosition(geometry: geometry, zoom: 1, viewRot: 0),
      );
      final double moonAfter = bearing(
        orbits.moonPosition(geometry: geometry, zoom: 1, viewRot: turn),
      );
      expect(turned(moonBefore, moonAfter), closeTo(turn, 1e-9));

      for (final RadarOrbit orbit in orbits.orbits) {
        final double before = bearing(
          orbits.positionOf(orbit, geometry: geometry, zoom: 1, viewRot: 0),
        );
        final double after = bearing(
          orbits.positionOf(orbit, geometry: geometry, zoom: 1, viewRot: turn),
        );
        expect(
          turned(before, after),
          closeTo(turn, 1e-9),
          reason: '${orbit.asteroid.name} must turn with the Moon, not past it',
        );
      }
    });

    test('is a view transform: it moves nobody and keeps every distance', () {
      // Spinning the field is a camera move, not an event in the sky. If
      // `viewRot` were ever folded into `phase` the animals would keep orbiting
      // from wherever the child let go — the drag would nudge the simulation —
      // and a rotation would have to be undone rather than simply set to 0 by
      // the ⤢ button.
      final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
      final List<double> phases =
          orbits.orbits.map((RadarOrbit o) => o.phase).toList();

      for (final RadarOrbit orbit in orbits.orbits) {
        final double resting =
            (orbits.positionOf(orbit, geometry: geometry, zoom: 1, viewRot: 0) -
                    geometry.center)
                .distance;
        final double spun =
            (orbits.positionOf(orbit, geometry: geometry, zoom: 1, viewRot: 2.4) -
                    geometry.center)
                .distance;
        // The whole point of rotating rather than re-placing: how far the animal
        // is from Earth is the one thing this screen must never get wrong, and a
        // rotation cannot touch it.
        expect(spun, closeTo(resting, 1e-9), reason: orbit.asteroid.name);
      }

      expect(
        orbits.orbits.map((RadarOrbit o) => o.phase),
        phases,
        reason: 'asking where an animal is drawn must not move it',
      );
    });
  });

  group('RadarOrbits.hitTest', () {
    const RadarGeometry geometry = RadarGeometry(size: Size(390, 700), maxLd: 60);
    final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);

    Offset centreOf(RadarOrbit orbit, {double viewRot = 0}) =>
        orbits.positionOf(orbit, geometry: geometry, zoom: 1, viewRot: viewRot);

    RadarOrbit? hit(Offset at, {double viewRot = 0}) =>
        orbits.hitTest(at, geometry: geometry, zoom: 1, viewRot: viewRot);

    test('selects the animal a tap lands on', () {
      final RadarOrbit target = orbits.orbits[4];
      expect(hit(centreOf(target)), same(target));
    });

    test('answers nothing for a tap on empty space', () {
      // Earth's own centre: every animal is held out past the 42px inner floor,
      // so nothing can be here. This is the tap that clears the selection.
      expect(hit(geometry.center), isNull);
    });

    test('reaches 12px past the animal, and stops', () {
      // The margin is what makes a Mouse tappable by a fingertip much wider than
      // it (`specs/02-live-radar.md:35`). Probed straight out from Earth so the
      // step is a clean radial distance, and on `2015 TB145` — 625m, the biggest
      // chip in the sample sky — because it is far enough from its neighbours
      // that nothing else can answer instead.
      final RadarOrbit target = orbits.orbits[7];
      expect(target.asteroid.name, '2015 TB145');
      final double reach = target.chipRadius + 12;
      final Offset out = (centreOf(target) - geometry.center) /
          (centreOf(target) - geometry.center).distance;

      expect(hit(centreOf(target) + out * (reach - 0.5)), same(target));
      expect(hit(centreOf(target) + out * (reach + 0.5)), isNull);
    });

    test('picks the nearest of two animals whose reaches overlap', () {
      // `if(d<bd && d<max(...))` (`index.html:711`) — nearest *among* those in
      // reach. A child aiming between two animals that overlap gets the one they
      // were closer to, rather than whichever the list happened to hold first.
      //
      // A bespoke pair rather than two of the sample sky's, because the sample
      // sky has no overlapping pair to borrow: consecutive animals are flung 61°
      // apart, so the two closest together on the field are still 133px apart.
      // These two are both jammed against the 42px inner floor, which is the one
      // place on this radar where animals really do crowd each other — and the
      // reason the floor exists at all (`specs/02-live-radar.md:53`).
      final RadarOrbits crowded = RadarOrbits.seed(<Asteroid>[
        _rock(missLunar: 0.01),
        _rock(missLunar: 0.01),
      ]);
      final RadarOrbit first = crowded.orbits[0];
      final RadarOrbit second = crowded.orbits[1];
      Offset at(RadarOrbit o) =>
          crowded.positionOf(o, geometry: geometry, zoom: 1, viewRot: 0);
      RadarOrbit? hitCrowded(Offset p) =>
          crowded.hitTest(p, geometry: geometry, zoom: 1, viewRot: 0);

      final Offset a = at(first);
      final Offset b = at(second);
      final Offset between = Offset.lerp(a, b, 0.5)!;

      expect(
        (a - b).distance,
        lessThan(first.chipRadius + 12 + (second.chipRadius + 12)),
        reason: 'the premise: their reaches must actually overlap',
      );
      // Just off the midpoint, either side: both animals are in reach of both
      // probes, so only "nearest" can separate them.
      expect(hitCrowded(Offset.lerp(between, a, 0.1)!), same(first));
      expect(hitCrowded(Offset.lerp(between, b, 0.1)!), same(second));
    });

    test('follows the animals when the field is spun', () {
      // The hit test and the painter must agree about where an animal is, or a
      // child drags the sky round and then taps a ghost. Both ask `positionOf`,
      // which is the point of it being a pure function of the same three inputs.
      const double turn = 1.9;
      final RadarOrbit target = orbits.orbits[4];

      expect(hit(centreOf(target, viewRot: turn), viewRot: turn), same(target));
      expect(
        hit(centreOf(target), viewRot: turn),
        isNot(same(target)),
        reason: 'where it used to be is not where it is',
      );
    });

    test('never needs its own 20px floor — the smallest animal is bigger', () {
      // `max(20, chipRadius+12)` (`index.html:711`), and the 20 is dead: the
      // emoji floor of 15 makes the smallest chip 10.8, so the smallest reach
      // any animal can have is 22.8. Ported anyway, as the prototype's, exactly
      // like `visibleRings`' 7px cull and two of `chipSizeFor`'s clamp bounds —
      // and pinned here so the next reader does not go hunting for the animal
      // small enough to need it.
      //
      // Swept over the whole diameter range rather than the sample sky, since
      // the claim is about the function and not about today's rocks.
      for (double dia = 0; dia <= 6000; dia += 0.5) {
        final ({double emoji, double chip}) size = chipSizeFor(dia);
        expect(
          size.chip + 12,
          greaterThan(20),
          reason: 'a ${dia}m animal would have made the floor bite',
        );
      }
    });
  });
}

/// An angle folded into (-π, π], so two bearings either side of due west can be
/// subtracted without answering ~2π.
double _wrap(double radians) {
  final double turns = (radians + math.pi) / (2 * math.pi);
  return (radians + math.pi) - (2 * math.pi) * turns.floorToDouble() - math.pi;
}

/// A rock with only the fields the radar reads, so a test can say what it means.
Asteroid _rock({required double missLunar, bool hazardous = false}) => Asteroid(
  name: 'probe',
  diaMax: 100,
  diaMin: 50,
  hazardous: hazardous,
  missLunar: missLunar,
  missKm: missLunar * 384400,
  velKps: 10,
  mag: 20,
  jpl: 'https://example.test',
  date: 'sample',
);
