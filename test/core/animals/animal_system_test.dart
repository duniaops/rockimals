import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// These tests pin the size ladder against `index.html:416-419` and `431-441`.
///
/// The boundaries are the whole point. Every threshold is an *exclusive*
/// ceiling, so exactly 8 m is a Rabbit and not a Mouse — a one-off there does
/// not throw and is invisible on most data, it just hands a handful of real
/// asteroids the wrong animal, which is the app's most visible promise.
void main() {
  /// Only [diaMax] decides a species, so the rest is filler.
  Asteroid rock(double diaMax) => Asteroid(
    name: 'test rock',
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: false,
    missLunar: 1,
    missKm: 384400,
    velKps: 10,
    mag: 22,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: sampleDate,
  );

  /// A rock built for `power` and `flybyTag`, which — unlike the ladder — read
  /// four fields rather than one.
  ///
  /// [diaMax] and [missLunar] are required on purpose: they are the arithmetic
  /// under test, and a default would hide half of a score's inputs from anyone
  /// reading the expectation. [velKps] and [hazardous] default only because
  /// several tests genuinely do not care which they get.
  Asteroid probe({
    required double diaMax,
    required double missLunar,
    double velKps = 10,
    bool hazardous = false,
  }) => Asteroid(
    name: 'test rock',
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: hazardous,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: velKps,
    mag: 22,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: sampleDate,
  );

  group('the ladder', () {
    test('has the prototype\'s eight rungs, in ascending order', () {
      expect(kAnimals.map((Animal a) => a.species), <String>[
        'Mouse',
        'Rabbit',
        'Fox',
        'Tiger',
        'Bear',
        'Elephant',
        'Dino',
        'Whale',
      ]);
      expect(kAnimals.map((Animal a) => a.emoji), <String>[
        '🐭',
        '🐰',
        '🦊',
        '🐯',
        '🐻',
        '🐘',
        '🦕',
        '🐋',
      ]);
      expect(kAnimals.map((Animal a) => a.sizeLabel), <String>[
        'car-sized',
        'bus-sized',
        'house-sized',
        'plane-sized',
        'football-pitch-sized',
        'stadium-sized',
        'skyscraper-sized',
        'mountain-sized',
      ]);
      expect(kAnimals.last.max, double.infinity);
    });
  });

  group('animalFor', () {
    test('puts every boundary in the UPPER band', () {
      // The assertion this file exists for: `diaMax < rung.max` is strict, so
      // the boundary value belongs to the rung above.
      expect(animalFor(rock(8)).species, 'Rabbit');
      expect(animalFor(rock(20)).species, 'Fox');
      expect(animalFor(rock(50)).species, 'Tiger');
      expect(animalFor(rock(120)).species, 'Bear');
      expect(animalFor(rock(300)).species, 'Elephant');
      expect(animalFor(rock(800)).species, 'Dino');
      expect(animalFor(rock(2000)).species, 'Whale');
    });

    test('puts a hair under every boundary in the LOWER band', () {
      expect(animalFor(rock(7.999)).species, 'Mouse');
      expect(animalFor(rock(19.999)).species, 'Rabbit');
      expect(animalFor(rock(49.999)).species, 'Fox');
      expect(animalFor(rock(119.999)).species, 'Tiger');
      expect(animalFor(rock(299.999)).species, 'Bear');
      expect(animalFor(rock(799.999)).species, 'Elephant');
      expect(animalFor(rock(1999.999)).species, 'Dino');
    });

    test('covers the ends: 0 is a Mouse, 5000 is a Whale', () {
      expect(animalFor(rock(0)).species, 'Mouse');
      expect(animalFor(rock(0)).emoji, '🐭');
      expect(animalFor(rock(5000)).species, 'Whale');
      expect(animalFor(rock(5000)).emoji, '🐋');
    });

    test('is deterministic — the same rock is always the same animal', () {
      for (final Asteroid a in kFallbackAsteroids) {
        expect(animalFor(a).species, animalFor(a).species);
      }
    });

    test('gives the prototype\'s species for known fallback asteroids', () {
      // Spec 01's "compare 5-6 sample asteroids side-by-side with the
      // prototype", spanning five rungs. These expectations were not read off
      // the table by eye — they are the output of `index.html`'s own
      // `animalFor` and `sizeLabel`, eval-ed straight out of the file over its
      // own `FALLBACK` array. Six hand-guessed values were wrong before that
      // script ran, which is the whole argument for it.
      Animal of(String name) => animalFor(
        kFallbackAsteroids.firstWhere((Asteroid a) => a.name == name),
      );

      // 302 m — two metres over the 300 boundary, so this real record is the
      // one that catches an off-by-one in the Bear/Elephant rung.
      expect(of('2011 EW').species, 'Elephant');
      expect(of('2020 SW').species, 'Rabbit'); // 9 m
      expect(of('2012 DA14').species, 'Fox'); // 40 m
      expect(of('2006 QV89').species, 'Tiger'); // 60 m
      expect(of('2019 OK').species, 'Bear'); // 130 m
      expect(of('99942 Apophis').species, 'Elephant'); // 370 m
      expect(of('2001 FO32').species, 'Dino'); // 1080 m
      expect(of('433 Eros').species, 'Whale'); // 16800 m
    });

    test('gives the prototype\'s words for those same asteroids', () {
      String labelOf(String name) => sizeLabel(
        kFallbackAsteroids.firstWhere((Asteroid a) => a.name == name).diaMax,
      );

      expect(labelOf('2011 EW'), 'stadium-sized');
      expect(labelOf('2020 SW'), 'bus-sized');
      expect(labelOf('2012 DA14'), 'house-sized');
      expect(labelOf('2006 QV89'), 'plane-sized');
      expect(labelOf('2019 OK'), 'football-pitch-sized');
      expect(labelOf('2001 FO32'), 'skyscraper-sized');
      expect(labelOf('433 Eros'), 'mountain-sized');
    });
  });

  group('sizeLabel', () {
    test('turns every boundary into the UPPER band\'s words', () {
      expect(sizeLabel(8), 'bus-sized');
      expect(sizeLabel(20), 'house-sized');
      expect(sizeLabel(50), 'plane-sized');
      expect(sizeLabel(120), 'football-pitch-sized');
      expect(sizeLabel(300), 'stadium-sized');
      expect(sizeLabel(800), 'skyscraper-sized');
      expect(sizeLabel(2000), 'mountain-sized');
    });

    test('covers the ends', () {
      expect(sizeLabel(0), 'car-sized');
      expect(sizeLabel(7.999), 'car-sized');
      expect(sizeLabel(5000), 'mountain-sized');
    });

    test('agrees with the species ladder at every diameter', () {
      // The two ladders share one table precisely so this can never drift; the
      // prototype keeps them as separate functions with identical thresholds.
      for (final double m in <double>[
        0,
        7.999,
        8,
        19.999,
        20,
        49.999,
        50,
        119.999,
        120,
        299.999,
        300,
        799.999,
        800,
        1999.999,
        2000,
        5000,
      ]) {
        expect(sizeLabel(m), animalFor(rock(m)).sizeLabel, reason: '$m m');
      }
    });

    test('never leaks a raw measurement into the kid vocabulary', () {
      // The guardrail: no giant raw numbers in the main flow. Every label is
      // an object a child knows.
      for (final Animal rung in kAnimals) {
        expect(rung.sizeLabel, isNot(contains(RegExp(r'\d'))));
        expect(rung.sizeLabel, endsWith('-sized'));
      }
    });
  });

  group('hashStr', () {
    /// Bit-exact expectations, captured by running `index.html`'s own
    /// `hashStr` (lines 430-444, sliced out and evaluated) over its own
    /// `FALLBACK` — not by hand-computing djb2, which is exactly the sort of
    /// arithmetic that looks right and is not.
    ///
    /// These pin the `& 0xFFFFFFFF`. JS wraps to unsigned 32-bit at every step
    /// via `>>> 0`; Dart's 64-bit ints do not, so an unmasked port agrees on
    /// short strings and then silently diverges once `h` passes 2^32 — around
    /// the sixth character, i.e. on every real designation.
    const Map<String, int> protoHashes = <String, int>{
      '2011 EW': 1559158165,
      '2006 QV89': 4143909479,
      '2020 SW': 1555571681,
      '433 Eros': 1415771290,
      '2004 BL86': 4221453315,
      '2012 DA14': 1218009828,
      '99942 Apophis': 1781046886,
      '2015 TB145': 2776603749,
      '2010 WC9': 4204114315,
      '2001 FO32': 119792334,
      '2005 YU55': 4259301678,
      '2019 OK': 1559445451,
      '2018 LF16': 1608940131,
      '2013 TX68': 1333611687,
    };

    test('is bit-exact with the prototype for all 14 designations', () {
      protoHashes.forEach((String designation, int expected) {
        expect(hashStr(designation), expected, reason: designation);
      });
    });

    test('matches the prototype on the seeds that bracket the mask', () {
      // Empty: the loop never runs, so the answer is the bare seed.
      expect(hashStr(''), 5381);
      // One character: 5381 * 33 ^ 65, still far below 2^32 — an unmasked
      // implementation agrees here, which is why this case alone proves
      // nothing and the 14 above are the real check.
      expect(hashStr('A'), 177636);
      // The two live numbered-asteroid designations, whose real NeoWs form
      // keeps the parenthesised group (see the plan's open item on the
      // grown-up facts panel). Pinned so that if that item ever changes what
      // `name` holds, the renaming it causes fails loudly here.
      expect(hashStr('433 Eros A898 PA'), 1864719859);
      expect(hashStr('99942 Apophis 2004 MN4'), 1520843479);
    });

    test('never leaves 32 bits, however long the seed', () {
      // The mask is the only thing bounding this; without it `h` runs away
      // to 64 bits and `% kNamePool.length` starts picking different names.
      for (final String s in <String>[
        '2011 EW',
        '99942 Apophis',
        'A' * 200,
        kFallbackAsteroids.map((Asteroid a) => a.name).join(),
      ]) {
        expect(hashStr(s), inInclusiveRange(0, 0xFFFFFFFF), reason: s);
      }
    });

    test('is stable across calls', () {
      // Determinism with no storage is the promise (CLAUDE.md:70); a hash that
      // drifted would rename a child's followed animal between launches.
      for (final Asteroid a in kFallbackAsteroids) {
        expect(hashStr(a.name), hashStr(a.name), reason: a.name);
      }
    });
  });

  group('critter', () {
    /// The prototype's own `critter()` output for its own `FALLBACK`, captured
    /// the same way. This is the user-visible end of the hash: these are the
    /// exact 14 names a child sees offline today.
    const Map<String, String> protoNames = <String, String>{
      '2011 EW': 'Mango the Elephant',
      '2006 QV89': 'Gizmo the Tiger',
      '2020 SW': 'Olive the Rabbit',
      '433 Eros': 'Pip the Whale',
      '2004 BL86': 'Rocky the Elephant',
      '2012 DA14': 'Ziggy the Fox',
      '99942 Apophis': 'Suki the Elephant',
      '2015 TB145': 'Teddy the Elephant',
      '2010 WC9': 'Bruno the Bear',
      '2001 FO32': 'Luna the Dino',
      '2005 YU55': 'Luna the Elephant',
      '2019 OK': 'Bruno the Bear',
      '2018 LF16': 'Rocky the Bear',
      '2013 TX68': 'Biscuit the Fox',
    };

    test('names every fallback asteroid exactly as the prototype does', () {
      for (final Asteroid a in kFallbackAsteroids) {
        expect(critter(a).name, protoNames[a.name], reason: a.name);
      }
    });

    test('carries the rung the diameter picked', () {
      for (final Asteroid a in kFallbackAsteroids) {
        expect(critter(a).animal, same(animalFor(a)), reason: a.name);
      }
    });

    test('is deterministic: the same rock is always the same animal', () {
      // No storage, no counter — both inputs are facts about the asteroid.
      for (final Asteroid a in kFallbackAsteroids) {
        expect(critter(a).name, critter(a).name, reason: a.name);
      }
    });

    test('gives two rocks of one species different names', () {
      // Not a property of the algorithm — a fact about this data, and the
      // thing that makes the zoo feel like a zoo. Six of the 14 are Elephants;
      // if they were all "Luna the Elephant" the app would look broken.
      final Iterable<Asteroid> elephants = kFallbackAsteroids.where(
        (Asteroid a) => animalFor(a).species == 'Elephant',
      );
      expect(elephants.length, greaterThan(1));
      expect(
        elephants.map((Asteroid a) => critter(a).name).toSet().length,
        elephants.length,
      );
    });

    test('draws only from the name pool', () {
      for (final Asteroid a in kFallbackAsteroids) {
        expect(kNamePool, contains(critter(a).first), reason: a.name);
      }
    });
  });

  group('the name pool', () {
    test('is the prototype\'s 24 names, in order', () {
      // Order is load-bearing: `hash % length` indexes it, so a reorder or a
      // 25th name renames the entire sky.
      expect(kNamePool.length, 24);
      expect(kNamePool.first, 'Milo');
      expect(kNamePool.last, 'Gizmo');
      expect(kNamePool[13], 'Mango');
    });

    test('has no duplicates', () {
      // Two rocks sharing a name is fine (the pool is small); the *pool*
      // holding a name twice would just be a typo, and would skew which name
      // a hash lands on.
      expect(kNamePool.toSet().length, kNamePool.length);
    });
  });

  group('power', () {
    /// Captured by slicing `index.html`'s own `danger()`/`threatIndex()`
    /// (lines 353-360) out and evaluating them over its own `FALLBACK` — the
    /// same technique the ladder and hash tests use, for the same reason: a
    /// four-term blend is precisely the arithmetic a careful hand-check gets
    /// wrong without anything throwing.
    ///
    /// Every one of the 14, not a sample of three, because they cost nothing
    /// and between them they span both saturating terms: `433 Eros` is 16.8 km
    /// (the top of the size scale) at 52 Moons (the floor of `prox`), while
    /// `2020 SW` is a 9 m pebble at 0.07 Moons (`prox` pinned to its cap).
    const Map<String, (double, int)> protoPower = <String, (double, int)>{
      '2011 EW': (27.339928100965185, 82),
      '2006 QV89': (18.170904611815384, 55),
      '2020 SW': (21.9, 66),
      '433 Eros': (39.03191779790207, 117),
      '2004 BL86': (34.90934131328841, 105),
      '2012 DA14': (27.381721377144288, 82),
      '99942 Apophis': (38.14658740875764, 114),
      '2015 TB145': (40.91531703691118, 123),
      '2010 WC9': (32.4776638831241, 97),
      '2001 FO32': (36.89808203923059, 111),
      '2005 YU55': (39.083854909137195, 117),
      '2019 OK': (33.777663883124106, 101),
      '2018 LF16': (23.02432902064877, 69),
      '2013 TX68': (17.675615580824726, 53),
    };

    test('matches the prototype for all 14 sample asteroids', () {
      for (final Asteroid a in kFallbackAsteroids) {
        final (double score, int stars) = protoPower[a.name]!;
        // The stars are exact — they are what a child reads. The raw score is
        // held to a tolerance because `log10` is the one term this port cannot
        // promise bit-for-bit: V8 implements it directly, Dart divides by
        // ln10, and they can land an ulp apart. 1e-9 is ~7 orders of magnitude
        // tighter than the smallest gap between any two of these scores, so it
        // still catches a wrong weight, a wrong term, or a dropped `+ 1`.
        expect(powerStars(a), stars, reason: a.name);
        expect(power(a), closeTo(score, 1e-9), reason: a.name);
      }
    });

    test('weighs the three terms exactly as the prototype does', () {
      // `2020 SW` lands on a whole number, which makes the blend legible:
      // size = log10(9 + 1) * 3 * 3 = 9, prox = min(6, 10 / 0.47) = 6, so
      // 6 * 2 = 12, speed = 8.1 / 9 = 0.9, and it is unflagged. 9 + 12 + 0.9.
      expect(
        power(probe(diaMax: 9, missLunar: 0.07, velKps: 8.1)),
        closeTo(21.9, 1e-9),
      );
    });

    test('adds 2.2 for a flagged rock and nothing else', () {
      // The only place the raw `hazardous` flag reaches a number.
      final double calm = power(probe(diaMax: 100, missLunar: 5, velKps: 12));
      final double flagged = power(
        probe(diaMax: 100, missLunar: 5, velKps: 12, hazardous: true),
      );
      expect(flagged - calm, closeTo(2.2, 1e-9));
    });

    test(
      'caps closeness at 6, so nothing inside ~1.27 Moons scores higher',
      () {
        // `10 / (missLunar + 0.4) >= 6` from 1.2666… Moons inward, so a rock
        // grazing the atmosphere and one at 1.2 Moons are equally close as far
        // as the score is concerned. Without the cap the term runs to 25 at
        // missLunar = 0 and a single grazing pebble outscores Eros.
        final double grazing = power(
          probe(diaMax: 100, missLunar: 0, velKps: 12),
        );
        final double atCap = power(
          probe(diaMax: 100, missLunar: 1.2, velKps: 12),
        );
        expect(grazing, closeTo(atCap, 1e-9));
        // And just outside the cap the term is live again, so this is a cap and
        // not a flat rate.
        expect(
          power(probe(diaMax: 100, missLunar: 3, velKps: 12)),
          lessThan(atCap),
        );
      },
    );

    test('stays finite and positive for a sub-metre rock', () {
      // The `+ 1` inside log10 and the `+ 0.4` inside prox are what keep this
      // from going negative and from dividing by ~0 respectively. A 0 m rock
      // is not real data, but it is what a garbled diameter rounds to.
      final double p = power(probe(diaMax: 0, missLunar: 0));
      expect(p, greaterThan(0));
      expect(p.isFinite, isTrue);
    });

    test('rises with size, closeness, and speed', () {
      // The direction of each term, independent of its weight — the property
      // a child is actually being taught by the Power Duel.
      final Asteroid base = probe(diaMax: 100, missLunar: 5, velKps: 12);
      expect(
        power(probe(diaMax: 1000, missLunar: 5, velKps: 12)),
        greaterThan(power(base)),
      );
      expect(
        power(probe(diaMax: 100, missLunar: 2, velKps: 12)),
        greaterThan(power(base)),
      );
      expect(
        power(probe(diaMax: 100, missLunar: 5, velKps: 30)),
        greaterThan(power(base)),
      );
    });

    test('is the unrounded score the games rank on', () {
      // The Duel and the Challenge compare `danger()` directly
      // (index.html:917,1037,1048) while the cards show the stars, so power
      // must separate two rocks that round to the same star count. These two
      // differ by 0.04 of a star — a tie if anything ranked on powerStars.
      final Asteroid a = probe(diaMax: 100, missLunar: 5, velKps: 12);
      final Asteroid b = probe(diaMax: 100, missLunar: 5, velKps: 12.12);
      expect(powerStars(a), powerStars(b));
      expect(power(a), lessThan(power(b)));
    });
  });

  group('flybyTag', () {
    test('waves at anything closer than the Moon', () {
      // The boundary is strict: exactly 1.0 Moons is just passing. The
      // prototype's `missLunar < 1`.
      expect(
        flybyTag(probe(diaMax: 100, missLunar: 0.99)),
        FlybyTag.closeFlyby,
      );
      expect(flybyTag(probe(diaMax: 100, missLunar: 1)), FlybyTag.justPassing);
      expect(
        flybyTag(probe(diaMax: 100, missLunar: 1.01)),
        FlybyTag.justPassing,
      );
    });

    test('waves at a flagged rock however far away it is', () {
      // `hazardous || missLunar < 1` — either alone is enough, which is why a
      // rock flagged at 40 Moons still gets the wave.
      expect(
        flybyTag(probe(diaMax: 100, missLunar: 0.99, hazardous: true)),
        FlybyTag.closeFlyby,
      );
      expect(
        flybyTag(probe(diaMax: 100, missLunar: 1, hazardous: true)),
        FlybyTag.closeFlyby,
      );
      expect(
        flybyTag(probe(diaMax: 100, missLunar: 40, hazardous: true)),
        FlybyTag.closeFlyby,
      );
    });

    test('matches the prototype for all 14 sample asteroids', () {
      // Captured from `index.html:445-447` over its own FALLBACK. Four are
      // just passing, which is the check that this is not the constant the
      // two boundary tests above would also pass.
      const Map<String, FlybyTag> protoTags = <String, FlybyTag>{
        '2011 EW': FlybyTag.closeFlyby,
        '2006 QV89': FlybyTag.justPassing,
        '2020 SW': FlybyTag.closeFlyby,
        '433 Eros': FlybyTag.justPassing,
        '2004 BL86': FlybyTag.closeFlyby,
        '2012 DA14': FlybyTag.closeFlyby,
        '99942 Apophis': FlybyTag.closeFlyby,
        '2015 TB145': FlybyTag.justPassing,
        '2010 WC9': FlybyTag.closeFlyby,
        '2001 FO32': FlybyTag.closeFlyby,
        '2005 YU55': FlybyTag.closeFlyby,
        '2019 OK': FlybyTag.closeFlyby,
        '2018 LF16': FlybyTag.justPassing,
        '2013 TX68': FlybyTag.justPassing,
      };
      for (final Asteroid a in kFallbackAsteroids) {
        expect(flybyTag(a), protoTags[a.name], reason: a.name);
      }
    });

    test('is independent of power', () {
      // `2015 TB145` is the strongest animal in the sample sky and is still
      // just passing; `2020 SW` is the second weakest and gets the wave. The
      // tag is about where a rock goes, not how impressive it is — conflating
      // them would make "close flyby" read as a danger ranking, which is the
      // exact thing CLAUDE.md:64 forbids.
      final Asteroid strongest = kFallbackAsteroids.reduce(
        (Asteroid a, Asteroid b) => power(a) > power(b) ? a : b,
      );
      expect(strongest.name, '2015 TB145');
      expect(flybyTag(strongest), FlybyTag.justPassing);
    });

    test('never says anything scary', () {
      // The guardrail (CLAUDE.md:64-66), pinned as a test because it is the
      // reason this returns a tag at all rather than exposing `hazardous`.
      for (final FlybyTag tag in FlybyTag.values) {
        expect(
          tag.label,
          isNot(
            matches(
              RegExp('hazard|danger|threat|risk|warn', caseSensitive: false),
            ),
          ),
        );
      }
      expect(FlybyTag.closeFlyby.label, '👋 close flyby');
      expect(FlybyTag.justPassing.label, 'just passing');
    });
  });

  group('distLabel and moonCompare', () {
    // Every expectation below was captured by slicing `index.html:420-426` out
    // of the prototype and evaluating it in Node, per the technique the
    // FALLBACK, naming, and power items all used. Guessed strings would pass a
    // careful read and still be wrong: `0.995` → "100% to Moon" and `9.99` →
    // "10.0× Moon" are both surprising, and both are what the prototype says.

    /// `(lunar distance, distLabel, moonCompare)` — the seven probes the plan
    /// item names, plus the rounding edges either side of both branches, plus
    /// every distinct shape the 14 sample rocks produce.
    ///
    /// One table rather than two maps: the two formatters are one number said
    /// two ways, so their expectations belong on one row where a reader can see
    /// they agree. (`const` also cannot key a map by `double`.)
    const List<(double, String, String)> cases = <(double, String, String)>[
      (0.07, '7% to Moon', '7% of the way to the Moon'),
      (0.995, '100% to Moon', '100% of the way to the Moon'),
      (1.0, '1.0× Moon', "1.0× the Moon's distance"),
      (9.99, '10.0× Moon', "10.0× the Moon's distance"),
      (10.0, '10× Moon', "10× the Moon's distance"),
      (12.4, '12× Moon', "12× the Moon's distance"),
      (60, '60× Moon', "60× the Moon's distance"),
      (0, '0% to Moon', '0% of the way to the Moon'),
      (0.005, '1% to Moon', '1% of the way to the Moon'),
      (0.999, '100% to Moon', '100% of the way to the Moon'),
      (1.05, '1.1× Moon', "1.1× the Moon's distance"),
      (9.949, '9.9× Moon', "9.9× the Moon's distance"),
      (99.5, '100× Moon', "100× the Moon's distance"),
    ];

    test('distLabel matches the prototype', () {
      for (final (double l, String expected, _) in cases) {
        expect(distLabel(l), expected, reason: 'distLabel($l)');
      }
    });

    test('moonCompare matches the prototype', () {
      for (final (double l, _, String expected) in cases) {
        expect(moonCompare(l), expected, reason: 'moonCompare($l)');
      }
    });

    test('both formatters agree on the number, and differ only in words', () {
      // The two share `_moonPercent`/`_moonMultiple` precisely so the compact
      // and long forms of one distance can never disagree about it. This is the
      // tripwire for anyone who re-inlines the `< 1` / `< 10` thresholds into
      // each function and lets them drift.
      for (final (double l, _, _) in cases) {
        final String number = RegExp(
          r'^[\d.]+',
        ).firstMatch(distLabel(l))!.group(0)!;
        expect(moonCompare(l), startsWith(number), reason: 'moonCompare($l)');
      }
    });

    test('the whole sample sky reads as Moon-relative, with no jargon', () {
      // The guardrail (CLAUDE.md:67-69), pinned across every rock the offline
      // app can show rather than on a probe: no raw km, no LD/AU, no
      // six-digit numbers. This is what these formatters exist for.
      for (final Asteroid a in kFallbackAsteroids) {
        for (final String label in <String>[
          distLabel(a.missLunar),
          moonCompare(a.missLunar),
        ]) {
          expect(label, contains('Moon'), reason: a.name);
          expect(
            label,
            isNot(
              matches(
                RegExp(
                  r'\bkm\b|\bLD\b|\bAU\b|lunar|astronomical',
                  caseSensitive: false,
                ),
              ),
            ),
            reason: a.name,
          );
        }
      }
    });
  });
}
