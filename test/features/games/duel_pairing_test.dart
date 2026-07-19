import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/duel_pairing.dart';

/// The rules of Power Duel with no widget in sight (`specs/04`, game 2) — the
/// deal's retry loop and the winner test.
///
/// **The give-up count is the thing this suite exists for.** A duel deal that
/// loops until it finds a well-separated pair is correct on any real sky and
/// hangs the UI thread forever on one where every animal has the same power —
/// rare, but a frozen app rather than a slightly unfair round. The cap is
/// asserted by *counting draws*, not by hoping a test times out.
void main() {
  group('dealDuelPair', () {
    test('draws two different animals separated by the power gap', () {
      // A varied sky, so the gap rule is satisfiable and the loop should find a
      // pair almost immediately. Repeated, because the deal is random: one pass
      // proves nothing about a rule that only bites on some draws.
      final List<Asteroid> sky = <Asteroid>[
        _rock('2020 AAA', diaMax: 3000, missLunar: 0.3, velKps: 30),
        _rock('2020 BBB', diaMax: 500, missLunar: 2, velKps: 20),
        _rock('2020 CCC', diaMax: 60, missLunar: 12, velKps: 12),
        _rock('2020 DDD', diaMax: 5, missLunar: 40, velKps: 6),
      ];
      final Random random = Random(7);

      for (int i = 0; i < 200; i++) {
        final DuelPair pair = dealDuelPair(sky, random);
        expect(
          identical(pair.a, pair.b),
          isFalse,
          reason: 'an animal cannot duel itself',
        );
        expect(
          (power(pair.a) - power(pair.b)).abs(),
          greaterThanOrEqualTo(kDuelMinPowerGap),
          reason: 'two cards a child cannot tell apart is not a fair question',
        );
      }
    });

    test('gives up after 50 attempts on a sky it cannot satisfy, rather than '
        'looping forever', () {
      // Every rock identical: no draw can ever clear the gap, so the loop can
      // only end by hitting its cap.
      final List<Asteroid> flatSky = <Asteroid>[
        _rock('2020 AAA', diaMax: 100, missLunar: 5, velKps: 15),
        _rock('2020 BBB', diaMax: 100, missLunar: 5, velKps: 15),
        _rock('2020 CCC', diaMax: 100, missLunar: 5, velKps: 15),
      ];
      final _CountingRandom random = _CountingRandom(Random(1));

      final DuelPair pair = dealDuelPair(flatSky, random);

      // Two draws per attempt, and not one attempt more than the cap.
      expect(random.draws, kDuelMaxDealAttempts * 2);
      // The child still gets a round — some pair, even a poor one, beats a
      // frozen screen.
      expect(flatSky, contains(pair.a));
      expect(flatSky, contains(pair.b));
    });

    test('deals the only qualifying pair when the sky offers just one', () {
      // Three near-identical rocks and one outlier: the only pairing that
      // clears the gap is the outlier against one of the others.
      final Asteroid outlier = _rock(
        '2020 ZZZ',
        diaMax: 3000,
        missLunar: 0.3,
        velKps: 30,
      );
      final List<Asteroid> sky = <Asteroid>[
        _rock('2020 AAA', diaMax: 100, missLunar: 5, velKps: 15),
        _rock('2020 BBB', diaMax: 100, missLunar: 5, velKps: 15),
        outlier,
      ];
      final Random random = Random(3);

      for (int i = 0; i < 50; i++) {
        final DuelPair pair = dealDuelPair(sky, random);
        expect(
          identical(pair.a, outlier) || identical(pair.b, outlier),
          isTrue,
          reason: 'no other pairing clears the gap',
        );
      }
    });

    test('a one-animal sky returns without hanging', () {
      // Defensive rather than reachable — the repository never yields fewer
      // than six (plan decision 10) — but the give-up is what makes it safe,
      // and a rule that only holds on good input is not a rule.
      final Asteroid lonely = _rock(
        '2020 AAA',
        diaMax: 100,
        missLunar: 5,
        velKps: 15,
      );
      final DuelPair pair = dealDuelPair(<Asteroid>[lonely], Random(1));

      expect(pair.a, same(lonely));
      expect(pair.b, same(lonely));
    });
  });

  group('winnerIsA', () {
    final Asteroid strong = _rock(
      '2020 AAA',
      diaMax: 3000,
      missLunar: 0.3,
      velKps: 30,
    );
    final Asteroid weak = _rock(
      '2020 DDD',
      diaMax: 5,
      missLunar: 40,
      velKps: 6,
    );

    test('the more powerful animal wins from either side of the board', () {
      expect(DuelPair(a: strong, b: weak).winnerIsA, isTrue);
      expect(DuelPair(a: weak, b: strong).winnerIsA, isFalse);
      expect(DuelPair(a: weak, b: strong).winner, same(strong));
    });

    test('a tie goes to A, so there is always exactly one right answer', () {
      // `danger(a) >= danger(b)` (`index.html:1048`). With `>` a tie would grade
      // *both* taps as wrong, which is the one outcome a kids-first game must
      // never produce.
      final Asteroid twin = _rock(
        '2020 BBB',
        diaMax: 5,
        missLunar: 40,
        velKps: 6,
      );
      expect(power(twin), power(weak));

      expect(DuelPair(a: weak, b: twin).winnerIsA, isTrue);
      expect(DuelPair(a: twin, b: weak).winnerIsA, isTrue);
    });

    test('compares unrounded power, not the stars the cards show', () {
      // Two rocks whose displayed ⭐ agree but whose real scores do not: the
      // prototype ranks on the raw double (`index.html:1048`), so this pair has
      // a winner even though the board looks tied. The deal's gap rule exists
      // to keep it off the screen — but the comparison must still be decisive.
      final Asteroid a = _rock(
        '2020 EEE',
        diaMax: 100,
        missLunar: 5,
        velKps: 15,
      );
      final Asteroid b = _rock(
        '2020 FFF',
        diaMax: 100,
        missLunar: 5,
        velKps: 15.02,
      );
      expect(powerStars(a), powerStars(b));
      expect(power(a), isNot(power(b)));

      expect(DuelPair(a: a, b: b).winnerIsA, isFalse);
      expect(DuelPair(a: b, b: a).winnerIsA, isTrue);
    });
  });
}

/// A [Random] that counts how many draws the deal made — the only way to assert
/// the attempt cap without relying on a test timeout.
class _CountingRandom implements Random {
  _CountingRandom(this._inner);

  final Random _inner;
  int draws = 0;

  @override
  int nextInt(int max) {
    draws++;
    return _inner.nextInt(max);
  }

  @override
  bool nextBool() => _inner.nextBool();

  @override
  double nextDouble() => _inner.nextDouble();
}

Asteroid _rock(
  String name, {
  required double diaMax,
  required double missLunar,
  required double velKps,
}) {
  return Asteroid(
    name: name,
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: false,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: velKps,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}
