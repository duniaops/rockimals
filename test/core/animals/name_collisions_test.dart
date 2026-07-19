import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// These tests pin the decision recorded on [kNamePool]: two rocks **may**
/// share an animal name, and the app accepts that rather than widening the
/// pool.
///
/// A decision that cannot fail is not recorded, which is why this file exists
/// as assertions rather than as prose in the doc comment. Each group pins one
/// clause of the argument, so the reasoning breaks loudly if the ground under
/// it moves:
///
///  * the collision is real and lives in the shipped sample data;
///  * the hash spreads evenly, so "use a better hash" is not the fix;
///  * the pool is what is small, so the rate follows from 24 alone;
///  * widening is hopeless at realistic feed sizes, which is *why* accepting
///    was the answer.
///
/// Nothing here asserts that duplicates are *harmless on screen* — they are
/// not, in the three games that show two names at once. That is a property of
/// the deal and is pinned wherever the deal is fixed.
void main() {
  /// Only [diaMax] decides a species and only the designation decides a first
  /// name, so a band is built by varying one and fixing the other.
  Asteroid rock(String name, double diaMax) => Asteroid(
    name: name,
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

  /// Provisional designations in the real `YYYY LX` / `YYYY LXn` shape, which
  /// is what the hash actually sees. Generated rather than sampled so the set
  /// is large enough to measure a rate on, and deterministic so a failure is
  /// reproducible.
  ///
  /// `I` is absent from the half-month letters in the real scheme, and is
  /// absent here for the same reason: a synthetic alphabet that fed the hash
  /// characters no designation contains would be measuring the wrong strings.
  List<String> designations({required int count}) {
    const String half = 'ABCDEFGHJKLMNOPQRSTUVWXY';
    final List<String> out = <String>[];
    for (int year = 2000; out.length < count; year++) {
      for (int a = 0; a < half.length && out.length < count; a++) {
        for (int b = 0; b < half.length && out.length < count; b++) {
          for (int n = 0; n <= 9 && out.length < count; n++) {
            out.add(
              n == 0
                  ? '$year ${half[a]}${half[b]}'
                  : '$year ${half[a]}${half[b]}$n',
            );
          }
        }
      }
    }
    return out;
  }

  group('the bundled sky', () {
    /// The concrete case the decision was made on. If a ladder boundary or a
    /// diameter ever moves, this stops being true and the doc's worked example
    /// stops matching the data it cites.
    test('collides exactly once, on Bruno the Bear', () {
      final Map<String, List<String>> byAnimalName = <String, List<String>>{};
      for (final Asteroid a in kFallbackAsteroids) {
        byAnimalName.putIfAbsent(critter(a).name, () => <String>[]).add(a.name);
      }

      final Map<String, List<String>> shared = <String, List<String>>{
        for (final MapEntry<String, List<String>> e in byAnimalName.entries)
          if (e.value.length > 1) e.key: e.value,
      };

      expect(shared, <String, List<String>>{
        'Bruno the Bear': <String>['2010 WC9', '2019 OK'],
      });
    });

    /// The other half of "nothing identifies a rock by its animal name": the
    /// designations stay unique even where the animal names do not, so the
    /// dedupe key and the follow key are unaffected by a homonym.
    test('has no duplicate designations despite the shared name', () {
      final Set<String> designations = <String>{
        for (final Asteroid a in kFallbackAsteroids) a.name,
      };
      expect(designations, hasLength(kFallbackAsteroids.length));
    });
  });

  group('the hash', () {
    /// The clause that rules out "fix the hash instead". `hashStr` is djb2 and
    /// `% 24` reads its low bits, which is exactly the shape that *can* be
    /// biased — so this is a real risk that turns out not to bite.
    ///
    /// The statistic is the decision-relevant one: the chance two rocks drawn
    /// from the population land on the same name. A chi-square would be
    /// enormous here purely because the sample is, and would say nothing about
    /// whether a child ever sees a duplicate.
    test('spreads real-format designations evenly across the pool', () {
      final List<String> names = designations(count: 20000);
      final List<int> counts = List<int>.filled(kNamePool.length, 0);
      for (final String d in names) {
        counts[hashStr(d) % kNamePool.length]++;
      }

      int sameNamePairs = 0;
      for (final int c in counts) {
        sameNamePairs += c * (c - 1);
      }
      final double measured =
          sameNamePairs / (names.length * (names.length - 1));
      final double ideal = 1 / kNamePool.length;

      // Within a tenth of the ideal rate. A pool that ignored half its names
      // would sit near 2x this; the measured excess is under 1%.
      expect(measured, closeTo(ideal, ideal * 0.1));
    });
  });

  group('the name space', () {
    /// The load-bearing arithmetic: a species is forced by size, so two rocks
    /// of one size draw from 24 names and never from 24 x 8. This is what
    /// makes the rate 1-in-24 rather than 1-in-192, and it is the single fact
    /// the whole decision turns on.
    test('offers one band only the 24 names, not all 192 combinations', () {
      const double bearDiameter = 130;
      final Set<String> namesInBand = <String>{
        for (final String d in designations(count: 5000))
          critter(rock(d, bearDiameter)).name,
      };

      expect(namesInBand, hasLength(kNamePool.length));
      expect(
        namesInBand.every((String n) => n.endsWith(' the Bear')),
        isTrue,
        reason: 'diameter alone should have fixed the species',
      );
    });

    /// Pigeonhole, asserted against `critter` rather than assumed: a band
    /// bigger than the pool *must* repeat. This is why no realistic widening
    /// helps — the bound moves with the pool size, and a busy day's band
    /// outgrows any pool a human would hand-write.
    test('must repeat once a band outgrows the pool', () {
      const double foxDiameter = 30;
      final List<String> names = <String>[
        for (final String d in designations(count: kNamePool.length + 1))
          critter(rock(d, foxDiameter)).name,
      ];

      expect(names.toSet().length, lessThan(names.length));
    });
  });

  group('sequential designations', () {
    /// **Why this file measures no birthday rate, recorded because the first
    /// draft tried to and got two different wrong answers.**
    ///
    /// Sampling bands out of a generated designation sequence measures the
    /// generator, not the naming. Consecutive designations gave a duplicate
    /// rate of 0% (the run below explains it); spreading each band across the
    /// sequence with a fixed stride gave 90% at a band of five, against a true
    /// 36% — aliasing, because a regular sequence beats against a mod-24
    /// bucket in whichever direction you walk it. Neither number says anything
    /// about a real sky.
    ///
    /// So the argument on [kNamePool] rests on the two things that *can* be
    /// asserted honestly — the pool is 24 wide per band, and the hash fills it
    /// evenly — with `C(k, 2) / 24` left as arithmetic from those under the
    /// assumption that a feed's designations are unrelated to one another. A
    /// real NeoWs window draws rocks discovered decades apart, so that holds;
    /// proving it needs live feed data, which no unit test has.
    ///
    /// The artifact itself is real and stable, and is pinned here so the next
    /// person to reach for a synthetic rate finds this instead of rediscovering
    /// it: djb2's final step is `(h * 33) ^ codeUnit`, so designations sharing
    /// every character but the last differ only in the low bits the `% 24`
    /// reads, and walk *consecutive* buckets rather than landing independently.
    test('never collide with one another', () {
      const double tigerDiameter = 100;
      final List<String> run = <String>[
        '2024 XA1',
        '2024 XA2',
        '2024 XA3',
        '2024 XA4',
        '2024 XA5',
      ];

      final List<String> names = <String>[
        for (final String d in run) critter(rock(d, tigerDiameter)).name,
      ];

      expect(
        names.toSet(),
        hasLength(run.length),
        reason: 'a discovery run should spread across the pool, not repeat',
      );
    });
  });
}
