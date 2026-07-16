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

  group('the ladder', () {
    test('has the prototype\'s eight rungs, in ascending order', () {
      expect(
        kAnimals.map((Animal a) => a.species),
        <String>[
          'Mouse',
          'Rabbit',
          'Fox',
          'Tiger',
          'Bear',
          'Elephant',
          'Dino',
          'Whale',
        ],
      );
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
}
