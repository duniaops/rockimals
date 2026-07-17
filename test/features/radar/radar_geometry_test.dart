import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';

/// The distance scale is the radar's one load-bearing claim: an animal's ring
/// *is* the app telling a child how close it came. So this pins the shape of
/// `radiusFor` rather than a handful of outputs — a linear scale, a missing
/// floor, or a log without the `k` offset would each pass a spot-check at the
/// ends and be wrong everywhere in between.
///
/// Pure Dart on purpose: no canvas, no binding, no device (there is no Xcode or
/// Android SDK here — see the plan's human-gated item). The maths is testable
/// today and is tested today.
void main() {
  // A phone-shaped field, and the numbers every expectation below is built from
  // rather than copied out of the implementation.
  const Size field = Size(390, 700);
  // Width-bound at this shape: min(390, 630)/2 - 28.
  final double r0 = math.min(field.width, field.height * 0.9) / 2 - 28; // 167
  const double inner = 42;

  group('RadarGeometry.radiusFor', () {
    const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);

    test('parks a zero-distance animal on the inner floor, clear of Earth', () {
      // The floor's entire reason to exist (`index.html:629`). Earth is a 15px
      // disc inside a glow that breathes out to 29px, so 42 is not an arbitrary
      // number — it is the smallest radius at which the closest animal in the
      // sky is still a separate, tappable thing rather than a chip sitting on
      // top of the planet. If this ever drops below ~30 the radar stops being
      // usable on exactly the animals a child most wants to tap.
      expect(geometry.radiusFor(0), inner);
      expect(inner, greaterThan(29));
    });

    test('reaches the outer radius exactly at maxLd', () {
      expect(geometry.radiusFor(60), closeTo(r0, 1e-9));
    });

    test('saturates beyond maxLd rather than running off the field', () {
      // `Math.min(ld, MAXLD)` (`index.html:630`). `maxLdFor` caps at 60 while
      // the feed happily contains rocks further out, so this is a real input,
      // not a defensive one.
      expect(geometry.radiusFor(200), closeTo(r0, 1e-9));
      expect(geometry.radiusFor(60000), closeTo(r0, 1e-9));
    });

    test('never goes backwards as an animal gets further away', () {
      double previous = -1;
      for (double ld = 0; ld <= 70; ld += 0.5) {
        final double radius = geometry.radiusFor(ld);
        expect(radius, greaterThanOrEqualTo(previous), reason: 'at $ld LD');
        previous = radius;
      }
    });

    test('is log-shaped: equal ratios of distance are equal steps outward', () {
      // The defining property, stated as something a linear scale cannot fake.
      // `radiusFor` is affine in `log10(ld + 0.25)`, so the distance whose
      // (ld+k) is the *geometric* mean of the two ends must land exactly
      // halfway out. Solve it here rather than hard-coding the answer.
      const double k = 0.25;
      final double geometricMean = math.sqrt(k * (60 + k)) - k;

      expect(geometry.radiusFor(geometricMean), closeTo((inner + r0) / 2, 1e-9));
      // ~3.6 LD — not 30. Sanity that the line above is testing the log and not
      // an arithmetic midpoint that a linear scale would also satisfy.
      expect(geometricMean, closeTo(3.63, 0.01));
    });

    test('spends half the field on the nearest 6% of the range', () {
      // What the log buys, in the terms the radar is for. Real approaches bunch
      // at the near end — most of a day's animals are within a few Moon-
      // distances — so a linear scale would pile them into the first 10px and
      // leave the rest of the screen empty. Here the inner 3.6 of 60 LD gets
      // half the radius, and 30 LD (the linear halfway point) is already out at
      // ~86% of the way.
      final double halfway = (inner + r0) / 2;
      expect(geometry.radiusFor(30), greaterThan(halfway));
      expect((geometry.radiusFor(30) - inner) / (r0 - inner), closeTo(0.874, 0.001));
    });

    test('tracks the field it is given rather than a fixed size', () {
      // `R0` is `min(W, H*0.9)/2 - 28` (`index.html:665`), so a narrow phone is
      // width-bound and a wide one height-bound. The floor is *not* scaled —
      // Earth is 15px on every device, so the gap that clears it is too.
      const RadarGeometry narrow = RadarGeometry(size: Size(300, 900), maxLd: 60);
      const RadarGeometry wide = RadarGeometry(size: Size(900, 300), maxLd: 60);

      expect(narrow.r0, 300 / 2 - 28);
      expect(wide.r0, (300 * 0.9) / 2 - 28);
      expect(narrow.radiusFor(0), inner);
      expect(wide.radiusFor(0), inner);
    });
  });

  group('RadarGeometry.center', () {
    test('sits above the middle to clear the overlay', () {
      // `cy = H*0.46` (`index.html:664`) — the home overlay's title and stat
      // strip occupy the top of this same box, so Earth is nudged up out from
      // under them. A centred radar would put the planet behind the wordmark.
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      expect(geometry.center, const Offset(195, 322));
      expect(geometry.center.dy, lessThan(field.height / 2));
    });
  });

  group('RadarGeometry.maxLdFor', () {
    test('reaches 5% past the furthest animal in the sky', () {
      // The margin that keeps the furthest animal just inside the outer ring
      // instead of sitting on the edge of the screen.
      expect(RadarGeometry.maxLdFor(_sky(<double>[3, 20, 11])), closeTo(21, 1e-9));
    });

    test('floors at 8 LD when the whole sky is close', () {
      // Without the floor, a day where nothing came further than half a Moon-
      // distance would zoom the scale so far in that the rings stop meaning
      // anything — and every ring but the 1× would vanish with them.
      expect(RadarGeometry.maxLdFor(_sky(<double>[0.2, 0.5])), closeTo(8.4, 1e-9));
      // The floor is on the *max*, then the headroom applies: 8 × 1.05.
      expect(RadarGeometry.maxLdFor(_sky(<double>[7.9])), closeTo(8.4, 1e-9));
      expect(RadarGeometry.maxLdFor(_sky(<double>[9])), closeTo(9.45, 1e-9));
    });

    test('caps at 60 LD so one distant animal cannot squash the rest', () {
      // The feed routinely carries rocks far past 60. Without the cap, one of
      // them at 400 LD would push every other animal in the sky into the first
      // few pixels around Earth.
      expect(RadarGeometry.maxLdFor(_sky(<double>[2, 400])), 60);
      // 57.2 × 1.05 = 60.06 — the cap bites just under the raw 60 mark.
      expect(RadarGeometry.maxLdFor(_sky(<double>[57.2])), 60);
      expect(RadarGeometry.maxLdFor(_sky(<double>[57])), closeTo(59.85, 1e-9));
    });

    test('answers a usable field for an empty sky rather than dividing by zero',
        () {
      // The app is never in this state — the repository substitutes the sample
      // sky rather than hand anyone an empty feed — but `radiusFor` divides by
      // `log10(maxLd + k) - log10(k)`, so a zero here would poison every
      // radius on the screen with NaN.
      expect(RadarGeometry.maxLdFor(const <Asteroid>[]), closeTo(8.4, 1e-9));
      expect(
        const RadarGeometry(size: field, maxLd: 8.4).radiusFor(1),
        isNot(isNaN),
      );
    });
  });

  group('RadarGeometry.visibleRings', () {
    test('offers all six rings on a sky that reaches them', () {
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      expect(
        geometry.visibleRings(zoom: 1).map((r) => r.ld),
        <int>[1, 2, 5, 10, 20, 50],
      );
    });

    test('drops rings the sky does not reach', () {
      // `specs/02-live-radar.md:19` lists the six as if they were fixed;
      // `index.html:825` filters them by `MAXLD`, and the prototype wins. A 50×
      // ring on a quiet day would claim the field reaches somewhere it does
      // not — the rings are the radar's legend, so a ring that is a lie is
      // worse than a ring that is missing.
      const RadarGeometry quiet = RadarGeometry(size: field, maxLd: 8.4);
      expect(quiet.visibleRings(zoom: 1).map((r) => r.ld), <int>[1, 2, 5]);
    });

    test('keeps a ring exactly on maxLd', () {
      // `l <= MAXLD`, not `<`. A sky whose furthest animal is at 19.05 LD gives
      // maxLd 20.0025 and keeps its 20× ring, with the animal just inside it.
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 20);
      expect(geometry.visibleRings(zoom: 1).map((r) => r.ld), <int>[1, 2, 5, 10, 20]);
    });

    test('reports each ring at its scaled radius', () {
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      final rings = geometry.visibleRings(zoom: 2);

      for (final ring in rings) {
        expect(ring.radius, closeTo(geometry.radiusFor(ring.ld.toDouble()) * 2, 1e-9));
      }
    });

    test('culls rings collapsed into a smudge on Earth', () {
      // The `rr < 7` half of `index.html:826`, and it bites the *inner* rings
      // first — they are the ones that collapse onto the planet, where a dashed
      // circle is a scribble rather than a scale.
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      expect(geometry.visibleRings(zoom: 0.05).map((r) => r.ld), <int>[20, 50]);
    });

    test('does not cull anything at the zoom floor the app actually allows', () {
      // **This half of `index.html:826` is unreachable through the UI, and that
      // is worth pinning rather than discovering later.** The smallest ring is
      // the 1×, and `radiusFor` floors at 42 — so the 1× never drops below
      // ~78px before zoom, and reaching the 7px cull needs zoom < 0.089. The
      // prototype clamps zoom to 0.35 (`index.html:689`, `695`, `697-698`), so
      // nothing a child can do gets near it.
      //
      // It is ported anyway: it is in the prototype, it costs one comparison,
      // and it is a real guard on `visibleRings` as a unit. But the plan item's
      // rationale — "this is what stops giant rings being stroked at the 6.5
      // zoom clamp" — is about the `rr > max(W, H)` half below, not this one.
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      final rings = geometry.visibleRings(zoom: 0.35);

      expect(rings.map((r) => r.ld), <int>[1, 2, 5, 10, 20, 50]);
      expect(rings.first.radius, closeTo(27.54, 0.01));
    });

    test('culls rings zoomed off the screen', () {
      // The `rr > max(W, H)` half — what stops the outer rings being stroked
      // far outside the field at the 6.5 zoom ceiling, which costs a frame and
      // draws nothing anyone can see.
      const RadarGeometry geometry = RadarGeometry(size: field, maxLd: 60);
      final visible = geometry.visibleRings(zoom: 6.5).map((r) => r.ld).toList();

      expect(visible, isNotEmpty, reason: 'the inner rings still fit');
      expect(visible, isNot(contains(50)), reason: '167 × 6.5 is way off-screen');
      for (final ring in geometry.visibleRings(zoom: 6.5)) {
        expect(ring.radius, lessThanOrEqualTo(field.longestSide));
      }
    });
  });

  group('chipSizeFor', () {
    test('matches the prototype for all 14 sample rocks', () {
      // Captured by slicing `index.html:846-848` out and `eval`-ing it over the
      // prototype's own `FALLBACK` — not derived by hand. The sizes are what a
      // child actually sees, and a wrong one is invisible in review: nothing
      // throws, an animal is just quietly the wrong size.
      const Map<String, ({double emoji, double chip})> expected =
          <String, ({double emoji, double chip})>{
        '2011 EW': (emoji: 21.81904789905254, chip: 15.709714487317827),
        '2006 QV89': (emoji: 18.032194302458574, chip: 12.983179897770173),
        '2020 SW': (emoji: 15, chip: 10.799999999999999),
        '433 Eros': (emoji: 28.8, chip: 20.736),
        '2004 BL86': (emoji: 23.58930768058237, chip: 16.984301530019305),
        '2012 DA14': (emoji: 17.093544180555362, chip: 12.30735180999986),
        '99942 Apophis': (emoji: 22.297394068305852, chip: 16.054123729180212),
        '2015 TB145': (emoji: 23.58930768058237, chip: 16.984301530019305),
        '2010 WC9': (emoji: 19.837955848367358, chip: 14.283328210824497),
        '2001 FO32': (emoji: 24.824011775106012, chip: 17.87328847807633),
        '2005 YU55': (emoji: 22.481105387053795, chip: 16.18639587867873),
        '2019 OK': (emoji: 19.837955848367358, chip: 14.283328210824497),
        '2018 LF16': (emoji: 20.9974509270196, chip: 15.118164667454112),
        '2013 TX68': (emoji: 17.465952331323194, chip: 12.575485678552699),
      };

      for (final Asteroid rock in kFallbackAsteroids) {
        final ({double emoji, double chip}) got = chipSizeFor(rock.diaMax);
        final ({double emoji, double chip}) want = expected[rock.name]!;
        expect(got.emoji, closeTo(want.emoji, 1e-9), reason: rock.name);
        expect(got.chip, closeTo(want.chip, 1e-9), reason: rock.name);
      }
    });

    test('keeps the smallest animal big enough to see and to tap', () {
      // The 15px floor (`index.html:847`) is the reachable one, and `2020 SW` —
      // a real 4m rock in the sample sky — is the record that reaches it. Drawn
      // to its logarithm it would be 12px; drawn to true scale next to a 16km
      // Eros it would be a fraction of a pixel. The floor is what makes it an
      // animal a child can find.
      expect(chipSizeFor(4).emoji, 15);
      expect(chipSizeFor(0).emoji, 15);
      // And just above it the size starts telling the truth again.
      expect(chipSizeFor(50).emoji, greaterThan(15));
    });

    test('never lets one mountain swallow the sky', () {
      // `rad`'s 9 cap (`index.html:846`) — the other reachable bound. `433 Eros`
      // is 16.8km and hits it; so does a rock ten times bigger. Without it a
      // whale would be drawn at 60px and cover its neighbours.
      expect(chipSizeFor(16800).emoji, 28.8);
      expect(chipSizeFor(168000).emoji, 28.8);
    });

    test('the two dead clamp bounds never fire, at any real diameter', () {
      // Ported from the prototype and provably unreachable, so this pins *why*
      // rather than leaving the next reader hunting for the input that triggers
      // them — the `rr < 7` ring cull's situation exactly.
      //
      //  * `rad`'s 2.6 floor: `log10(dia+1) >= 0` for any `dia >= 0`, so `rad`
      //    is already >= 2.6 before the clamp sees it.
      //  * `emoji`'s 30 ceiling: `rad` caps at 9, so `emoji` peaks at 28.8.
      for (double dia = 0; dia <= 100000; dia += dia < 100 ? 0.5 : 250) {
        final double emoji = chipSizeFor(dia).emoji;
        expect(emoji, greaterThanOrEqualTo(15));
        expect(
          emoji,
          lessThanOrEqualTo(28.8),
          reason: 'the 30 ceiling is unreachable; dia $dia',
        );
      }
    });

    test('the token is always smaller than the animal standing in it', () {
      // `chip = em*0.72` (`index.html:848`) — the emoji overhangs its token,
      // which is what makes the animal read as the subject and the token as
      // something it is sitting in rather than a plate it is served on.
      for (final Asteroid rock in kFallbackAsteroids) {
        final ({double emoji, double chip}) size = chipSizeFor(rock.diaMax);
        expect(size.chip, lessThan(size.emoji));
        expect(size.chip, closeTo(size.emoji * 0.72, 1e-12));
      }
    });

    test('bigger rocks are never drawn smaller', () {
      // The ordering is the only honest thing the size on screen claims: it is a
      // hint, not a scale (the real answer is `sizeLabel` and the size-comparison
      // module). But a bigger rock drawn *smaller* would be a lie, and a log
      // scale with two clamps is exactly where one could hide.
      double last = 0;
      for (double dia = 0; dia <= 20000; dia += 1) {
        final double emoji = chipSizeFor(dia).emoji;
        expect(emoji, greaterThanOrEqualTo(last), reason: 'dia $dia');
        last = emoji;
      }
    });
  });

  group('moonRadius', () {
    test('is the 1× ring, at every zoom', () {
      // The Moon rides its own ring, so the two must scale as one thing. If they
      // could come apart, the unit every distance on this screen is quoted in
      // would be sitting somewhere other than where the screen says it is.
      const RadarGeometry geometry = RadarGeometry(size: Size(390, 700), maxLd: 60);
      for (final double zoom in <double>[0.35, 1, 2.5, 6.5]) {
        expect(
          geometry.moonRadius(zoom: zoom),
          closeTo(geometry.radiusFor(1) * zoom, 1e-12),
          reason: 'zoom $zoom',
        );
      }
    });
  });
}

/// A sky at the given Moon-distances. Nothing but `missLunar` matters here, so
/// the rest is plausible filler rather than a real capture.
List<Asteroid> _sky(List<double> missLunar) => <Asteroid>[
  for (final double ld in missLunar)
    Asteroid(
      name: '2026 LD$ld',
      diaMax: 100,
      diaMin: 50,
      hazardous: false,
      missLunar: ld,
      missKm: ld * 384400,
      velKps: 12,
      mag: 22,
      jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
      date: '2026-07-17',
    ),
];
